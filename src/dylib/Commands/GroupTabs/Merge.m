#import "GroupTabs.h"

// Without an apply, toggling eases and relayouts every patch. Group Tabs reads the switch when it runs.
static void DPApplyMergeSubdomains(DPPatch *patch) {}

DP_PATCH(DPGroupTabsMergeSubdomains) {
    .key = @"groupTabsMergeSubdomains",
    .order = 86,
    .title = @"Merge Subdomains",
    .detail = @"Group tabs from the same site together, so gist.github.com joins github.com.",
    .symbol = @"arrow.triangle.merge",
    .tint = @"systemPinkColor",
    .requires = @"groupTabsByDomain",
    .apply = DPApplyMergeSubdomains,
};
