#import "CommandBar.h"

extern DPPatch DPCommandBar, DPCommandBarAddress, DPCommandBarSuggestions, DPCommandBarAllSpaces;

BOOL DPCommandBarSuggests(void) { return DPCommandBarSuggestions.on; }
BOOL DPCommandBarCoversAllSpaces(void) { return DPCommandBarAllSpaces.on; }

static BOOL DPAddressOn(void) { return DPCommandBar.on && DPCommandBarAddress.on; }

// Anything the field doesn't use would hit the tabs behind the bar.
static NSEvent *DPHandleBarKey(NSEvent *event, NSEventModifierFlags modifiers, NSString *key) {
    BOOL command = modifiers & NSEventModifierFlagCommand;
    if (!command) return modifiers == NSEventModifierFlagControl && [key isEqualToString:@"\t"] ? nil : event;  // Control-Tab changes tabs.
    if (modifiers == NSEventModifierFlagCommand) {
        if ([@[@"a", @"c", @"v", @"x", @"z", @"q", @"h"] containsObject:key]) return event;
        if ([key isEqualToString:@"\r"]) {  // AppKit doesn't send Command-Return to the field as a newline.
            DPCommandBarCommitInNewTab();
            return nil;
        }
        if ([@[@"t", @"l", @"w"] containsObject:key]) {
            DPCommandBarClose();
            return nil;
        }
    }
    if (modifiers == (NSEventModifierFlagCommand | NSEventModifierFlagShift) && [key isEqualToString:@"z"]) return event;
    // Dia's menus would grab these otherwise, like Back on Command-Left.
    unichar first = key.length ? [key characterAtIndex:0] : 0;
    if ((first >= NSUpArrowFunctionKey && first <= NSRightArrowFunctionKey) || first == 0x7f) [event.window.firstResponder keyDown:event];
    return nil;
}

static NSEvent *DPHandleKey(NSEvent *event) {
    // Holding Command-W shouldn't start closing real tabs after the bar is gone.
    static BOOL ownsRepeats;
    if (!event.isARepeat) ownsRepeats = NO;
    else if (ownsRepeats) return nil;
    if (!DPCommandBar.on) return event;
    // Just these four, so Caps Lock and Fn don't break the comparisons.
    NSEventModifierFlags modifiers = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    BOOL barIsKey = DPCommandBarIsKey();
    if (!barIsKey && modifiers != NSEventModifierFlagCommand) return event;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    NSEvent *result = event;
    if (barIsKey) result = DPHandleBarKey(event, modifiers, key);
    else {
        NSWindow *window = event.window ?: NSApp.keyWindow;
        if ([key isEqualToString:@"t"] && DPCommandBarShow(window, YES)) result = nil;
        else if ([key isEqualToString:@"l"] && DPAddressOn() && DPCommandBarShow(window, NO)) result = nil;
    }
    ownsRepeats = !result;
    return result;
}

static void DPNewTabCell_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPCommandBar.on || !DPCommandBarShow(self.window, YES)) DPCallOriginal(DPNewTabCell_mouseDown, self, event);
}

// Other buttons use this class too, hence the label check.
static void DPTabStripButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPCommandBar.on || !DPHasLabel(self, @"New tab") || !DPCommandBarShow(self.window, YES)) DPCallOriginal(DPTabStripButton_mouseDown, self, event);
}

static void DPNoteActiveTabSoon(void) {
    if (!DPCommandBar.on) return;
    static NSUInteger latest;
    NSUInteger mine = ++latest;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != latest) return;
        NSWindow *window = NSApp.keyWindow;
        if (DPIsKind(window, DPDiaWindow)) DPBarNoteActiveTab(window);
    });
}

static BOOL DPWindow_makeFirstResponder(NSWindow *self, SEL _cmd, NSResponder *responder) {
    if (self.isKeyWindow && responder != self.firstResponder) DPNoteActiveTabSoon();
    return DPCallOriginal(DPWindow_makeFirstResponder, self, responder);
}

static void DPInstallCommandBar(void) {
    DPHook(DPDiaNewTabButton, @selector(mouseDown:), (IMP)DPNewTabCell_mouseDown);
    DPHook(DPDiaTabSurfaceButton, @selector(mouseDown:), (IMP)DPTabStripButton_mouseDown);
    DPHook(DPDiaWindow, @selector(makeFirstResponder:), (IMP)DPWindow_makeFirstResponder);
    DPOnQuit(^{ DPBarDropProfileSnapshot(); });
    DPOnLaunch(^{
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPHandleKey(event); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPNoteActiveTabSoon(); }];
    });
}

static void DPApplyCommandBar(DPPatch *patch) {
    if (!DPCommandBar.on) DPCommandBarClose();
}

static BOOL DPIsVisibleBrowser(NSWindow *window) { return window.visible && DPIsKind(window, DPDiaWindow); }

static NSWindow *DPAnyBrowserWindow(void) {
    for (NSWindow *window in NSApp.windows) if (DPIsVisibleBrowser(window)) return window;
    return nil;
}

