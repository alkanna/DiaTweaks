#import "Bar.h"

extern DPPatch DPCommandBarAnimation;

static const NSTimeInterval DPBarOpenSeconds = 0.12, DPBarCloseSeconds = 0.12;

// Scale around the top centre or the field jumps.
static CATransform3D DPBarSmaller(NSView *view) {
    NSRect bounds = view.bounds;
    CATransform3D transform = CATransform3DMakeTranslation(NSMidX(bounds), NSMaxY(bounds), 0);
    transform = CATransform3DScale(transform, 0.98, 0.98, 1);
    return CATransform3DTranslate(transform, -NSMidX(bounds), -NSMaxY(bounds), 0);
}

BOOL DPCommandBarAnimates(void) {
    return DPCommandBarAnimation.on && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

@implementation DPBar (Animation)

- (void)prepareToAppear {
    [NSAnimationContext beginGrouping];  // Stops a fade that's still going.
    NSAnimationContext.currentContext.duration = 0;
    self.panel.animator.alphaValue = DPCommandBarAnimates() ? 0 : 1;
    [NSAnimationContext endGrouping];
}

// The panel is already key here, so you can type during this.
- (void)animateIn {
    if (!DPCommandBarAnimates()) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = DPBarOpenSeconds;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.panel.animator.alphaValue = 1;
    }];
    CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"transform"];
    grow.fromValue = [NSValue valueWithCATransform3D:DPBarSmaller(self.background)];
    grow.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    grow.duration = DPBarOpenSeconds;
    grow.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.9 :0.3 :1];
    [self.background.layer addAnimation:grow forKey:@"grow"];
}

- (void)finishHiding {
    self.hiding = NO;
    [self.host removeChildWindow:self.panel];
    [self.panel orderOut:nil];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.background.layer removeAllAnimations];
    self.background.layer.opacity = 1;
    [CATransaction commit];
    self.panel.hasShadow = YES;
    self.panel.ignoresMouseEvents = NO;
}

- (void)hide {
    DPBarDropProfileSnapshot();
    if (!DPCommandBarAnimates()) return [self finishHiding];
    self.hiding = YES;
    self.panel.ignoresMouseEvents = YES;
    // The shadow won't fade with the layer, but fading the window instead stutters while a tab opens.
    self.panel.hasShadow = NO;
    NSView *view = self.background;
    __weak DPBar *weakSelf = self;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:^{
        DPBar *bar = weakSelf;
        if (bar.hiding) [bar finishHiding];
    }];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1;
    fade.toValue = @0;
    CABasicAnimation *shrink = [CABasicAnimation animationWithKeyPath:@"transform"];
    shrink.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    shrink.toValue = [NSValue valueWithCATransform3D:DPBarSmaller(view)];
    for (CABasicAnimation *animation in @[fade, shrink]) {
        animation.duration = DPBarCloseSeconds;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        animation.fillMode = kCAFillModeForwards;
        animation.removedOnCompletion = NO;
        [view.layer addAnimation:animation forKey:animation.keyPath];
    }
    view.layer.opacity = 0;
    [CATransaction commit];
    [CATransaction flush];  // Otherwise it wouldn't start until after the tab opens.
}

@end
