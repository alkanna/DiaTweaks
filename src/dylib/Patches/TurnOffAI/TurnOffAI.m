#import "TurnOffAI.h"

#define DPDiaCapabilitiesToolbar "_TtC23AssistantCapabilitiesUI32AssistantCapabilitiesToolbarView"
#define DPDiaCapabilitiesItem    "_TtC23AssistantCapabilitiesUI36AssistantCapabilitiesToolbarItemView"
#define DPDiaTabCardActions      "_TtC5TabUI21TabPopoverActionsView"
#define DPDiaSettingsHeader      "_TtC11Preferences25SettingsSectionHeaderView"
#define DPDiaPlaceholderText     "_TtC5ARCUI23TextViewWithPlaceholder"

BOOL DPIsAITitle(NSString *title) {
    if (![title isKindOfClass:NSString.class] || [title hasPrefix:@"Chat with Support"]) return NO;
    NSString *lower = title.lowercaseString;
    return [@[ @"Chat…", @"New Chat", @"Focus Chat", @"Send Chat Prompt Now", @"Open Daily Brief", @"Personalize Dia", @"Chat events", @"Daily report" ]
               containsObject:title]
        || [lower hasPrefix:@"chat with "] || [lower hasPrefix:@"ask dia"];
}

#pragma mark Views

static BOOL DPIsAIView(NSView *view) {
    return DPHasLabel(view, @"Chat with this tab") || DPIsKind(view, DPDiaLibraryButton) || DPIsKind(view, DPDiaLibraryCell)
        || DPIsKind(view, DPDiaSkillsSuggestions) || DPIsKind(view, DPDiaPersonalizeButton) || DPIsKind(view, DPDiaChatUsage)
        || DPIsKind(view, DPDiaCapabilitiesItem);
}

// The command bar and a tab's card are outside the hide hosts. The command bar's toolbar itself stays, so the buttons
// right of it don't slide left.
static void DPHost_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPHost_layout, self);
}

static NSHashTable<NSView *> *DPMorningBriefs;

// Settings' Morning Brief section: a heading and its switch in a stack of their own, hidden whole so no gap is left.
static void DPSettingsHeader_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSettingsHeader_layout, self);
    NSTextField *title = (NSTextField *)DPFindView(self, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    if (![title.stringValue isEqual:@"Morning Brief"] || !self.superview) return;
    [DPMorningBriefs addObject:self.superview];
    self.superview.hidden = DPTurnOffAI.on;
}

#pragma mark Placeholder

static NSHashTable<NSTextView *> *DPPlaceholderViews;

// "Ask anything…" in the command bar. Dia sets it from Swift, so it's changed where AppKit reads it to draw.
static NSAttributedString *DPPlaceholder_get(NSTextView *self, SEL _cmd) {
    NSAttributedString *dia = DPCallOriginal(DPPlaceholder_get, self);
    [DPPlaceholderViews addObject:self];
    if (!DPTurnOffAI.on || ![dia.string.lowercaseString hasPrefix:@"ask "]) return dia;
    NSMutableAttributedString *ours = [dia mutableCopy];
    [ours replaceCharactersInRange:NSMakeRange(0, ours.length) withString:@"Search or enter address"];
    return ours;
}

#pragma mark Menus

static NSHashTable<NSMenuItem *> *DPAIItems;
static char DPDiaHiddenKey;

// Dia shows and hides some of these itself, so what it asked for is kept and only added to.
static void DPItem_setHidden(NSMenuItem *self, SEL _cmd, BOOL hidden) {
    BOOL ai = [DPAIItems containsObject:self];
    if (ai) DPSet(self, &DPDiaHiddenKey, @(hidden));
    DPCallOriginal(DPItem_setHidden, self, hidden || (ai && DPTurnOffAI.on));
}

static void DPTrack(NSMenuItem *item) {
    if (!DPIsAITitle(item.title)) return;
    if (![DPAIItems containsObject:item]) {
        BOOL diaHidden = item.hidden;
        [DPAIItems addObject:item];
        DPSet(item, &DPDiaHiddenKey, @(diaHidden));
    }
    item.hidden = [DPGet(item, &DPDiaHiddenKey) boolValue];
}

