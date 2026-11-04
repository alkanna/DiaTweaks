#import "CommandBar.h"
#include <math.h>

@implementation DPBarSources {
    NSArray<DPBarItem *> *_commands, *_pages, *_tabs, *_bookmarks;
    NSString *_searchTemplate, *_suggestTemplate, *_activeURL;
    BOOL _private;
    NSURLSession *_session;
    NSURLSessionTask *_suggestTask;
    dispatch_queue_t _queue;
    NSUInteger _latest;  // Written on main only.
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _icons = [DPBarIcons new];
    _queue = dispatch_queue_create("com.diapatches.commandbar.history", DISPATCH_QUEUE_SERIAL);
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;  // No cookies, nothing kept.
    configuration.timeoutIntervalForRequest = 2;
    _session = [NSURLSession sessionWithConfiguration:configuration];
    return self;
}

- (void)prepareForWindow:(NSWindow *)window {
    DPBarHoldScriptedWindows(YES);
    NSString *space = DPBarSpaceOfWindow(window);
    // Private windows get their own tabs and nothing from the profile. Nothing goes to the search engine either.
    _private = !space;
    DPBarNoteActiveTab(window);
    DPBarUseSpace(space);
    _icons.disabled = _private;
    _activeURL = DPBarURLOfWindow(window);
    _tabs = [DPBarLoadTabs(window, space) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"tabId != %@", DPBarActiveTabId(window)]];
    DPBarHoldScriptedWindows(NO);
    _commands = DPBarLoadCommands();
    _pages = DPBarLoadPages();
    _bookmarks = _private ? @[] : DPBarLoadBookmarks();
    NSString *suggest = nil;
    _searchTemplate = DPBarLoadSearchTemplate(&suggest);
    _suggestTemplate = _private ? nil : suggest;
    [_icons prepare];
}

