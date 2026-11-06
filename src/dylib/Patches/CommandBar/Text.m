#import "CommandBar.h"

@implementation DPBarItem
@end

static NSString *DPSplitHost(NSString *text, NSString **port) {
    NSCharacterSet *ends = [NSCharacterSet characterSetWithCharactersInString:@"/?#"];
    NSString *authority = [text componentsSeparatedByCharactersInSet:ends].firstObject.lowercaseString;
    *port = @"";
    if ([authority hasPrefix:@"["]) {
        NSRange close = [authority rangeOfString:@"]"];
        if (close.location == NSNotFound) return authority;
        NSString *rest = [authority substringFromIndex:NSMaxRange(close)];
        *port = [rest hasPrefix:@":"] ? [rest substringFromIndex:1] : rest;  // Junk after "]" fails the port check.
        return [authority substringToIndex:NSMaxRange(close)];
    }
    NSRange colon = [authority rangeOfString:@":" options:NSBackwardsSearch];
    if (colon.location == NSNotFound) return authority;
    *port = [authority substringFromIndex:colon.location + 1];
    return [authority substringToIndex:colon.location];
}

static BOOL DPIsDigits(NSString *text, NSUInteger maxLength) {
    return text.length && text.length <= maxLength && [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

// This machine or the local network, which mostly only speak http.
static BOOL DPIsIPv4(NSString *host) {
    NSArray<NSString *> *octets = [host componentsSeparatedByString:@"."];
    if (octets.count != 4) return NO;
    for (NSString *octet in octets) if (!DPIsDigits(octet, 3) || octet.integerValue > 255) return NO;
    return YES;
}

static BOOL DPIsLocalHost(NSString *host) {
    if ([host hasPrefix:@"["] || ![host containsString:@"."]) return YES;  // [::1], localhost, nas
    for (NSString *suffix in @[@".localhost", @".local", @".lan", @".home", @".home.arpa", @".internal", @".localdomain", @".test"])
        if ([host hasSuffix:suffix]) return YES;
    if (!DPIsIPv4(host)) return NO;
    NSArray<NSString *> *octets = [host componentsSeparatedByString:@"."];
    NSInteger a = octets[0].integerValue, b = octets[1].integerValue;
    return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) || (a == 169 && b == 254) || (a == 100 && b >= 64 && b <= 127);
}

// Never treat javascript: as an address, or a pasted script would run in the current tab.
static BOOL DPHasScheme(NSString *text) {
    static NSRegularExpression *scheme;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ scheme = [NSRegularExpression regularExpressionWithPattern:@"^([a-zA-Z][a-zA-Z0-9+.-]*):(//)?\\S*$" options:0 error:nil]; });
    NSTextCheckingResult *match = [scheme firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return NO;
    NSString *name = [text substringWithRange:[match rangeAtIndex:1]].lowercaseString;
    if ([name isEqualToString:@"javascript"]) return NO;
    return [match rangeAtIndex:2].location != NSNotFound
        || [@[@"about", @"chrome", @"file", @"mailto", @"data", @"blob", @"view-source", @"tel"] containsObject:name];
}

static BOOL DPLooksLikeAddress(NSString *text) {
    if (!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location != NSNotFound) return NO;
    if (DPHasScheme(text)) return YES;
    NSString *port, *host = DPSplitHost(text, &port);
    if (port.length && (!DPIsDigits(port, 5) || port.integerValue > 65535)) return NO;
    if ([host hasPrefix:@"["]) return [host hasSuffix:@"]"] && host.length > 2;
    if ([host isEqualToString:@"localhost"] || DPIsIPv4(host)) return YES;
    // Turns "me@example.com" and "c++.net" into searches.
    static NSCharacterSet *notAllowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
        [allowed addCharactersInString:@"-_"];
        notAllowed = allowed.invertedSet;
    });
    NSArray<NSString *> *labels = [host componentsSeparatedByString:@"."];
    for (NSString *label in labels) if (!label.length || [label rangeOfCharacterFromSet:notAllowed].location != NSNotFound) return NO;
    NSString *last = labels.lastObject;
    if (labels.count == 1) {
        // "nas:5000", but not "12:30" or "ratio:5".
        NSInteger number = port.integerValue;
        return !DPIsDigits(last, last.length) && (number >= 1024 || number == 80 || number == 443);
    }
    if (port.length) return YES;
    if ([last hasPrefix:@"xn--"]) return YES;
    // Letters only, otherwise "3.14" and "1.5kg" count as domains.
    // ponytail: file extensions, not the public suffix list. Ship that if other words slip through.
    return last.length >= 2 && [last rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet.invertedSet].location == NSNotFound
        && ![@[@"js", @"jsx", @"ts", @"tsx", @"css", @"html", @"json", @"txt", @"pdf", @"png", @"jpg", @"exe"] containsObject:last];
}

