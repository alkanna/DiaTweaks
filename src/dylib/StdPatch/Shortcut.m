#import "StdPatch/StdPatch.h"
#import <Carbon/Carbon.h>

static const NSEventModifierFlags DPShortcutModifiers = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand;
static NSUInteger DPRecording;

static NSUserDefaults *DPShortcutDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return defaults;
}

static NSString *DPShortcutText(NSDictionary *shortcut) {
    if (![shortcut[@"key"] length]) return nil;
    NSEventModifierFlags flags = [shortcut[@"modifiers"] unsignedIntegerValue];
    return [NSString stringWithFormat:@"%@%@%@%@%@", flags & NSEventModifierFlagControl ? @"⌃" : @"", flags & NSEventModifierFlagOption ? @"⌥" : @"",
                                      flags & NSEventModifierFlagShift ? @"⇧" : @"", flags & NSEventModifierFlagCommand ? @"⌘" : @"", shortcut[@"key"]];
}

static NSString *DPKeyName(NSEvent *event) {
    NSDictionary *named = @{ @(kVK_Return) : @"↩", @(kVK_Tab) : @"⇥", @(kVK_Space) : @"Space", @(kVK_Delete) : @"⌫", @(kVK_ForwardDelete) : @"⌦",
                             @(kVK_LeftArrow) : @"←", @(kVK_RightArrow) : @"→", @(kVK_UpArrow) : @"↑", @(kVK_DownArrow) : @"↓",
                             @(kVK_F1) : @"F1", @(kVK_F2) : @"F2", @(kVK_F3) : @"F3", @(kVK_F4) : @"F4", @(kVK_F5) : @"F5", @(kVK_F6) : @"F6",
                             @(kVK_F7) : @"F7", @(kVK_F8) : @"F8", @(kVK_F9) : @"F9", @(kVK_F10) : @"F10", @(kVK_F11) : @"F11", @(kVK_F12) : @"F12" };
    NSString *name = named[@(event.keyCode)];
    if (name) return name;
    NSString *typed = event.charactersIgnoringModifiers.uppercaseString;
    return typed.length == 1 && [typed rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound ? typed : nil;
}

static NSDictionary *DPPatchShortcut(DPPatch *patch) {
    id saved = [DPShortcutDefaults() objectForKey:patch->shortcut];
    return [saved isKindOfClass:NSDictionary.class] ? saved : patch->defaultShortcut ? patch->defaultShortcut() : nil;
}

BOOL DPShortcutMatches(NSEvent *event, DPPatch *patch) {
    NSDictionary *shortcut = DPPatchShortcut(patch);
    return !DPRecording && shortcut[@"keyCode"] && [shortcut[@"keyCode"] integerValue] == event.keyCode &&
           [shortcut[@"modifiers"] unsignedIntegerValue] == (event.modifierFlags & DPShortcutModifiers);
}

static NSDictionary *DPMenuShortcut(NSMenuItem *item) {
    NSString *equivalent = item.keyEquivalent;
    if (equivalent.length != 1) return nil;
    unichar c = [equivalent characterAtIndex:0];
    NSDictionary *named = @{ @('\r') : @"↩", @('\t') : @"⇥", @(' ') : @"Space", @('\b') : @"⌫", @(0x7f) : @"⌫", @(NSDeleteFunctionKey) : @"⌦",
                             @(NSLeftArrowFunctionKey) : @"←", @(NSRightArrowFunctionKey) : @"→", @(NSUpArrowFunctionKey) : @"↑", @(NSDownArrowFunctionKey) : @"↓" };
    NSString *name = named[@(c)] ?: (c >= NSF1FunctionKey && c <= NSF12FunctionKey ? [NSString stringWithFormat:@"F%d", c - NSF1FunctionKey + 1] : equivalent.uppercaseString);
    NSEventModifierFlags flags = item.keyEquivalentModifierMask & DPShortcutModifiers;
    if (![equivalent isEqualToString:equivalent.lowercaseString]) flags |= NSEventModifierFlagShift;
    return @{ @"key" : name, @"modifiers" : @(flags) };
}

static BOOL DPSameShortcut(NSDictionary *a, NSDictionary *b) {
    return [a[@"key"] length] && [a[@"key"] isEqual:b[@"key"]] && [a[@"modifiers"] isEqual:b[@"modifiers"]];
}

static void DPMenuClashes(NSMenu *menu, NSDictionary *shortcut, NSString *shared, NSMutableArray<NSString *> *names) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.submenu) DPMenuClashes(item.submenu, shortcut, shared, names);
        else if (!(item.action && [NSStringFromSelector(item.action) isEqualToString:shared]) && DPSameShortcut(DPMenuShortcut(item), shortcut)) [names addObject:item.title];
    }
}