// If a Dia update breaks scripting or renames the window class, this is where it shows.
static NSString *DPVerifyOpens(BOOL newTab) {
    NSWindow *window = DPAnyBrowserWindow();
    if (!window) return @"no browser window";
    if (!DPCommandBarShow(window, newTab)) return @"the bar didn't open";
    BOOL shown = DPCommandBarIsShown(window);
    NSString *text = DPCommandBarText(), *url = DPBarURLOfWindow(window), *space = DPBarSpaceOfWindow(window);
    DPCommandBarClose();
    if (!shown) return @"the bar isn't over the window";
    if (DPCommandBarIsShown(window)) return @"the bar didn't close";
    if (!DPBarCanScript(window)) return @"Dia's scripting bridge has no active tab";
    if (!space) return @"Dia's scripting bridge reports no space for this window";
    if (!DPBarLoadCommands().count) return @"no commands in Dia's menus";
    if (!DPBarCanOpenTabDirectly()) return @"Dia no longer opens tabs directly, so the bar is using the slower script";
    if (newTab && text.length) return @"the new tab bar isn't empty";
    if (!newTab && text.length && ![text isEqualToString:url]) return @"the bar doesn't show the page's URL";
    return nil;
}

static NSString *DPVerifyCommandBar(DPPatch *patch) {
    Method row = class_getInstanceMethod(objc_getClass(DPDiaNewTabButton), @selector(mouseDown:));
    Method button = class_getInstanceMethod(objc_getClass(DPDiaTabSurfaceButton), @selector(mouseDown:));
    if (method_getImplementation(row) != (IMP)DPNewTabCell_mouseDown) return @"the New Tab row isn't hooked";
    if (method_getImplementation(button) != (IMP)DPTabStripButton_mouseDown) return @"the tab strip's + button isn't hooked";
    if (method_getImplementation(class_getInstanceMethod(objc_getClass(DPDiaWindow), @selector(makeFirstResponder:))) != (IMP)DPWindow_makeFirstResponder) return @"the window's first responder isn't hooked";
    return patch->on ? DPVerifyOpens(YES) : nil;
}

static NSString *DPVerifyCommandBarAddress(DPPatch *patch) {
    return DPAddressOn() ? DPVerifyOpens(NO) : nil;
}

static NSString *DPVerifyCommandBarAnimation(DPPatch *patch) {
    NSWindow *window = DPAnyBrowserWindow();
    if (!DPCommandBar.on || !window || !DPCommandBarShow(window, YES)) return nil;
    BOOL animating = DPCommandBarIsAnimating();
    DPCommandBarClose();
    if (animating != DPCommandBarAnimates()) return animating ? @"the bar animates with the option off" : @"the bar opened without animating";
    return DPCommandBarIsShown(window) ? @"the bar is still in use after closing" : nil;
}

static NSString *DPVerifyCommandBarAllSpaces(DPPatch *patch) {
    if (!patch->on) return nil;
    for (NSWindow *window in NSApp.windows)
        if (DPIsVisibleBrowser(window) && DPBarSpaceOfWindow(window))
            return DPBarCanListSpaces(window) ? nil : @"Dia's scripting bridge can't list or focus tabs by space";
    return nil;
}

DP_PATCH(DPCommandBar) {
    .key = @"commandBar",
    .order = 95,
    .title = @"Command bar",
    .detail = @"Press Command-T for an Arc-style bar over the page that finds tabs, history and bookmarks, runs Dia's menu commands, and completes addresses as you type.",
    .symbol = @"command",
    .tint = @"systemBlueColor",
    .section = @"Keyboard",
    .classes = DPClasses(DPDiaWindow, DPDiaNewTabButton, DPDiaTabSurfaceButton),
    .install = DPInstallCommandBar,
    .apply = DPApplyCommandBar,
    .verify = DPVerifyCommandBar,
};

DP_PATCH(DPCommandBarAddress) {
    .key = @"commandBarAddress",
    .defaultOn = YES,
    .order = 96,
    .title = @"Open with Command-L",
    .detail = @"Command-L opens the bar on the current page's address, and what you pick opens in the same tab.",
    .symbol = @"link",
    .tint = @"systemBlueColor",
    .requires = @"commandBar",
    .apply = DPApplyCommandBar,
    .verify = DPVerifyCommandBarAddress,
};

DP_PATCH(DPCommandBarAnimation) {
    .key = @"commandBarAnimation",
    .defaultOn = YES,
    .order = 97,
    .title = @"Animate opening and closing",
    .detail = @"Fade the bar in and out instead of snapping. You can type as soon as it opens, and the page takes your clicks as soon as it starts closing. Follows Reduce Motion.",
    .symbol = @"sparkles",
    .tint = @"systemBlueColor",
    .requires = @"commandBar",
    .apply = DPApplyCommandBar,
    .verify = DPVerifyCommandBarAnimation,
};

DP_PATCH(DPCommandBarSuggestions) {
    .key = @"commandBarSuggestions",
    .order = 98,
    .title = @"Show search suggestions",
    .detail = @"Ask your search engine for suggestions as you type, which sends it what you've typed. Never in private windows, and off if suggestions are off in Dia.",
    .symbol = @"text.magnifyingglass",
    .tint = @"systemBlueColor",
    .requires = @"commandBar",
};

DP_PATCH(DPCommandBarAllSpaces) {
    .key = @"commandBarAllSpaces",
    .defaultOn = YES,
    .order = 99,
    .title = @"Find tabs in all spaces",
    .detail = @"List open and pinned tabs from every space, labeled with their space. Picking one switches to that space.",
    .symbol = @"square.stack",
    .tint = @"systemBlueColor",
    .requires = @"commandBar",
    .verify = DPVerifyCommandBarAllSpaces,
};