NSString *DPResolveURL(NSString *input) {
    NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!DPLooksLikeAddress(text)) return nil;
    if (DPHasScheme(text)) return text;
    NSString *port;
    return [(DPIsLocalHost(DPSplitHost(text, &port)) ? @"http://" : @"https://") stringByAppendingString:text];
}

NSString *DPSearchURL(NSString *engineTemplate, NSString *text) {
    static NSCharacterSet *allowed;
    static NSRegularExpression *placeholder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
        [set removeCharactersInString:@"&=+?#"];
        allowed = set;
        placeholder = [NSRegularExpression regularExpressionWithPattern:@"\\{[^}]*\\}" options:0 error:nil];
    });
    NSString *query = [text stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";  // nil for a lone surrogate.
    NSString *url = [engineTemplate ?: @"https://www.google.com/search?q={searchTerms}" stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:query];
    url = [url stringByReplacingOccurrencesOfString:@"{google:baseURL}" withString:@"https://www.google.com/"];
    // Strips Chromium placeholders like {google:RLZ}. Typed braces are already encoded.
    url = [placeholder stringByReplacingMatchesInString:url options:0 range:NSMakeRange(0, url.length) withTemplate:@""];
    while ([url hasSuffix:@"&"]) url = [url substringToIndex:url.length - 1];
    return url;
}

NSString *DPSearchEngineName(NSString *searchURL) {
    NSString *host = [NSURL URLWithString:searchURL].host;
    for (NSString *name in @[@"Google", @"DuckDuckGo", @"Bing", @"Brave", @"Ecosia", @"Kagi", @"Perplexity", @"Startpage"])
        if ([host.lowercaseString containsString:name.lowercaseString]) return name;
    return host ?: @"the web";
}

