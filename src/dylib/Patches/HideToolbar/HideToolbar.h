// Shared by hide toolbar and its options, which only work on top of it.
#import "StdPatch/StdPatch.h"
#include <simd/simd.h>

extern DPPatch DPHideToolbar, DPRevealToolbarOnHover, DPShowToolbarWithSidebar, DPShowToolbarOnNewTab, DPPlainSelectedTab;
extern DPPatch DPPeekToolbarOnCopy, DPCopyToast, DPShowLoadingProgress;
extern NSHashTable<NSView *> *DPPanes;  // Every content pane laid out so far.

// Shows the hidden toolbar while the pointer is at the top of a pane, or in its place while an option keeps it there. One per pane.
@interface DPToolbarHover : NSObject
@property (nonatomic, weak) NSView *pane, *bar, *bookmarks;
@property (nonatomic, strong) NSTrackingArea *tracking;
@property (nonatomic, strong) NSTimer *animation, *hideTimer, *inPlaceAnimation, *peekTimer;
@property (nonatomic) BOOL revealed, inPlace, peeking;
@property (nonatomic) CGFloat progress, inPlaceProgress;  // How far the pointer, and an option keeping it in place, have brought the toolbar back.
+ (DPToolbarHover *)forPane:(NSView *)pane;  // nil until the pane is laid out.
+ (DPToolbarHover *)attachToPane:(NSView *)pane;
- (void)updateForBar:(NSView *)bar bookmarks:(NSView *)bookmarks;
- (void)peek;  // Reveals the hidden toolbar for a moment, as the pointer would.
- (void)endPeek;
@end

// Layout.m
NSRect DPLaidOutFrame(NSView *view);  // Where Dia put the view, before the patch moved it.
CGFloat DPTop(NSView *pane, NSRect r);  // Distances from the pane's top, whichever way it's flipped.
CGFloat DPBottom(NSView *pane, NSRect r);
NSView *DPBookmarksUnder(NSView *pane, NSView *bar);
BOOL DPKeptInPlace(NSView *pane);  // With the sidebar open, or on a new tab page, when their options are on.
NSString *DPVerifyKeptInPlace(DPPatch *patch);
void DPApplyToolbar(NSView *pane);
void DPApplyToolbarOpacity(DPToolbarHover *hover);
void DPRelayoutPanes(void);

// PlainTab.m
void DPRepaintTabs(NSWindow *window);  // After the toolbar's opacity changes.

// CopyToast.m
void DPShowCopyToast(NSView *pane, NSString *message);
void DPRemoveCopyToasts(void);
NSString *DPVerifyNoCopyToast(DPPatch *patch);

// ProgressLine.m
void DPShowProgressLine(NSView *pane, CGFloat fraction);
void DPFinishProgressLine(NSView *pane);  // Fills it, then fades it out.
void DPRemoveProgressLine(NSView *pane);
BOOL DPShowsProgressLine(NSView *pane);

// ProgressShader.m
CAMetalLayer *DPProgressShaderLayer(void);  // nil when Dia's loading shader can't be loaded.
void DPDrawProgressShader(CAMetalLayer *layer, CGFloat progress, CGFloat cycle, simd_float3 primary, simd_float3 secondary);
BOOL DPProgressColorSlots(NSUInteger slots[2]);  // Where the shader takes its two colors.

// ProgressColors.m
NSMenu *DPProgressColorChoices(void);
simd_float3 DPRGB(NSColor *color);
void DPProgressColors(NSView *pane, NSString *choice, simd_float3 *primary, simd_float3 *secondary);
void DPInstallProgressColors(void);
