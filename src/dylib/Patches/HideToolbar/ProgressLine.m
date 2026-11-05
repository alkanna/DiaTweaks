#import "HideToolbar.h"

static const CGFloat DPGlowHeight = 24, DPLineHeight = 1;  // Dia's glow fades over its address field's height.
static const NSTimeInterval DPLineFade = 0.3, DPCycle = 2;
static char DPLineKey;

// Along the top of the pane: Dia's loading glow when its shader loads, else a hairline. It never takes the pointer.
@interface DPProgressLineView : NSView
@property (nonatomic, strong) CAMetalLayer *glow;
@property (nonatomic, strong) CALayer *fill;
@property (nonatomic, strong) NSTimer *frames;
@property (nonatomic) CGFloat fraction, shown;  // Where loading is, and where the glow has eased to.
@property (nonatomic) BOOL finishing;
@end

@implementation DPProgressLineView

- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.wantsLayer = YES;
    self.glow = DPProgressShaderLayer();
    if (self.glow) {
        self.glow.transform = CATransform3DMakeScale(1, -1, 1);  // Dia's glow rises from the bottom edge; this one hangs from the top.
        // Dia's glow fills its field to the edge; over a page it has to fade out instead of stopping in a line.
        CAGradientLayer *fade = [CAGradientLayer layer];
        fade.colors = @[(id)NSColor.blackColor.CGColor, (id)NSColor.clearColor.CGColor];
        fade.startPoint = CGPointMake(0.5, 0.35);
        fade.endPoint = CGPointMake(0.5, 1);
        self.glow.mask = fade;
        [self.layer addSublayer:self.glow];
    } else {
        self.fill = [CALayer layer];  // Not a view's own layer, so it animates its frame by itself.
        [self.layer addSublayer:self.fill];
    }
    return self;
}

- (void)dealloc { [_frames invalidate]; }

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    self.fill.backgroundColor = [NSColor.controlAccentColor CGColor];  // Follows the accent color, light and dark.
    [self draw];
}

- (NSView *)hitTest:(NSPoint)point { return nil; }

- (CGFloat)height { return self.glow ? DPGlowHeight : DPLineHeight; }

- (NSRect)fillFrame { return NSMakeRect(0, 0, round(NSWidth(self.bounds) * self.fraction), DPLineHeight); }

- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];  // Resizing with the window, not loading.
    self.fill.frame = self.fillFrame;
    self.glow.frame = self.bounds;
    self.glow.mask.frame = self.glow.bounds;
    self.glow.contentsScale = self.window.backingScaleFactor ?: 2;
    self.glow.drawableSize = CGSizeMake(NSWidth(self.bounds) * self.glow.contentsScale, NSHeight(self.bounds) * self.glow.contentsScale);
    [CATransaction commit];
    [self draw];
}

- (void)draw {
    if (!self.glow) return;
    simd_float3 primary, secondary;
    DPProgressColors(self.superview, DPChoice(&DPShowLoadingProgress), &primary, &secondary);
    CGFloat cycle = fmod(CACurrentMediaTime(), DPCycle) / DPCycle;
    DPDrawProgressShader(self.glow, self.shown, cycle, primary, secondary);
}

// The glow redraws each frame while it shows, easing toward the load's progress as Dia's does.
- (void)viewDidMoveToWindow {
    [self.frames invalidate];
    self.frames = nil;
    if (!self.window || !self.glow) return;
    __weak DPProgressLineView *weakSelf = self;
    self.frames = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        DPProgressLineView *me = weakSelf;
        me.shown += (me.fraction - me.shown) * 0.15;
        [me draw];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.frames forMode:NSRunLoopCommonModes];
}

- (void)setFraction:(CGFloat)fraction {
    _fraction = fraction;
    if (fraction == 0) self.shown = 0;
    self.fill.frame = self.fillFrame;
}

- (void)placeIn:(NSView *)pane {
    CGFloat height = self.height;
    self.frame = NSMakeRect(0, pane.isFlipped ? 0 : NSHeight(pane.bounds) - height, NSWidth(pane.bounds), height);
    self.autoresizingMask = NSViewWidthSizable | (pane.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
    if (self.superview != pane || pane.subviews.lastObject != self) [pane addSubview:self positioned:NSWindowAbove relativeTo:nil];
}
@end

static DPProgressLineView *DPLineIn(NSView *pane) {
    DPProgressLineView *line = DPGet(pane, &DPLineKey);
    return line.superview == pane ? line : nil;
}

void DPShowProgressLine(NSView *pane, CGFloat fraction) {
    DPProgressLineView *line = DPGet(pane, &DPLineKey);
    if (!line) DPSet(pane, &DPLineKey, line = [DPProgressLineView new]);
    if (!DPLineIn(pane) || line.finishing) {
        // A new load starts from the left, without animating back from where the last one ended.
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        line.finishing = NO;
        line.fraction = 0;
        [CATransaction commit];
        line.alphaValue = 1;
    }
    [line placeIn:pane];
    line.fraction = MAX(line.fraction, fraction);  // Never runs backwards within a load.
}

// Fills the line, then fades it out.
void DPFinishProgressLine(NSView *pane) {
    DPProgressLineView *line = DPLineIn(pane);
    if (!line || line.finishing) return;
    line.finishing = YES;
    line.fraction = 1;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = DPLineFade;
        line.animator.alphaValue = 0;
    } completionHandler:^{
        if (line.finishing) [line removeFromSuperview];  // Unless another load brought it back.
    }];
}

void DPRemoveProgressLine(NSView *pane) {
    DPProgressLineView *line = DPGet(pane, &DPLineKey);
    line.finishing = NO;
    [line removeFromSuperview];
}

BOOL DPShowsProgressLine(NSView *pane) {
    for (NSView *view in pane.subviews)
        if ([view isKindOfClass:DPProgressLineView.class] && view.alphaValue > 0) return YES;
    return NO;
}