NSString *DPLikeEscape(NSString *text) {
    text = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    text = [text stringByReplacingOccurrencesOfString:@"%" withString:@"\\%"];
    return [text stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"];
}

NSString *DPPrettyURL(NSString *url) {
    for (NSString *prefix in @[@"https://", @"http://", @"www."])
        if ([url hasPrefix:prefix]) url = [url substringFromIndex:prefix.length];
    return [url hasSuffix:@"/"] ? [url substringToIndex:url.length - 1] : url;
}

NSString *DPShortcutText(NSString *key, NSEventModifierFlags modifiers) {
    if (!key.length) return @"";
    NSMutableString *text = [NSMutableString string];
    if (modifiers & NSEventModifierFlagControl) [text appendString:@"⌃"];
    if (modifiers & NSEventModifierFlagOption) [text appendString:@"⌥"];
    if (modifiers & NSEventModifierFlagShift) [text appendString:@"⇧"];
    if (modifiers & NSEventModifierFlagCommand) [text appendString:@"⌘"];
    NSDictionary *names = @{@"\r": @"↩", @"\t": @"⇥", @" ": @"Space", @"\x1b": @"⎋", @"\x7f": @"⌫",
                            [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey]: @"←",
                            [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey]: @"→",
                            [NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey]: @"↑",
                            [NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey]: @"↓"};
    [text appendString:names[key] ?: key.uppercaseString];
    return text;
}

static void DPAddTokens(NSMutableArray<NSString *> *tokens, NSString *text) {
    for (NSString *token in [text.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet])
        if (token.length) [tokens addObject:token];
}

// Site name and path words. Leaves out www and the TLD, or "com" would start every address,
// and the query, or "utm" and "q" would start every tracked link.
static NSArray<NSString *> *DPURLTokens(NSURL *parsed) {
    NSMutableArray<NSString *> *labels = [[parsed.host.lowercaseString componentsSeparatedByString:@"."] mutableCopy] ?: [NSMutableArray new];
    if (labels.count > 1) [labels removeLastObject];
    [labels removeObject:@"www"];
    NSMutableArray<NSString *> *tokens = [NSMutableArray new];
    DPAddTokens(tokens, [labels componentsJoinedByString:@"."]);
    DPAddTokens(tokens, parsed.path);
    return tokens;
}

// One substitution, insertion, deletion or swap of neighbors.
// Characters rather than strings, since this runs against most rows on every keystroke.
static BOOL DPOneEditApart(const unichar *a, NSUInteger m, const unichar *b, NSUInteger n) {
    if (m > n + 1 || n > m + 1) return NO;
    NSUInteger i = 0;
    while (i < m && i < n && a[i] == b[i]) i++;
    if (i == m && i == n) return YES;
    // Past the first difference, skip one character in the longer word, or in both when they're the same length.
    NSUInteger skipA = i + (m >= n), skipB = i + (n >= m);
    if (!memcmp(a + skipA, b + skipB, (m - skipA) * sizeof(unichar))) return YES;
    return m == n && i + 1 < m && a[i] == b[i + 1] && a[i + 1] == b[i] && !memcmp(a + i + 2, b + i + 2, (m - i - 2) * sizeof(unichar));
}

// Also against the start of a longer word, so a typo in a half typed word still finds it.
static BOOL DPTypoOf(NSString *word, NSArray<NSString *> *tokens) {
    unichar typed[64], token[65];
    NSUInteger m = word.length;
    if (m > 64) return NO;
    [word getCharacters:typed range:NSMakeRange(0, m)];
    for (NSString *candidate in tokens) {
        NSUInteger n = MIN(candidate.length, m + 1);
        if (n + 1 < m) continue;
        [candidate getCharacters:token range:NSMakeRange(0, n)];
        for (NSUInteger length = m - 1; length <= n; length++) if (DPOneEditApart(typed, m, token, length)) return YES;
    }
    return NO;
}

static BOOL DPAnyHasPrefix(NSArray<NSString *> *tokens, NSString *word) {
    for (NSString *token in tokens) if ([token hasPrefix:word]) return YES;
    return NO;
}

// What matching needs from a row, worked out once per row rather than on every keystroke.
@interface DPBarWords : NSObject {
  @public
    NSString *lowerTitle, *lowerURL, *host, *initials;
    NSArray<NSString *> *titleTokens, *urlTokens;
}
@end
@implementation DPBarWords
@end

static DPBarWords *DPWordsOf(NSString *title, NSString *url) {
    DPBarWords *words = [DPBarWords new];
    words->lowerTitle = title.lowercaseString ?: @"";
    words->lowerURL = url.lowercaseString ?: @"";
    NSURL *parsed = url ? [NSURL URLWithString:url] : nil;
    NSString *host = parsed.host.lowercaseString ?: @"";
    words->host = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
    NSMutableArray<NSString *> *titleTokens = [NSMutableArray new];
    DPAddTokens(titleTokens, words->lowerTitle);
    words->titleTokens = titleTokens;
    words->urlTokens = parsed ? DPURLTokens(parsed) : @[];
    NSMutableString *initials = [NSMutableString new];  // "nw" for New Window.
    for (NSString *token in titleTokens) [initials appendString:[token substringToIndex:1]];
    words->initials = initials;
    return words;
}

static DPBarMatch DPMatch(NSArray<NSString *> *words, DPBarWords *row) {
    if ([row->lowerTitle isEqualToString:[words componentsJoinedByString:@" "]]) return DPBarMatchExact;
    DPBarMatch match = DPBarMatchPrefix;
    for (NSString *word in words) {
        // The whole title too, for typed words with punctuation in them like "picture-in".
        BOOL startsWord = [row->host hasPrefix:word] || [row->lowerTitle hasPrefix:word]
            || [row->lowerTitle containsString:[@" " stringByAppendingString:word]] || (word.length >= 2 && [row->initials hasPrefix:word])
            || DPAnyHasPrefix(row->titleTokens, word) || DPAnyHasPrefix(row->urlTokens, word);
        if (startsWord) continue;
        if ([row->lowerTitle containsString:word] || [row->lowerURL containsString:word]) match = MIN(match, DPBarMatchContains);
        // ponytail: in memory only. History is filtered in SQL first, so a typo can't find a page that's only in history.
        else if (word.length >= 5 && (DPTypoOf(word, row->titleTokens) || DPTypoOf(word, row->urlTokens))) match = DPBarMatchTypo;
        else return DPBarMatchNone;
    }
    return match;
}

DPBarMatch DPBarMatchOf(NSArray<NSString *> *words, NSString *title, NSString *url) { return DPMatch(words, DPWordsOf(title, url)); }

DPBarMatch DPBarMatchItem(NSArray<NSString *> *words, DPBarItem *item) {
    if (!item.words) item.words = DPWordsOf(item.title, item.url);
    return DPMatch(words, item.words);
}

NSString *DPBarURLKey(NSString *url) {
    NSRange scheme = [url rangeOfString:@"://"];
    if (scheme.location == NSNotFound) return url;
    static NSCharacterSet *ends;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ends = [NSCharacterSet characterSetWithCharactersInString:@"/?#"]; });
    NSUInteger start = NSMaxRange(scheme);
    NSRange end = [url rangeOfCharacterFromSet:ends options:0 range:NSMakeRange(start, url.length - start)];
    NSUInteger split = end.location == NSNotFound ? url.length : end.location;
    NSString *key = [[url substringToIndex:split].lowercaseString stringByAppendingString:[url substringFromIndex:split]];
    while ([key hasSuffix:@"/"]) key = [key substringToIndex:key.length - 1];
    return key;
}

