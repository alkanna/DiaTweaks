// Address parsing and match logic for the command bar. make test runs this.
#import "Patches/CommandBar/CommandBar.h"

static int failures;
#define CHECK(condition) do { if (!(condition)) { NSLog(@"FAIL %s", #condition); failures++; } } while (0)
#define SAME(actual, expected) do { NSString *got = (actual), *want = (expected); if (got != want && ![got isEqual:want]) { NSLog(@"FAIL %s: got %@, want %@", #actual, got, want); failures++; } } while (0)

int main(void) {
    SAME(DPResolveURL(@"github.com"), @"https://github.com");
    SAME(DPResolveURL(@"  github.com/a?b#c "), @"https://github.com/a?b#c");
    SAME(DPResolveURL(@"localhost:3000"), @"http://localhost:3000");
    SAME(DPResolveURL(@"nas:5000/x"), @"http://nas:5000/x");
    SAME(DPResolveURL(@"homeassistant.local:8123"), @"http://homeassistant.local:8123");
    SAME(DPResolveURL(@"192.168.1.2"), @"http://192.168.1.2");
    SAME(DPResolveURL(@"8.8.8.8"), @"https://8.8.8.8");
    SAME(DPResolveURL(@"8.8.8.8:80"), @"https://8.8.8.8:80");
    SAME(DPResolveURL(@"bücher.de"), @"https://bücher.de");
    SAME(DPResolveURL(@"xn--bcher-kva.xn--p1ai"), @"https://xn--bcher-kva.xn--p1ai");
    SAME(DPResolveURL(@"dev.example.com:8"), @"https://dev.example.com:8");
    SAME(DPResolveURL(@"my_app.dev"), @"https://my_app.dev");
    SAME(DPResolveURL(@"nas:80"), @"http://nas:80");
    SAME(DPResolveURL(@"[::1]:8080"), @"http://[::1]:8080");
    SAME(DPResolveURL(@"HTTP://x.y"), @"HTTP://x.y");
    SAME(DPResolveURL(@"chrome://flags"), @"chrome://flags");
    SAME(DPResolveURL(@"about:blank"), @"about:blank");
    SAME(DPResolveURL(@"view-source:https://x.y"), @"view-source:https://x.y");

    for (NSString *text in @[@"hello world", @"hello", @"", @"a.b", @".com", @"foo.", @"host:notaport", @"[::1", @"what is 2.5 kg",
                              @"12:30", @"ratio:5", @"3.14", @"2.50", @"1.5kg", @"v1.2.3", @"me@example.com", @"node.js", @"c++.net", @"a..b", @"300.1.1.1", @"nas:99999"])
        CHECK(!DPResolveURL(text));
    for (NSString *text in @[@"javascript:alert(1)", @"JavaScript:alert(1)", @"javascript://x%0aalert(1)"])
        CHECK(!DPResolveURL(text));

    SAME(DPSearchURL(nil, @"a&b c"), @"https://www.google.com/search?q=a%26b%20c");
    SAME(DPSearchURL(@"{google:baseURL}search?q={searchTerms}&{google:RLZ}", @"x"), @"https://www.google.com/search?q=x");
    SAME(DPSearchURL(@"https://k.io/?q={searchTerms}", @"{a}"), @"https://k.io/?q=%7Ba%7D");
    SAME(DPSearchEngineName(@"https://duckduckgo.com/?q=x"), @"DuckDuckGo");
    SAME(DPLikeEscape(@"50%_\\"), @"50\\%\\_\\\\");
    SAME(DPPrettyURL(@"https://www.a.io/b/"), @"a.io/b");
    SAME(DPShortcutText(@"t", NSEventModifierFlagCommand | NSEventModifierFlagShift), @"⇧⌘T");

    CHECK(DPBarMatchOf(@[@"git"], @"Home", @"https://www.github.com/") == DPBarMatchPrefix);
    CHECK(DPBarMatchOf(@[@"hub"], @"GitHub", @"https://github.com/") == DPBarMatchContains);
    CHECK(DPBarMatchOf(@[@"git", @"zzz"], @"GitHub", @"https://github.com/") == DPBarMatchNone);
    CHECK(DPBarMatchOf(@[@"settings"], @"Settings", nil) == DPBarMatchExact);
    CHECK(DPBarMatchOf(@[@"new", @"win"], @"New Window", nil) == DPBarMatchPrefix);
    CHECK(DPBarMatchOf(@[@"pulls"], @"Quarry", @"https://github.com/alkanna/quarry/pulls?q=open") == DPBarMatchPrefix);
    CHECK(DPBarMatchOf(@[@"inbox"], @"(3) Inbox - Mail", nil) == DPBarMatchPrefix);
    CHECK(DPBarMatchOf(@[@"nw"], @"New Window", nil) == DPBarMatchPrefix);
    CHECK(DPBarMatchOf(@[@"com"], @"Home", @"https://example.com/") == DPBarMatchContains);
    CHECK(DPBarMatchOf(@[@"setings"], @"Settings", nil) == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"reposiotry"], @"My repository list", nil) == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"githbu"], @"Home", @"https://github.com/") == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"repsoit"], @"Repository", nil) == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"stngs"], @"Settings", nil) == DPBarMatchNone);
    CHECK(DPBarMatchOf(@[@"githubx"], @"GitHub", nil) == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"xgithub"], @"GitHub", nil) == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"gitxub"], @"GitHub", nil) == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"gihub"], @"Nothing", @"https://github.com/") == DPBarMatchTypo);
    CHECK(DPBarMatchOf(@[@"gxxhub"], @"GitHub", nil) == DPBarMatchNone);
    CHECK(DPBarMatchOf(@[@"sett"], @"Seat", nil) == DPBarMatchNone);
    CHECK(DPBarTier(DPBarKindCommand, DPBarMatchTypo, 7) == 3);
    CHECK(DPBarTier(DPBarKindCommand, DPBarMatchTypo, 4) < 0);
    CHECK(DPBarTier(DPBarKindBookmark, DPBarMatchTypo, 6) == 3);

    // Chromium time is microseconds. This week's daily visits beat a heavy month ago.
    double now = 13438300000000000, day = 8.64e10;
    NSMutableArray *daily = [NSMutableArray new], *heavy = [NSMutableArray new];
    for (int i = 0; i < 7; i++) [daily addObject:[NSString stringWithFormat:@"%.0f:0", now - i * day]];
    for (int i = 0; i < 50; i++) [heavy addObject:[NSString stringWithFormat:@"%.0f:0", now - 30 * day - i * 1e9]];
    CHECK(DPBarVisitFrecency([daily componentsJoinedByString:@","], now, 7) > DPBarVisitFrecency([heavy componentsJoinedByString:@","], now, 400));
    CHECK(DPBarVisitFrecency([NSString stringWithFormat:@"%.0f:1", now], now, 1) > DPBarVisitFrecency([NSString stringWithFormat:@"%.0f:0", now], now, 1));
    CHECK(DPBarVisitFrecency([NSString stringWithFormat:@"%.0f:8", now], now, 1) < DPBarVisitFrecency([NSString stringWithFormat:@"%.0f:0", now], now, 1));
    CHECK(DPBarVisitFrecency(@"", now, 0) == 0);

    NSTimeInterval t = 1e9;
    NSArray *picks = DPBarAddPick(@[], @"gith", @"https://github.com/a/b", @"Space 1", t);
    picks = DPBarAddPick(picks, @"gith", @"https://github.com/a/b", @"Space 1", t);
    picks = DPBarAddPick(picks, @"git", @"https://github.com/a/c", @"Space 1", t);
    CHECK(picks.count == 2);
    NSDictionary *learned = DPBarLearnedPicks(picks, @"gi", @"Space 1", t);
    CHECK([learned[@"https://github.com/a/b"] doubleValue] > [learned[@"https://github.com/a/c"] doubleValue]);
    CHECK(!DPBarLearnedPicks(picks, @"gith", @"Space 1", t)[@"https://github.com/a/c"]);  // Typed past what was picked from.
    CHECK(DPBarLearnedPicks(picks, @"gi", @"Repos GH", t).count == 0);
    CHECK(DPBarLearnedPicks(picks, @"gi", @"Space 1", t + 200 * 86400).count == 2);  // Faded but still there until the next pick prunes.
    CHECK(DPBarAddPick(picks, @"x", @"https://x.test/", @"Space 1", t + 200 * 86400).count == 1);

    SAME(DPBarURLKey(@"https://Example.COM/"), @"https://example.com");
    SAME(DPBarURLKey(@"HTTPS://example.com/A/b/?Q=1"), @"https://example.com/A/b/?Q=1");
    SAME(DPBarURLKey(@"Settings"), @"Settings");

    DPBarItem *(^row)(DPBarKind, NSString *, NSString *, NSInteger) = ^(DPBarKind kind, NSString *title, NSString *url, NSInteger tier) {
        DPBarItem *item = [DPBarItem new];
        item.kind = kind;
        item.title = title;
        item.url = url;
        item.tier = tier;
        return item;
    };
    DPBarItem *tab = row(DPBarKindTab, @"Example", @"https://example.com/", 1), *visited = row(DPBarKindHistory, @"Example", @"https://example.com/", 1);
    DPBarItem *faded = row(DPBarKindHistory, @"Old", @"https://old.test/", 2), *command = row(DPBarKindCommand, @"Go Back", nil, 0);
    // A typed "example.com" was saved without its slash.
    NSArray *saved = DPBarAddPick(@[], @"ex", DPBarURLKey(@"https://example.com"), @"Space 1", t);
    saved = DPBarAddPick(saved, @"o", @"https://old.test", @"Space 1", t - 30 * 86400);
    saved = DPBarAddPick(saved, @"go", @"Go Back", @"Space 1", t);
    DPBarLiftLearned(@[tab, visited, faded, command], DPBarLearnedPicks(saved, @"e", @"Space 1", t));
    CHECK(tab.learned && tab.tier == 0 && visited.learned && tab.rank == visited.rank);
    DPBarLiftLearned(@[faded], DPBarLearnedPicks(saved, @"o", @"Space 1", t));
    CHECK(!faded.learned && faded.tier == 2 && faded.rank > 0);
    DPBarLiftLearned(@[command], DPBarLearnedPicks(saved, @"g", @"Space 1", t));
    CHECK(command.learned);

    CHECK(DPBarMatchOf(@[@"picture-in"], @"Picture-in-Picture", nil) == DPBarMatchPrefix);
    CHECK(DPBarMatchOf(@[@"utm"], @"Home", @"https://example.com/?utm_source=x") == DPBarMatchContains);
    DPBarItem *cached = row(DPBarKindBookmark, @"New Window", nil, 0);
    CHECK(DPBarMatchItem(@[@"nw"], cached) == DPBarMatchPrefix && cached.words && DPBarMatchItem(@[@"zz"], cached) == DPBarMatchNone);

    CHECK(DPBarTier(DPBarKindCommand, DPBarMatchPrefix, 3) == 0);
    CHECK(DPBarTier(DPBarKindCommand, DPBarMatchPrefix, 2) == 2);
    CHECK(DPBarTier(DPBarKindCommand, DPBarMatchContains, 5) < 0);
    CHECK(DPBarTier(DPBarKindHistory, DPBarMatchPrefix, 1) == 1);
    CHECK(DPBarTier(DPBarKindHistory, DPBarMatchContains, 5) == 2);
    CHECK(DPBarTier(DPBarKindTab, DPBarMatchExact, 5) == 0);
    CHECK(DPBarTier(DPBarKindTab, DPBarMatchNone, 5) < 0);

    CHECK(!DPBarReturnTakesCompletion(DPBarKindTab, NO));
    CHECK(DPBarReturnTakesCompletion(DPBarKindTab, YES));
    CHECK(DPBarReturnTakesCompletion(DPBarKindHistory, NO));

    NSMutableArray<DPBarItem *> *items = [NSMutableArray new];
    for (NSArray *row in @[@[@"weak but popular", @2, @50.0], @[@"rare", @1, @0.5], @[@"popular", @1, @9.0], @[@"New Incognito Window", @0, @0.0], @[@"New Window", @0, @0.0]]) {
        DPBarItem *item = [DPBarItem new];
        item.title = row[0];
        item.tier = [row[1] integerValue];
        item.rank = [row[2] doubleValue];
        [items addObject:item];
    }
    DPBarSortItems(items);
    SAME([[items valueForKey:@"title"] componentsJoinedByString:@","], @"New Window,New Incognito Window,popular,rare,weak but popular");

    NSMutableArray<DPBarItem *> *tabs = [NSMutableArray new];
    for (NSString *tabId in @[@"never1", @"old", @"never2", @"new"]) {
        DPBarItem *tab = [DPBarItem new];
        tab.tabId = tabId;
        [tabs addObject:tab];
    }
    DPBarSortByRecency(tabs, @{@"old": @1, @"new": @2});
    SAME([[tabs valueForKey:@"tabId"] componentsJoinedByString:@","], @"new,old,never1,never2");

    DPBarItem *(^spaceTab)(NSString *, NSString *, NSString *) = ^(NSString *tabId, NSString *space, NSString *windowId) {
        DPBarItem *tab = [DPBarItem new];
        tab.tabId = tabId;
        tab.space = space;
        tab.windowId = windowId;
        tab.windowShowsSpace = [windowId isEqual:@"shows"];
        return tab;
    };
    NSArray<DPBarItem *> *arranged = DPBarArrangeTabs(@[spaceTab(@"other", @"B", @"w1"), spaceTab(@"pinned", @"A", @"w2"), spaceTab(@"pinned", @"A", @"w1"), spaceTab(@"own", @"A", @"w1")], @"A", @"w1");
    SAME([[arranged valueForKey:@"tabId"] componentsJoinedByString:@","], @"pinned,own,other");
    SAME(arranged[0].windowId, @"w1");
    SAME(arranged[2].space, @"B");
    CHECK(arranged[2].showsSpace);
    NSArray<DPBarItem *> *oneSpace = DPBarArrangeTabs(@[spaceTab(@"own", @"A", @"w1")], @"A", @"w1");
    CHECK(!oneSpace[0].showsSpace);
    SAME(oneSpace[0].space, @"A");
    CHECK(DPBarArrangeTabs(@[spaceTab(@"other", @"B", @"w1")], @"A", @"w1")[0].showsSpace);
    NSArray<DPBarItem *> *shared = DPBarArrangeTabs(@[spaceTab(@"pinned", @"B", @"w1"), spaceTab(@"pinned", @"B", @"shows")], @"A", @"w1");
    CHECK(shared.count == 1);
    SAME(shared[0].windowId, @"shows");

    SAME(DPSuggestURL(@"{google:baseSuggestURL}{google:suggestPath}?q={searchTerms}", @"a b"), @"https://suggestqueries.google.com/complete/search?client=firefox&oe=utf-8&q=a%20b");
    SAME(DPSuggestURL(@"https://duckduckgo.com/ac/?q={searchTerms}&type=list", @"x"), @"https://duckduckgo.com/ac/?q=x&type=list");
    CHECK(!DPSuggestURL(@"http://example.com/?q={searchTerms}", @"x"));
    CHECK(!DPSuggestURL(@"", @"x"));
    SAME([DPParseSuggestions([@"[\"we\",[\"WE\",\"weather\",\"web\",\"west\",\"wet\"]]" dataUsingEncoding:NSUTF8StringEncoding], @"we") componentsJoinedByString:@","], @"weather,web,west");
    CHECK(DPParseSuggestions([@"{}" dataUsingEncoding:NSUTF8StringEncoding], @"x").count == 0);
    CHECK(DPParseSuggestions(nil, @"x").count == 0);

    if (!failures) NSLog(@"command bar text: ok");
    return failures != 0;
}
