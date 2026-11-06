#import "StdPatch/Hide.h"

static BOOL DPIsUpgradeBanner(NSView *view) { return DPIsKind(view, DPDiaChatUsage); }

// The command bar is outside the hide hosts.
static void DPChatUsage_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPChatUsage_layout, self);
}

static void DPInstallHideUpgradeBanner(void) {
    DPHook(DPDiaChatUsage, @selector(layout), (IMP)DPChatUsage_layout);
}

DP_PATCH(DPHideUpgradeBanner) {
    .key = @"hideUpgradeBanner",
    .order = 92,
    .section = @"Command Bar",
    .title = @"Hide Upgrade Banner",
    .detail = @"Hide the “Looking for chat?” upgrade banner under the command bar.",
    .symbol = @"crown.fill",
    .tint = @"systemOrangeColor",
    .classes = DPClasses(DPDiaChatUsage),
    .hides = DPIsUpgradeBanner,
    .install = DPInstallHideUpgradeBanner,
};