// 0: what you're clearly naming. 1: starts with what's typed. 2: contains it. 3: one typo away.
NSInteger DPBarTier(DPBarKind kind, DPBarMatch match, NSUInteger queryLength) {
    if (match == DPBarMatchNone) return -1;
    if (match == DPBarMatchExact) return 0;
    if (kind == DPBarKindCommand || kind == DPBarKindPage) {
        // One or two letters match half the menus, so leave most visited sites on top until there's a third.
        if (match == DPBarMatchContains) return -1;
        if (match == DPBarMatchTypo) return queryLength >= 5 ? 3 : -1;
        return queryLength >= 3 ? 0 : 2;
    }
    return match == DPBarMatchPrefix ? 1 : match == DPBarMatchContains ? 2 : 3;
}

// Each visit counts, halving every week, so this week's habits beat last month's.
double DPBarVisitFrecency(NSString *visits, double now, double visitCount) {
    double score = 0;
    const char *cursor = visits.UTF8String;
    while (cursor && *cursor) {
        char *end;
        double time = strtod(cursor, &end);
        if (*end != ':') break;
        long type = strtol(end + 1, &end, 10);
        double weight = type == 1 ? 2 : type == 8 ? 0 : 1;  // Typed counts double. Reloads don't count.
        score += weight * exp2(-MAX(0, now - time) / (7 * 8.64e10));
        cursor = *end == ',' ? end + 1 : NULL;
    }
    // Chromium only keeps 90 days of visits, so the all time count breaks ties between older pages.
    return log2(1 + score) * 1.5 + log2(1 + visitCount) * 0.1;
}

static const NSTimeInterval DPPickHalfLife = 14 * 86400;

static double DPPickScore(NSDictionary *pick, NSTimeInterval now) {
    return [pick[@"count"] doubleValue] * exp2(-MAX(0, now - [pick[@"time"] doubleValue]) / DPPickHalfLife);
}

NSArray<NSDictionary *> *DPBarAddPick(NSArray<NSDictionary *> *picks, NSString *input, NSString *key, NSString *space, NSTimeInterval now) {
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray new];
    double count = 0;
    space = space ?: @"";
    for (NSDictionary *pick in picks) {
        if (![pick isKindOfClass:NSDictionary.class]) continue;
        double score = DPPickScore(pick, now);
        if ([pick[@"input"] isEqual:input] && [pick[@"key"] isEqual:key] && [pick[@"space"] isEqual:space]) count = score;
        else if (score >= 0.1) [kept addObject:pick];  // About seven weeks for a single pick.
    }
    [kept insertObject:@{@"input": input, @"key": key, @"space": space, @"count": @(count + 1), @"time": @(now)} atIndex:0];
    // ponytail: a capped list scanned on every keystroke. Index it by first letter if it ever shows up in a profile.
    return [kept subarrayWithRange:NSMakeRange(0, MIN(kept.count, 1000))];
}

NSDictionary<NSString *, NSNumber *> *DPBarLearnedPicks(NSArray<NSDictionary *> *picks, NSString *query, NSString *space, NSTimeInterval now) {
    NSMutableDictionary<NSString *, NSNumber *> *learned = [NSMutableDictionary new];
    if (!query.length) return learned;
    for (NSDictionary *pick in picks) {
        if (![pick isKindOfClass:NSDictionary.class] || ![pick[@"space"] isEqual:space ?: @""] || ![pick[@"input"] isKindOfClass:NSString.class]
            || ![pick[@"input"] hasPrefix:query] || ![pick[@"key"] isKindOfClass:NSString.class]) continue;
        // "g", "gi" and "git" all picking the same page add up.
        learned[pick[@"key"]] = @(DPPickScore(pick, now) + learned[pick[@"key"]].doubleValue);
    }
    return learned;
}

