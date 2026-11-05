#import "StdPatch/StdPatch.h"

// The "Personalization on for new chats" button Dia puts at the top right of the toolbar on new tab pages.
static BOOL DPIsPersonalizeButton(NSView *view) { return DPIsKind(view, DPDiaPersonalizeButton); }

DP_PATCH(DPHidePersonalizeButton) {
    .key = @"hidePersonalizeButton",
    .order = 95,
    .title = @"Hide Personalize Button",
    .detail = @"Hide the Personalization button at the top right of new tab pages.",
    .symbol = @"person.crop.circle.fill",
    .tint = @"systemGrayColor",
    .section = @"New Tab Page",
    .classes = DPClasses(DPDiaToolbar, DPDiaPersonalizeButton),
    .disabledBy = @"hideToolbar",
    .hides = DPIsPersonalizeButton,
};
