#import "StdPatch/StdPatch.h"

extern DPPatch DPProfileShortcuts;
static char DPSwappedKey;  // @[Dia's modifiers, ours]

static BOOL DPIsDigitShortcut(NSMenuItem *item, NSEventModifierFlags mods) {
    NSString *key = item.keyEquivalent;
    return key.length == 1 && [key characterAtIndex:0] >= '1' && [key characterAtIndex:0] <= '9' && item.keyEquivalentModifierMask == mods;
}

static NSMenuItem *DPFindItem(NSMenu *menu, BOOL (^match)(NSMenuItem *item)) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = match(item) ? item : item.submenu ? DPFindItem(item.submenu, match) : nil;
        if (found) return found;
    }
    return nil;
}

static void DPSwapItem(NSMenuItem *item) {
    NSArray<NSNumber *> *swapped = DPGet(item, &DPSwappedKey);
    BOOL ours = swapped && item.keyEquivalentModifierMask == swapped[1].unsignedIntegerValue;
    if (!DPProfileShortcuts.on) {
        if (ours) item.keyEquivalentModifierMask = swapped[0].unsignedIntegerValue;
        if (swapped) DPSet(item, &DPSwappedKey, nil);
        return;
    }
    if (ours) return;
    NSEventModifierFlags to;
    if (DPIsDigitShortcut(item, NSEventModifierFlagCommand)) to = NSEventModifierFlagControl;
    else if (DPIsDigitShortcut(item, NSEventModifierFlagControl)) to = NSEventModifierFlagCommand;
    else return;
    DPSet(item, &DPSwappedKey, @[ @(item.keyEquivalentModifierMask), @(to) ]);
    item.keyEquivalentModifierMask = to;
}

static void DPApplyProfileShortcuts(DPPatch *patch) {
    DPFindItem(NSApp.mainMenu, ^BOOL(NSMenuItem *item) {
        DPSwapItem(item);
        return NO;
    });
}

// A focused page takes ⌘ and a number before the menu bar sees it.
static void DPApplication_sendEvent(NSApplication *self, SEL _cmd, NSEvent *event) {
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    NSMenuItem *item = DPProfileShortcuts.on && event.type == NSEventTypeKeyDown && mods == NSEventModifierFlagCommand
        ? DPFindItem(NSApp.mainMenu, ^BOOL(NSMenuItem *candidate) {
              return DPGet(candidate, &DPSwappedKey) && DPIsDigitShortcut(candidate, NSEventModifierFlagCommand) && [candidate.keyEquivalent isEqualToString:event.charactersIgnoringModifiers];
          })
        : nil;
    if (!item.enabled) return DPCallOriginal(DPApplication_sendEvent, self, event);
    [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
}

static void DPInstallProfileShortcuts(void) {
    DPHookClass(NSApplication.class, @selector(sendEvent:), (IMP)DPApplication_sendEvent);
    DPOnLaunch(^{
        DPApplyProfileShortcuts(&DPProfileShortcuts);
        __block BOOL pending = NO;
        void (^changed)(NSNotification *) = ^(NSNotification *note) {
            if (pending || !DPProfileShortcuts.on) return;
            pending = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                pending = NO;
                DPApplyProfileShortcuts(&DPProfileShortcuts);
            });
        };
        for (NSNotificationName name in @[ NSMenuDidAddItemNotification, NSMenuDidChangeItemNotification ])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:changed];
    });
}

static NSString *DPVerifyProfileShortcuts(DPPatch *patch) {
    NSMenuItem *item = DPFindItem(NSApp.mainMenu, ^BOOL(NSMenuItem *candidate) { return [candidate.title isEqualToString:@"Go to Sidebar Item 1"]; });
    if (!item || DPIsDigitShortcut(item, patch->on ? NSEventModifierFlagControl : NSEventModifierFlagCommand)) return nil;
    return patch->on ? @"the sidebar items keep ⌘ and a number" : @"the sidebar items didn't get ⌘ back";
}

DP_PATCH(DPProfileShortcuts) {
    .key = @"profileShortcuts",
    .order = 79,
    .title = @"Switch Profiles with ⌘1–9",
    .detail = @"Press ⌘ and a number to switch to that profile, like Arc's spaces. The sidebar's items move to ⌃ and a number.",
    .symbol = @"command",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .install = DPInstallProfileShortcuts,
    .apply = DPApplyProfileShortcuts,
    .verify = DPVerifyProfileShortcuts,
};
