#import "StdPatch/Hide.h"

static BOOL DPIsPinnedTabOutline(NSView *view) { return DPIsKind(view, DPDiaPinnedTabOutline); }

// The outline is deeper than the hide hosts search.
static void DPPinnedTab_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPPinnedTab_layout, self);
}

static void DPInstallHidePinnedTabBorder(void) { DPHook(DPDiaPinnedTab, @selector(layout), (IMP)DPPinnedTab_layout); }

DP_PATCH(DPHidePinnedTabBorder) {
    .key = @"hidePinnedTabBorder",
    .order = 82,
    .title = @"Hide Pinned Tab Border",
    .detail = @"Remove the colored border around the selected pinned tab.",
    .symbol = @"pin.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaPinnedTab, DPDiaPinnedTabOutline),
    .hides = DPIsPinnedTabOutline,
    .install = DPInstallHidePinnedTabBorder,
};
