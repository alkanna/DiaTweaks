#import "StdPatch/StdPatch.h"

// The Skills and Learn Skills pills under the new tab page's search field.
static BOOL DPIsSkillsSuggestions(NSView *view) { return DPIsKind(view, DPDiaSkillsSuggestions); }

DP_PATCH(DPHideSkillsSuggestions) {
    .key = @"hideSkillsSuggestions",
    .order = 94,
    .section = @"New Tab Page",
    .title = @"Hide Skills Suggestions",
    .detail = @"Hide the Skills and Learn Skills buttons under the search field on new tab pages.",
    .symbol = @"bolt.fill",
    .tint = @"systemGrayColor",
    .classes = DPClasses(DPDiaSkillsSuggestions),
    .hides = DPIsSkillsSuggestions,
};