- (NSString *)searchURLFor:(NSString *)text {
    return DPSearchURL(_searchTemplate, [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
}

static void DPAddMatches(NSMutableArray<DPBarItem *> *all, NSArray<DPBarItem *> *list, NSArray<NSString *> *words, NSUInteger queryLength) {
    for (DPBarItem *item in list) {
        item.tier = DPBarTier(item.kind, DPBarMatchOf(words, item.title, item.url), queryLength);
        item.rank = item.frecency;
        if (item.tier >= 0) [all addObject:item];
    }
}

static NSMutableArray<DPBarItem *> *DPRanked(NSMutableArray<DPBarItem *> *all) {
    DPBarSortItems(all);
    NSMutableArray<DPBarItem *> *ranked = [NSMutableArray new];
    NSMutableSet<NSString *> *keys = [NSMutableSet new];
    NSCountedSet *perSite = [NSCountedSet new], *perTitle = [NSCountedSet new];
    NSCharacterSet *slash = [NSCharacterSet characterSetWithCharactersInString:@"/"];
    for (DPBarItem *item in all) {
        NSString *key = item.url ? [item.url stringByTrimmingCharactersInSet:slash] : item.title;
        NSString *site = item.url ? [NSURL URLWithString:item.url].host : nil;
        BOOL history = item.kind == DPBarKindHistory;
        NSString *own = item.kind == DPBarKindTab && key ? [NSString stringWithFormat:@"%@ %@", item.space, key] : key;
        if (!own || [keys containsObject:own]) continue;
        if (history && site && [perSite countForObject:site] >= 2) continue;
        if (history && item.title && [perTitle countForObject:item.title] >= 2) continue;
        if (site) [perSite addObject:site];
        if (item.title) [perTitle addObject:item.title];
        [keys addObject:key];
        [keys addObject:own];
        [ranked addObject:item];
        if (ranked.count == DPBarMaxRows) break;
    }
    return ranked;
}

static DPBarItem *DPTypedItem(NSString *text, NSString *searchURL) {
    DPBarItem *item = [DPBarItem new];
    NSString *url = DPResolveURL(text);
    item.title = text;
    item.kind = url ? DPBarKindURL : DPBarKindSearch;
    item.url = url ?: searchURL;
    item.detail = url ? @"Open" : [@"Search " stringByAppendingString:DPSearchEngineName(searchURL)];
    item.symbol = url ? @"globe" : @"magnifyingglass";
    return item;
}

- (void)query:(NSString *)text done:(void (^)(NSArray<DPBarItem *> *))done {
    NSUInteger generation = ++_latest;
    [_suggestTask cancel];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *query = trimmed.lowercaseString;
    if (!query.length) return done([_tabs subarrayWithRange:NSMakeRange(0, MIN(DPBarMaxRows, _tabs.count))]);
    NSArray<NSString *> *words = [[query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                                  filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSArray<DPBarItem *> *commands = _commands, *pages = _pages, *tabs = _tabs, *bookmarks = _bookmarks;
    NSString *searchURL = [self searchURLFor:text];
    BOOL isPrivate = _private;
    dispatch_async(_queue, ^{
        // ponytail: racy read of _latest. Worst case is one wasted scan, since `done` rechecks on main.
        if (generation != self->_latest) return;
        NSMutableArray<DPBarItem *> *all = [NSMutableArray new];
        NSUInteger length = query.length;
        for (NSArray<DPBarItem *> *list in @[commands, pages, tabs, bookmarks]) DPAddMatches(all, list, words, length);
        NSArray<DPBarItem *> *history = isPrivate ? @[] : DPBarLoadHistory(words);
        if (generation != self->_latest) return;
        DPAddMatches(all, history, words, length);

        // If a page shows up twice, keep the tab, then the bookmark, and rank it like its history row.
        NSMutableDictionary<NSString *, DPBarItem *> *byURL = [NSMutableDictionary new];
        for (DPBarItem *item in history) if (item.url) byURL[item.url] = item;
        for (DPBarItem *item in all) {
            if (!byURL[item.url] || item.kind == DPBarKindHistory) continue;
            if (item.kind == DPBarKindTab) item.rank = MAX(item.rank, byURL[item.url].rank + 0.5);
            if (item.kind == DPBarKindBookmark) item.rank = MAX(item.rank, byURL[item.url].rank + 0.25);
        }

        NSMutableArray<DPBarItem *> *ranked = DPRanked(all);
        // An address comes first so Return opens it. A search comes second if the top result is strong.
        DPBarItem *typed = DPTypedItem(trimmed, searchURL);
        [ranked insertObject:typed atIndex:typed.kind == DPBarKindSearch && ranked.count && ranked[0].tier <= 1 ? 1 : 0];
        NSArray<DPBarItem *> *items = [ranked subarrayWithRange:NSMakeRange(0, MIN(DPBarMaxRows, ranked.count))];
        // Load these now so rows and icons show up together.
        for (DPBarItem *item in items)
            if (item.kind == DPBarKindHistory || item.kind == DPBarKindTab || item.kind == DPBarKindBookmark || item.kind == DPBarKindURL)
                [self->_icons preload:item.url space:item.space];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_latest) return;
            done(items);
            if (typed.kind == DPBarKindSearch) [self suggest:trimmed after:typed in:items generation:generation done:done];
        });
    });
}

// Wait a moment so the search engine doesn't get every keystroke.
- (void)suggest:(NSString *)text after:(DPBarItem *)typed in:(NSArray<DPBarItem *> *)items generation:(NSUInteger)generation done:(void (^)(NSArray<DPBarItem *> *))done {
    if (!DPCommandBarSuggests() || text.length < 2 || text.length > 100) return;
    NSURL *url = [NSURL URLWithString:DPSuggestURL(_suggestTemplate, text) ?: @""];
    if (!url.host) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->_latest) return;
        self->_suggestTask = [self->_session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSArray<NSString *> *suggestions = error ? @[] : DPParseSuggestions(data, text);
            if (!suggestions.count) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_latest) return;
                NSMutableArray<DPBarItem *> *merged = [items mutableCopy];
                NSUInteger index = [items indexOfObjectIdenticalTo:typed] + 1;
                for (NSString *suggestion in suggestions) {
                    DPBarItem *item = [DPBarItem new];
                    item.kind = DPBarKindSuggestion;
                    item.title = suggestion;
                    item.detail = typed.detail;
                    item.url = [self searchURLFor:suggestion];
                    item.symbol = @"magnifyingglass";
                    [merged insertObject:item atIndex:index++];
                }
                done([merged subarrayWithRange:NSMakeRange(0, MIN(DPBarMaxRows, merged.count))]);
            });
        }];
        [self->_suggestTask resume];
    });
}

- (NSString *)completionFor:(NSString *)text inItems:(NSArray<DPBarItem *> *)items url:(NSString **)url {
    NSString *query = text.lowercaseString;
    if (!query.length || [query rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location != NSNotFound) return nil;
    for (DPBarItem *item in items) {
        if (item.kind != DPBarKindHistory && item.kind != DPBarKindTab && item.kind != DPBarKindBookmark) continue;
        NSURLComponents *parts = [NSURLComponents componentsWithString:item.url];
        NSString *host = parts.host.lowercaseString;
        if (!host.length || !parts.scheme.length) return nil;
        NSString *site = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
        NSString *port = parts.port ? [@":" stringByAppendingString:parts.port.stringValue] : @"";
        site = [site stringByAppendingString:port];
        if (site.length <= query.length || ![site hasPrefix:query]) return nil;  // Only complete from the top-ranked page.
        // Keep http and the port. "homeassistant.local" on its own would turn into https.
        *url = [NSString stringWithFormat:@"%@://%@%@/", parts.scheme.lowercaseString, host, port];
        return site;
    }
    return nil;
}

@end
