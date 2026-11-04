#import "CommandBar.h"

@class DPBar;

@interface DPBarResults : NSView
@property (nonatomic, copy) NSArray<DPBarItem *> *items;
@property (nonatomic) NSInteger selected;
@property (nonatomic, weak) DPBar *bar;
- (DPBarItem *)itemAtRow:(NSInteger)row;
@end

@interface DPBar : NSObject <NSTextFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSVisualEffectView *background;
@property (nonatomic) BOOL hiding;  // Fading out. Still on screen but nothing should touch it.
@property (nonatomic, strong) NSTextField *field;
@property (nonatomic, strong) NSImageView *fieldIcon;
@property (nonatomic, strong) DPBarResults *results;
@property (nonatomic, strong) DPBarSources *sources;
@property (nonatomic, weak) NSWindow *host;
@property (nonatomic) BOOL opensNewTab;
@property (nonatomic, copy) NSString *typed;           // Without the inline completion.
@property (nonatomic) BOOL suppressCompletion;         // After a deletion.
@property (nonatomic, copy) NSString *completionURL;   // Cleared when the text is edited.
@property (nonatomic, copy) NSString *shownQuery;
@property (nonatomic, readonly) BOOL inUse;
- (void)close;
- (void)layoutForRows:(NSUInteger)rows;
@end

@interface DPBar (Animation)
- (void)prepareToAppear;
- (void)animateIn;
- (void)hide;
- (void)finishHiding;
@end

@interface DPBar (Input)
- (void)runQuery;
- (void)commitInNewTab:(BOOL)newTab;
- (void)updateFieldIcon;
- (void)activateRow:(NSInteger)row forceNewTab:(BOOL)forceNewTab;
- (NSImage *)iconForItem:(DPBarItem *)item;
@end

static const CGFloat DPBarRowHeight = 44, DPBarListInset = 8;

static inline BOOL DPBarIsDark(NSAppearance *appearance) {
    return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
}

static inline NSColor *DPBarColor(CGFloat darkWhite, CGFloat darkAlpha, CGFloat lightWhite, CGFloat lightAlpha) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        return DPBarIsDark(appearance) ? [NSColor colorWithWhite:darkWhite alpha:darkAlpha] : [NSColor colorWithWhite:lightWhite alpha:lightAlpha];
    }];
}
