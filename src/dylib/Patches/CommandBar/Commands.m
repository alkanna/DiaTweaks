#import "CommandBar.h"

static NSString *DPCommandSymbol(NSString *title) {
    NSDictionary<NSString *, NSString *> *symbols = @{
        @"Settings": @"gearshape", @"New Window": @"macwindow.badge.plus", @"New Tab": @"plus.square",
        @"Close Tab": @"xmark.square", @"Reopen Closed Tab": @"arrow.uturn.backward.square", @"Print": @"printer",
        @"Copy URL": @"link", @"Find": @"magnifyingglass", @"Reload": @"arrow.clockwise", @"Downloads": @"arrow.down.circle",
        @"History": @"clock", @"Bookmarks": @"bookmark", @"Extensions": @"puzzlepiece.extension", @"Quit Dia": @"power",
        @"Zoom In": @"plus.magnifyingglass", @"Zoom Out": @"minus.magnifyingglass", @"Developer Tools": @"hammer", @"Task Manager": @"chart.bar",
    };
    for (NSString *prefix in symbols) if ([title hasPrefix:prefix]) return symbols[prefix];
    return @"command";
}

static void DPWalkMenu(NSMenu *menu, NSString *parent, NSSet<NSString *> *topTitles, NSMutableSet<NSString *> *seen, NSMutableArray<DPBarItem *> *items) {
    NSSet<NSString *> *skipped = [NSSet setWithArray:@[@"Services", @"Open Recent", @"Help"]];
    [menu update];  // Runs Dia's validation, so isEnabled is current.
    for (NSMenuItem *entry in menu.itemArray) {
        if (entry.isSeparatorItem || entry.isHidden || !entry.title.length) continue;
        if (entry.submenu) {
            if (![skipped containsObject:entry.title]) DPWalkMenu(entry.submenu, entry.title, topTitles, seen, items);
            continue;
        }
        if (!entry.action || !entry.isEnabled || entry.action == @selector(makeKeyAndOrderFront:)) continue;  // That last one is the window list.
        NSString *title = [entry.title stringByReplacingOccurrencesOfString:@"…" withString:@""];
        if (![topTitles containsObject:parent]) title = [NSString stringWithFormat:@"%@ › %@", parent, title];
        if ([seen containsObject:title]) continue;
        [seen addObject:title];
        DPBarItem *item = [DPBarItem new];
        item.kind = DPBarKindCommand;
        item.title = title;
        item.detail = DPShortcutText(entry.keyEquivalent, entry.keyEquivalentModifierMask);
        item.menuItem = entry;
        item.symbol = DPCommandSymbol(title);
        [items addObject:item];
    }
}

NSArray<DPBarItem *> *DPBarLoadCommands(void) {
    NSMutableArray<DPBarItem *> *items = [NSMutableArray new];
    NSSet<NSString *> *topTitles = [NSSet setWithArray:[NSApp.mainMenu.itemArray valueForKey:@"title"]];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) if (top.submenu) DPWalkMenu(top.submenu, top.title, topTitles, seen, items);
    return items;
}

NSArray<DPBarItem *> *DPBarLoadPages(void) {
    NSArray<NSArray<NSString *> *> *pages = @[
        @[@"Chrome Flags", @"chrome://flags", @"flag"],
        @[@"Extensions", @"chrome://extensions", @"puzzlepiece.extension"],
        @[@"Downloads", @"chrome://downloads", @"arrow.down.circle"],
        @[@"History", @"chrome://history", @"clock"],
        @[@"Bookmarks", @"chrome://bookmarks", @"bookmark"],
        @[@"Passwords", @"chrome://password-manager", @"key"],
        @[@"Clear Browsing Data", @"chrome://settings/clearBrowserData", @"trash"],
        @[@"Privacy and Security", @"chrome://settings/privacy", @"hand.raised"],
        @[@"Site Settings", @"chrome://settings/content", @"slider.horizontal.3"],
        @[@"Cookies and Site Data", @"chrome://settings/cookies", @"circle.hexagongrid"],
        @[@"Search Engines", @"chrome://settings/searchEngines", @"magnifyingglass"],
        @[@"Autofill and Addresses", @"chrome://settings/addresses", @"person.text.rectangle"],
        @[@"Payment Methods", @"chrome://settings/payments", @"creditcard"],
        @[@"Version", @"chrome://version", @"info.circle"],
        @[@"GPU", @"chrome://gpu", @"cpu"],
        @[@"Inspect Devices", @"chrome://inspect", @"hammer"],
        @[@"Net Internals", @"chrome://net-internals", @"network"],
    ];
    NSMutableArray<DPBarItem *> *items = [NSMutableArray new];
    for (NSArray<NSString *> *page in pages) {
        DPBarItem *item = [DPBarItem new];
        item.kind = DPBarKindPage;
        item.title = page[0];
        item.url = page[1];
        item.symbol = page[2];
        [items addObject:item];
    }
    return items;
}
