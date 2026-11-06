#import "GroupTabs.h"

extern DPPatch DPGroupTabs;

// ⌘G and ⇧⌘G are Find Next and Previous; ⌃⌘N is Dia's New Group with Selected Tabs.
NSDictionary *DPDefaultGroupTabsShortcut(void) {
    return @{ @"keyCode" : @5, @"modifiers" : @(NSEventModifierFlagControl | NSEventModifierFlagShift), @"key" : @"G" };
}

void DPInstallGroupTabsShortcut(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (!DPGroupTabs.on || !DPShortcutMatches(event, &DPGroupTabs) || !DPCommandBrowser()) return event;
        if (!event.isARepeat) DPGroupTabsOnce();
        return nil;
    }];
}
