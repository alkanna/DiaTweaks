#import "HideToolbar.h"

// Stays on while Hide toolbar is off, so the shortcut can bring it back.
extern DPPatch DPToggleToolbarVisibility;
static id DPKeyMonitor;
static NSString *const DPToggleToolbarShortcutKey = @"toggleToolbarShortcut";
static NSDictionary *DPDefaultToggleToolbarShortcut(void) { return @{ @"keyCode" : @2, @"modifiers" : @(NSEventModifierFlagControl), @"key" : @"D" }; }

static void DPInstallToggleToolbar(void) {
    DPKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (DPToggleToolbarVisibility.on && !event.isARepeat && DPShortcutMatches(event, DPToggleToolbarShortcutKey, DPDefaultToggleToolbarShortcut())) {
            DPSetPatch(&DPHideToolbar, !DPHideToolbar.on, YES);
            [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        }
        return event;
    }];
}

static void DPApplyToggleToolbar(DPPatch *patch) {}

static NSArray<NSView *> *DPToggleToolbarRows(void) {
    NSStackView *row = [NSStackView stackViewWithViews:@[ [NSTextField labelWithString:@"Shortcut"], DPShortcutField(DPToggleToolbarShortcutKey, DPDefaultToggleToolbarShortcut()) ]];
    row.distribution = NSStackViewDistributionEqualCentering;
    return @[ row ];
}

static NSString *DPVerifyToggleToolbar(DPPatch *patch) { return DPKeyMonitor ? nil : @"nothing listens for the shortcut"; }

DP_PATCH(DPToggleToolbarVisibility) {
    .key = @"toggleToolbarVisibility",
    .order = 35,
    .title = @"Toggle toolbar visibility",
    .detail = @"Hide or show the toolbar with a keyboard shortcut, ⌃D unless you set another.",
    .symbol = @"command",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"Showing the Toolbar",
    .classes = DPClasses(DPDiaContentPane, DPDiaToolbar),
    .install = DPInstallToggleToolbar,
    .rows = DPToggleToolbarRows,
    .apply = DPApplyToggleToolbar,
    .verify = DPVerifyToggleToolbar,
};
