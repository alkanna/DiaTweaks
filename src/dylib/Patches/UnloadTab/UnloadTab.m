#import "StdPatch/StdPatch.h"
#import <objc/message.h>

extern DPPatch DPUnloadTab;

enum { DPPageVisible = 2 };  // content::Visibility: hidden, occluded, visible.

static NSHashTable *DPPages;
static NSMapTable<id, NSString *> *DPUnloading;  // Page asked to unload -> its tab's content ID, until Chromium answers.
static NSMutableSet<NSString *> *DPUnloaded;     // Content IDs of tabs dimmed until they're opened again.

// The tab's one page, as Dia's tab controller knows it. A split tab has more than one, and isn't offered.
static id DPTabContent(NSView *tab) {
    NSDictionary *views = DPSwiftValue(tab, @"contentViews");
    if (views.count != 1) return nil;
    return DPSwiftValue(DPSwiftValue(views.allValues.firstObject, @"viewModel"), @"delegate");
}

static NSString *DPContentID(id content) { return [DPSwiftValue(content, @"contentID") description]; }

// Dia's tabs don't hold their page, so it's found by address, and only when no other loaded page shares it.
static id DPPageAt(NSURL *url) {
    id found = nil;
    for (id page in DPPages) {
        if (![[page valueForKey:@"url"] isEqual:url]) continue;
        if (found) return nil;
        found = page;
    }
    return found;
}

static BOOL DPTabOpen(NSView *tab) {
    NSString *state = [DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue") description];
    NSString *style = [[state componentsSeparatedByString:@"selectionStyle: "].lastObject substringToIndex:5];
    return ![style hasPrefix:@"nil"] && ![style hasPrefix:@"none"] && ![style hasPrefix:@"above"] && ![style hasPrefix:@"below"];
}

static void DPRelayoutTabs(void) {
    for (NSView *tab in DPFindViews(DPDiaTabView)) tab.needsLayout = YES;
}

static void DPPage_setVisibility(id self, SEL _cmd, NSInteger visibility) {
    [DPPages addObject:self];
    DPCallOriginal(DPPage_setVisibility, self, visibility);
    // Selecting a tab doesn't lay it out again, so its page coming back is the cue to undim it.
    if (visibility == DPPageVisible && DPUnloaded.count) dispatch_async(dispatch_get_main_queue(), ^{ DPRelayoutTabs(); });
}

// Chromium may decline, as for a page playing audio, so a tab only dims once it says the page went.
static void DPWebContent_finalizeDiscard(id self, SEL _cmd, id page, BOOL discarded) {
    DPCallOriginal(DPWebContent_finalizeDiscard, self, page, discarded);
    NSString *contentID = [DPUnloading objectForKey:page];
    if (!contentID) return;
    [DPUnloading removeObjectForKey:page];
    if (discarded) [DPUnloaded addObject:contentID];
    DPRelayoutTabs();
}

static NSMenu *DPTab_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPTab_menuForEvent, self, event);
    id content = menu && DPUnloadTab.on ? DPTabContent(self) : nil;
    NSString *contentID = DPContentID(content);
    id page = DPPageAt(DPSwiftValue(content, @"webContentURL"));
    if (!contentID || !page || [DPUnloaded containsObject:contentID]) return menu;
    NSMenuItem *item = DPMenuItem(@"Unload Tab", ^{
        [DPUnloading setObject:contentID forKey:page];
        [page performSelector:@selector(discard)];
    });
    item.image = [NSImage imageWithSystemSymbolName:@"moon.zzz" accessibilityDescription:nil];
    // Hidden by default, unlike Dia's own items. By name: CI's SDK predates macOS 27. 1 is NSMenuItemImageVisibilityVisible.
    if (@available(macOS 27, *)) [item setValue:@1 forKey:@"preferredImageVisibility"];
    item.enabled = ((NSInteger (*)(id, SEL))objc_msgSend)(page, @selector(visibility)) != DPPageVisible;  // Chromium keeps the page on screen.
    NSUInteger close = [menu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *it, NSUInteger i, BOOL *stop) { return [it.title isEqual:@"Close"]; }];
    [menu insertItem:item atIndex:close == NSNotFound ? (NSUInteger)menu.numberOfItems : close];
    return menu;
}

static void DPTab_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTab_layout, self);
    static char DPDimmedKey;
    BOOL dimmed = [DPGet(self, &DPDimmedKey) boolValue], dim = NO;
    if (DPUnloaded.count || dimmed) {
        NSString *contentID = DPContentID(DPTabContent(self));
        if (contentID && DPTabOpen(self)) [DPUnloaded removeObject:contentID];  // Opening it loads the page again.
        dim = DPUnloadTab.on && contentID && [DPUnloaded containsObject:contentID];
    }
    if (dim == dimmed) return;
    DPSet(self, &DPDimmedKey, dim ? @YES : nil);
    self.alphaValue = dim ? 0.5 : 1;
}

static void DPApplyUnloadTab(DPPatch *patch) { DPRelayoutTabs(); }

static void DPInstallUnloadTab(void) {
    DPPages = [NSHashTable weakObjectsHashTable];
    DPUnloading = [NSMapTable weakToStrongObjectsMapTable];
    DPUnloaded = [NSMutableSet set];
    DPHook(DPDiaWebContents, @selector(setVisibility:), (IMP)DPPage_setVisibility);
    DPHook(DPDiaTabView, @selector(menuForEvent:), (IMP)DPTab_menuForEvent);
    DPHook(DPDiaTabView, @selector(layout), (IMP)DPTab_layout);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:finalizeDiscardRequest:), (IMP)DPWebContent_finalizeDiscard);
    });
}

DP_PATCH(DPUnloadTab) {
    .key = @"unloadTab",
    .order = 86,
    .section = @"Tabs",
    .title = @"Unload Tabs",
    .detail = @"Right-click a tab and choose Unload Tab to free its memory. It stays in the sidebar, dimmed, and loads again when you open it.",
    .symbol = @"moon.zzz.fill",
    .tint = @"systemPinkColor",
    .classes = DPClasses(DPDiaWebContents, DPDiaTabView),
    .install = DPInstallUnloadTab,
    .apply = DPApplyUnloadTab,
};