static void DPTrackMenu(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        DPTrack(item);
        if (item.submenu) DPTrackMenu(item.submenu);
    }
}

static void DPMenu_addItem(NSMenu *self, SEL _cmd, NSMenuItem *item) {
    DPCallOriginal(DPMenu_addItem, self, item);
    DPTrack(item);
}

static void DPMenu_insertItem(NSMenu *self, SEL _cmd, NSMenuItem *item, NSInteger index) {
    DPCallOriginal(DPMenu_insertItem, self, item, index);
    DPTrack(item);
}

static const NSEventModifierFlags DPModifiers = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;

// Dia runs its shortcuts, ones set in its Shortcuts settings included, ahead of the menus, so a hidden item's still works.
static BOOL DPIsAIShortcut(NSEvent *event) {
    NSEventModifierFlags mods = event.modifierFlags & DPModifiers;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    for (NSMenuItem *item in DPAIItems)
        if (item.keyEquivalent.length && [item.keyEquivalent.lowercaseString isEqual:key] && (item.keyEquivalentModifierMask & DPModifiers) == mods) return YES;
    // ⌃⌘Return in the command bar sends what's typed to chat.
    BOOL inBar = [NSStringFromClass([event.window.firstResponder class]) hasPrefix:@"_TtCC15BoostCommandBar"];
    return inBar && (event.keyCode == 36 || event.keyCode == 76) && mods == (NSEventModifierFlagCommand | NSEventModifierFlagControl);
}

#pragma mark Patch

static void DPInstallTurnOffAI(void) {
    DPAIItems = [NSHashTable weakObjectsHashTable];
    DPPlaceholderViews = [NSHashTable weakObjectsHashTable];
    DPMorningBriefs = [NSHashTable weakObjectsHashTable];
    DPHookClass(NSMenu.class, @selector(addItem:), (IMP)DPMenu_addItem);
    DPHookClass(NSMenu.class, @selector(insertItem:atIndex:), (IMP)DPMenu_insertItem);
    DPHookClass(NSMenuItem.class, @selector(setHidden:), (IMP)DPItem_setHidden);
    DPHook(DPDiaCapabilitiesToolbar, @selector(layout), (IMP)DPHost_layout);
    DPHook(DPDiaTabCardActions, @selector(layout), (IMP)DPHost_layout);
    DPHook(DPDiaSettingsHeader, @selector(layout), (IMP)DPSettingsHeader_layout);
    DPHook(DPDiaPlaceholderText, @selector(placeholderAttributedString), (IMP)DPPlaceholder_get);
    DPInstallAIRows();
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return DPTurnOffAI.on && DPIsAIShortcut(event) ? nil : event;
    }];
    DPOnLaunch(^{ DPTrackMenu(NSApp.mainMenu); });
}

static void DPApplyTurnOffAI(DPPatch *patch) {
    DPApplyHides(patch);
    for (NSMenuItem *item in DPAIItems.allObjects) DPTrack(item);
    for (NSTextView *view in DPPlaceholderViews.allObjects) view.needsDisplay = YES;
    for (NSView *section in DPMorningBriefs.allObjects) section.hidden = patch->on;
    DPApplyAIRows();
}

DP_PATCH(DPTurnOffAI) {
    .key = @"turnOffAI",
    .order = 88,
    .section = @"Command Bar",
    .title = @"Turn Off AI",
    .detail = @"Hide every AI feature in Dia: chat and its buttons, menus and shortcuts, Skills, Ask Dia, Chat With This Tab, chat in the command bar, Morning Brief, and Settings' Apps and Skills. To send questions to search, set Address Bar to Prefer Search Engine in Advanced.",
    .symbol = @"bubble.left.and.exclamationmark.bubble.right.fill bubble.left.fill",
    .tint = @"systemOrangeColor",
    .hides = DPIsAIView,
    .install = DPInstallTurnOffAI,
    .apply = DPApplyTurnOffAI,
};
