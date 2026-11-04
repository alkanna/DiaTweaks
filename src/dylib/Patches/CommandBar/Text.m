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

DPBarMatch DPBarMatchOf(NSArray<NSString *> *words, NSString *title, NSString *url) {
    NSString *lowerTitle = title.lowercaseString ?: @"", *lowerURL = url.lowercaseString ?: @"";
    NSString *host = [NSURL URLWithString:url].host.lowercaseString ?: @"";
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    if ([lowerTitle isEqualToString:[words componentsJoinedByString:@" "]]) return DPBarMatchExact;
    DPBarMatch match = DPBarMatchPrefix;
    for (NSString *word in words) {
        if ([host hasPrefix:word] || [lowerTitle hasPrefix:word] || [lowerTitle containsString:[@" " stringByAppendingString:word]]) continue;
        if (![lowerTitle containsString:word] && ![lowerURL containsString:word]) return DPBarMatchNone;
        match = DPBarMatchContains;
    }
    return match;
}

// 0: what you're clearly naming. 1: starts with what's typed. 2: the rest.
NSInteger DPBarTier(DPBarKind kind, DPBarMatch match, NSUInteger queryLength) {
    if (match == DPBarMatchNone) return -1;
    if (match == DPBarMatchExact) return 0;
    if (kind == DPBarKindCommand || kind == DPBarKindPage) {
        // One or two letters match half the menus, so leave most visited sites on top until there's a third.
        if (match == DPBarMatchContains) return -1;
        return queryLength >= 3 ? 0 : 2;
    }
    return match == DPBarMatchPrefix ? 1 : 2;
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