// A recent or repeated pick goes first. A faded one only moves up among rows that match as well as it does.
// Every row for that page gets the same lift, so its tab still beats its history row.
void DPBarLiftLearned(NSArray<DPBarItem *> *items, NSDictionary<NSString *, NSNumber *> *learned) {
    if (!learned.count) return;
    for (DPBarItem *item in items) {
        NSNumber *pick = learned[item.url ? DPBarURLKey(item.url) : item.title ?: @""];
        if (!pick) continue;
        double score = pick.doubleValue;
        item.learned = score >= 0.75;  // About six days for a single pick, four weeks for three.
        if (item.learned) item.tier = 0;
        item.rank += item.learned ? 10 + score : score * 3;
    }
}

void DPBarSortItems(NSMutableArray<DPBarItem *> *items) {
    [items sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(DPBarItem *a, DPBarItem *b) {
        if (a.tier != b.tier) return a.tier < b.tier ? NSOrderedAscending : NSOrderedDescending;
        if (a.rank != b.rank) return a.rank > b.rank ? NSOrderedAscending : NSOrderedDescending;
        if (a.title.length != b.title.length) return a.title.length < b.title.length ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
}

void DPBarSortByRecency(NSMutableArray<DPBarItem *> *tabs, NSDictionary<NSString *, NSNumber *> *lastUsed) {
    [tabs sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(DPBarItem *a, DPBarItem *b) {
        return [(lastUsed[b.tabId] ?: @0) compare:lastUsed[a.tabId] ?: @0];
    }];
}

NSMutableArray<DPBarItem *> *DPBarArrangeTabs(NSArray<DPBarItem *> *tabs, NSString *space, NSString *windowId) {
    NSInteger (^distance)(DPBarItem *) = ^NSInteger(DPBarItem *tab) {
        return ([tab.space isEqual:space] ? 0 : 4) + (tab.windowShowsSpace ? 0 : 2) + ([tab.windowId isEqual:windowId] ? 0 : 1);
    };
    NSArray<DPBarItem *> *nearestFirst = [tabs sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(DPBarItem *a, DPBarItem *b) {
        return [@(distance(a)) compare:@(distance(b))];
    }];
    NSMutableArray<DPBarItem *> *arranged = [NSMutableArray new];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    BOOL label = NO;
    for (DPBarItem *tab in nearestFirst) {
        if (tab.space && ![tab.space isEqual:space]) label = YES;
        if ([seen containsObject:tab.tabId]) continue;
        if (tab.tabId) [seen addObject:tab.tabId];
        [arranged addObject:tab];
    }
    for (DPBarItem *tab in arranged) tab.showsSpace = label;
    return arranged;
}

BOOL DPBarReturnTakesCompletion(DPBarKind topRow, BOOL forceNewTab) {
    return forceNewTab || topRow != DPBarKindTab;
}

NSString *DPSuggestURL(NSString *suggestTemplate, NSString *text) {
    if (!suggestTemplate.length) return nil;
    // Google's template only works from inside Chrome, so this uses its public endpoint.
    if ([suggestTemplate hasPrefix:@"{google:baseSuggestURL}"]) suggestTemplate = @"https://suggestqueries.google.com/complete/search?client=firefox&oe=utf-8&q={searchTerms}";
    NSString *url = DPSearchURL(suggestTemplate, text);
    return [url hasPrefix:@"https://"] ? url : nil;  // Never send what's typed over plain http.
}

// OpenSearch format, ["query", ["one", "two"]].
NSArray<NSString *> *DPParseSuggestions(NSData *json, NSString *query) {
    id parsed = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if (![parsed isKindOfClass:NSArray.class] || [parsed count] < 2 || ![parsed[1] isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *suggestions = [NSMutableArray new];
    for (id suggestion in parsed[1]) {
        if (![suggestion isKindOfClass:NSString.class] || ![suggestion length] || [[suggestion lowercaseString] isEqualToString:query.lowercaseString]) continue;
        [suggestions addObject:suggestion];
        if (suggestions.count == 3) break;
    }
    return suggestions;
}
