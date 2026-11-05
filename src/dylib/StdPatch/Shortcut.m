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

static NSDictionary *DPShortcutFor(NSString *key, NSDictionary *fallback) {
    id saved = [DPShortcutDefaults() objectForKey:key];
    return [saved isKindOfClass:NSDictionary.class] ? saved : fallback;
}

static NSString *DPShortcutText(NSDictionary *shortcut) {
    if (![shortcut[@"key"] length]) return nil;
    NSEventModifierFlags flags = [shortcut[@"modifiers"] unsignedIntegerValue];
    return [NSString stringWithFormat:@"%@%@%@%@%@", flags & NSEventModifierFlagControl ? @"⌃" : @"", flags & NSEventModifierFlagOption ? @"⌥" : @"",
                                      flags & NSEventModifierFlagShift ? @"⇧" : @"", flags & NSEventModifierFlagCommand ? @"⌘" : @"", shortcut[@"key"]];
}

// What to show for the key, or nil for one a shortcut can't use.
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

BOOL DPShortcutMatches(NSEvent *event, NSString *key, NSDictionary *fallback) {
    NSDictionary *shortcut = DPShortcutFor(key, fallback);
    return !DPRecording && shortcut[@"keyCode"] && [shortcut[@"keyCode"] integerValue] == event.keyCode &&
           [shortcut[@"modifiers"] unsignedIntegerValue] == (event.modifierFlags & DPShortcutModifiers);
}

@interface DPShortcutButton : NSView
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSDictionary *fallback;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) NSButton *clear;
@property (nonatomic, strong) id monitor;
@property (nonatomic) BOOL hovered;
@end

@implementation DPShortcutButton

- (instancetype)initWithKey:(NSString *)key fallback:(NSDictionary *)fallback {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _key = key;
    _fallback = fallback;
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
    NSString *text = DPShortcutText(DPShortcutFor(_key, _fallback));
    _label.stringValue = text ?: @"Add new…";
    _label.textColor = text ? NSColor.labelColor : NSColor.secondaryLabelColor;
    _clear.hidden = !text || !_hovered;
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
    // A shortcut needs a modifier other than Shift, so typing letters isn't taken.
    if (!name || (!(flags & ~NSEventModifierFlagShift) && !functionKey)) return NSBeep();
    [DPShortcutDefaults() setObject:@{ @"keyCode" : @(event.keyCode), @"modifiers" : @(flags), @"key" : name } forKey:_key];
    [self.window makeFirstResponder:nil];
    [self refresh];
}

- (void)clearShortcut {
    [DPShortcutDefaults() setObject:@{} forKey:_key];
    [self refresh];
}
@end

NSView *DPShortcutField(NSString *key, NSDictionary *fallback) {
    return [[DPShortcutButton alloc] initWithKey:key fallback:fallback];
}
