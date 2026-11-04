#import "Bar.h"

static const CGFloat DPBarWidth = 760, DPBarInputHeight = 64, DPBarCornerRadius = 16;

@interface DPBarPanel : NSPanel
@end

@implementation DPBarPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface DPBar ()
@property (nonatomic, strong) NSBox *divider;
@property (nonatomic, strong) NSView *tint;
@end

@implementation DPBar

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _sources = [DPBarSources new];
    __weak DPBar *weakSelf = self;
    _sources.icons.changed = ^{
        weakSelf.results.needsDisplay = YES;
        [weakSelf updateFieldIcon];
    };

    _panel = [[DPBarPanel alloc] initWithContentRect:NSMakeRect(0, 0, DPBarWidth, DPBarInputHeight)
                                           styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskFullSizeContentView
                                             backing:NSBackingStoreBuffered defer:YES];
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.level = NSFloatingWindowLevel;
    _panel.delegate = self;
    _panel.releasedWhenClosed = NO;
    _panel.hidesOnDeactivate = YES;

    _background = [[NSVisualEffectView alloc] initWithFrame:_panel.contentView.bounds];
    _background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _background.state = NSVisualEffectStateActive;
    _background.wantsLayer = YES;
    _background.layer.cornerRadius = DPBarCornerRadius;
    _background.layer.masksToBounds = YES;
    _background.layer.borderWidth = 1;
    NSImage *corners = [NSImage imageWithSize:NSMakeSize(DPBarCornerRadius * 2 + 1, DPBarCornerRadius * 2 + 1) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:DPBarCornerRadius yRadius:DPBarCornerRadius] fill];
        return YES;
    }];
    corners.capInsets = NSEdgeInsetsMake(DPBarCornerRadius, DPBarCornerRadius, DPBarCornerRadius, DPBarCornerRadius);
    corners.resizingMode = NSImageResizingModeStretch;
    _background.maskImage = corners;
    _panel.contentView = _background;

    _tint = [[NSView alloc] initWithFrame:_background.bounds];
    _tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _tint.wantsLayer = YES;
    [_background addSubview:_tint];

    _fieldIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _fieldIcon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightRegular];
    _fieldIcon.contentTintColor = NSColor.secondaryLabelColor;
    [_background addSubview:_fieldIcon];

    _field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _field.bezeled = NO;
    _field.drawsBackground = NO;
    _field.focusRingType = NSFocusRingTypeNone;
    _field.font = [NSFont systemFontOfSize:22 weight:NSFontWeightMedium];
    _field.placeholderString = @"Search or enter URL";
    _field.cell.scrollable = YES;
    _field.cell.wraps = NO;
    _field.delegate = self;
    [_background addSubview:_field];

    _divider = [[NSBox alloc] initWithFrame:NSZeroRect];
    _divider.boxType = NSBoxSeparator;
    [_background addSubview:_divider];

    _results = [[DPBarResults alloc] initWithFrame:NSZeroRect];
    _results.bar = self;
    [_background addSubview:_results];
    return self;
}

- (void)showInWindow:(NSWindow *)window newTab:(BOOL)newTab {
    if (self.panel.isVisible) [self finishHiding];
    self.host = window;
    self.opensNewTab = newTab;
    self.panel.appearance = window.effectiveAppearance;
    // The HUD material is always dark.
    self.background.material = DPBarIsDark(window.effectiveAppearance) ? NSVisualEffectMaterialHUDWindow : NSVisualEffectMaterialPopover;
    [self.background.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.background.layer.borderColor = DPBarColor(1, 0.12, 0, 0.10).CGColor;
        self.tint.layer.backgroundColor = DPBarColor(0, 0.40, 1, 0.40).CGColor;
    }];
    DPBarDropProfileSnapshot();
    [self.sources prepareForWindow:window];

    NSString *url = newTab ? nil : self.sources.activeURL;
    NSString *initial = url.length && ![url hasPrefix:@"dia://"] ? url : @"";
    self.field.stringValue = initial;
    self.typed = initial;
    self.completionURL = self.shownQuery = nil;
    [self layoutForRows:0];
    [self prepareToAppear];
    [window addChildWindow:self.panel ordered:NSWindowAbove];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.field];
    ((NSTextView *)self.field.currentEditor).selectedTextAttributes = @{
        NSBackgroundColorAttributeName: DPBarColor(1, 0.22, 0, 0.12),
        NSForegroundColorAttributeName: NSColor.labelColor,
    };
    [self.field.currentEditor selectAll:nil];
    if (newTab || !initial.length) [self runQuery];
    else {
        self.results.items = @[];
        [self updateFieldIcon];
    }
    [self animateIn];  // After the query, since an empty field already has its rows by now.
}

- (void)layoutForRows:(NSUInteger)rows {
    NSRect host = self.host.frame;
    CGFloat width = MIN(DPBarWidth, NSWidth(host) - 80);
    CGFloat listHeight = rows ? rows * DPBarRowHeight + DPBarListInset * 2 : 0;
    CGFloat height = DPBarInputHeight + (rows ? 1 + listHeight : 0);
    CGFloat top = NSMaxY(host) - NSHeight(host) * 0.20;
    [self.panel setFrame:NSMakeRect(NSMidX(host) - width / 2, top - height, width, height) display:YES];

    self.fieldIcon.frame = NSMakeRect(22, height - DPBarInputHeight / 2 - 12, 24, 24);
    self.field.frame = NSMakeRect(58, height - DPBarInputHeight / 2 - 15, width - 58 - 22, 30);
    self.divider.hidden = rows == 0;
    self.divider.frame = NSMakeRect(0, height - DPBarInputHeight - 1, width, 1);
    self.results.frame = NSMakeRect(0, 0, width, listHeight);
}

- (BOOL)inUse { return self.panel.isVisible && !self.hiding; }

- (void)close {
    [self hide];
    [self.host makeKeyAndOrderFront:nil];
}

// Don't give key back to the host here, something else just took it.
- (void)windowDidResignKey:(NSNotification *)notification {
    if (self.inUse) [self hide];
}

@end

static DPBar *DPSharedBar(void) {
    static DPBar *bar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bar = [DPBar new]; });
    return bar;
}

BOOL DPCommandBarShow(NSWindow *window, BOOL newTab) {
    if (!DPIsKind(window, DPDiaWindow)) return NO;
    [DPSharedBar() showInWindow:window newTab:newTab];
    return YES;
}

BOOL DPCommandBarIsKey(void) { return DPSharedBar().panel.isKeyWindow; }
BOOL DPCommandBarIsShown(NSWindow *window) { return DPSharedBar().panel.parentWindow == window && !DPSharedBar().hiding; }
BOOL DPCommandBarIsAnimating(void) { return DPSharedBar().background.layer.animationKeys.count > 0; }
NSString *DPCommandBarText(void) { return DPSharedBar().field.stringValue; }

void DPCommandBarCommitInNewTab(void) { [DPSharedBar() commitInNewTab:YES]; }

void DPCommandBarClose(void) {
    if (DPSharedBar().inUse) [DPSharedBar() close];
}