static NSArray<NSString *> *DPShortcutClashes(DPPatch *patch) {
    NSDictionary *shortcut = DPPatchShortcut(patch);
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    DPMenuClashes(NSApp.mainMenu, shortcut, patch->sharesShortcutWith, names);
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPPatches[i] != patch && DPPatches[i]->shortcut && DPSameShortcut(DPPatchShortcut(DPPatches[i]), shortcut)) [names addObject:DPPatches[i]->title];
    return names;
}

@interface DPShortcutButton : NSView
@property (nonatomic) DPPatch *patch;
@property (nonatomic, strong) NSTextField *label, *clash;
@property (nonatomic, strong) NSButton *clear;
@property (nonatomic, strong) id monitor;
@property (nonatomic) BOOL hovered;
@end

@implementation DPShortcutButton

- (instancetype)initWithPatch:(DPPatch *)patch clash:(NSTextField *)clash {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = patch;
    _clash = clash;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 6;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _label = [NSTextField labelWithString:@""];
    _label.font = [NSFont systemFontOfSize:13];
    _label.alignment = NSTextAlignmentCenter;
    _clear = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Clear"] target:self action:@selector(clearShortcut)];
    _clear.bordered = NO;
    _clear.contentTintColor = NSColor.tertiaryLabelColor;
    for (NSView *view in @[ _label, _clear ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:28], [self.widthAnchor constraintEqualToConstant:160],
        [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_clear.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6], [_clear.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                         owner:self userInfo:nil]];
    [self refresh];
    return self;
}

- (void)refresh {
    NSString *text = DPShortcutText(DPPatchShortcut(_patch));
    _label.stringValue = text ?: @"Add new…";
    _label.textColor = text ? NSColor.labelColor : NSColor.secondaryLabelColor;
    _clear.hidden = !text || !_hovered;
    // Worded like Dia's Shortcuts settings.
    NSArray<NSString *> *clashes = DPShortcutClashes(_patch);
    NSFont *font = [NSFont systemFontOfSize:11];
    NSMutableAttributedString *warning = [[NSMutableAttributedString alloc] initWithString:@"This shortcut conflicts with another shortcut:\n"
                                                                                attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName : NSColor.secondaryLabelColor }];
    [warning appendAttributedString:[[NSAttributedString alloc] initWithString:[clashes componentsJoinedByString:@", "]
                                                                    attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName : NSColor.systemRedColor }]];
    _clash.attributedStringValue = warning;
    _clash.hidden = !clashes.count;
    ((NSStackView *)_clash.superview).edgeInsets = NSEdgeInsetsMake(0, 0, clashes.count ? 8 : 0, 0);
    self.needsDisplay = YES;
}

- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor; }

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (void)mouseDown:(NSEvent *)event { [self.window makeFirstResponder:self]; }
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self refresh]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self refresh]; }

- (NSRect)focusRingMaskBounds { return self.bounds; }
- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill]; }

// Recording takes every key before Dia's menus and other shortcuts see it.
- (BOOL)becomeFirstResponder {
    if (![super becomeFirstResponder]) return NO;
    DPRecording++;
    __weak typeof(self) weak = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        DPShortcutButton *field = weak;
        if (!field || event.window != field.window || field.window.firstResponder != field) return event;
        [field record:event];
        return nil;
    }];
    return YES;
}

- (BOOL)resignFirstResponder {
    if (_monitor) {
        [NSEvent removeMonitor:_monitor];
        _monitor = nil;
        DPRecording--;
    }
    return [super resignFirstResponder];
}

- (void)record:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & DPShortcutModifiers;
    if (event.keyCode == kVK_Escape && !flags) return (void)[self.window makeFirstResponder:nil];
    if ((event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete) && !flags) return [self clearShortcut];
    NSString *name = DPKeyName(event);
    BOOL functionKey = name.length > 1 && [name hasPrefix:@"F"];
    // Needs a modifier other than Shift, so plain typing isn't taken.
    if (!name || (!(flags & ~NSEventModifierFlagShift) && !functionKey)) return NSBeep();
    [DPShortcutDefaults() setObject:@{ @"keyCode" : @(event.keyCode), @"modifiers" : @(flags), @"key" : name } forKey:_patch->shortcut];
    [self.window makeFirstResponder:nil];
    [self refresh];
}

- (void)clearShortcut {
    [DPShortcutDefaults() setObject:@{} forKey:_patch->shortcut];
    [self refresh];
}
@end

NSView *DPShortcutRow(DPPatch *patch) {
    NSTextField *clash = [NSTextField wrappingLabelWithString:@""];
    NSStackView *row = [NSStackView stackViewWithViews:@[ [NSTextField labelWithString:@"Shortcut"], [[DPShortcutButton alloc] initWithPatch:patch clash:clash] ]];
    row.distribution = NSStackViewDistributionEqualCentering;
    NSStackView *column = [NSStackView stackViewWithViews:@[ row, clash ]];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.alignment = NSLayoutAttributeLeading;
    [row.widthAnchor constraintEqualToAnchor:column.widthAnchor].active = YES;
    return column;
}
