#import "CompactCommandBar.h"

static char DPFullSizeKey;

// The panel is also Dia's chat, so only the new tab page's and Command bar's are trimmed.
BOOL DPTrimsPanel(NSView *panel) {
    return DPIsKind(panel.superview.superview, DPDiaNewTabPage) || DPIsKind(panel.superview, "DPCommandBarOverlay");
}

// Command bar sets the size again as it lays out, so a trimmed size maps back to the full one before trimming.
static void DPAssistantPanel_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSValue *full = DPDiaValue(self, &DPFullSizeKey, [NSValue valueWithSize:size]);
    NSSize compact = DPTrimsPanel(self) ? DPCompactSize(self, full.sizeValue) : full.sizeValue;
    DPOverride(self, &DPFullSizeKey, full, [NSValue valueWithSize:compact]);
    DPSetTrim(self, full.sizeValue.height - compact.height);
    DPCallOriginal(DPAssistantPanel_setFrameSize, self, compact);
}

void DPInstallNewTabLayout(void) {
    DPHook(DPDiaAssistantPanel, @selector(setFrameSize:), (IMP)DPAssistantPanel_setFrameSize);
}
