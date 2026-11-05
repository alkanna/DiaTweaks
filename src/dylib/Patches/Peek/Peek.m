#import "Patches/Peek/Peek.h"

static NSURL *DPPeekHovered;
static __weak id DPPeekHoveredPage;

static BOOL DPPeekWanted(NSInteger disposition) {
    BOOL elsewhere = disposition == DPForegroundTab || disposition == DPBackgroundTab || disposition == DPPopup || disposition == DPNewWindow;
    return DPPeek.on && elsewhere && (NSEvent.modifierFlags & NSEventModifierFlagShift);
}

static void DPPeekOpenLater(id delegate, id source, NSURL *url) {
    NSWindow *window = NSApp.keyWindow;
    NSPoint origin = NSEvent.mouseLocation;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPeekOpen(window, url, origin, delegate, source); });
}

static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    if (!DPPeekWanted(disposition) || !(DPPeekShows(webContents) || DPPeekCanOpen(webContents)))
        return (void)DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, (NSInteger)DPIgnoreAction);
    if (DPPeekShows(webContents)) return DPPeekLoad(webContents, url);
    DPPeekOpenLater(self, webContents, url);
}

static NSInteger DPWebContent_decidePolicy(id self, SEL _cmd, id webContents, id action) {
    NSInteger disposition = [[action valueForKey:@"navigationDisposition"] integerValue];
    if (!DPPeekWanted(disposition)) {
        NSInteger policy = DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
        // Only a pinned tab turns a current-tab link into a new tab.
        if (!DPPeek.on || !DPPeekPinnedLinks.on || disposition != DPCurrentTab || policy != DPForegroundTab || !DPPeekCanOpen(webContents)) return policy;
        DPPeekOpenLater(self, webContents, [action valueForKey:@"url"]);
        return DPIgnoreAction;
    }
    if (DPPeekShows(webContents)) return DPCurrentTab;
    if (!DPPeekCanOpen(webContents)) return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    DPPeekOpenLater(self, webContents, [action valueForKey:@"url"]);
    return DPIgnoreAction;
}

static void DPPeekLookAhead(void) {
    NSEventModifierFlags mods = NSEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~NSEventModifierFlagCapsLock;
    id page = DPPeekHoveredPage;
    if (DPPeek.on && mods == NSEventModifierFlagShift && DPPeekHovered && page && !DPPeekShows(page) && DPPeekCanOpen(page))
        DPPeekWarm(NSApp.keyWindow, page, DPPeekHovered);
    else DPPeekCool();
}

static void DPWebContent_status(id self, SEL _cmd, id webContents, NSString *text) {
    DPCallOriginal(DPWebContent_status, self, webContents, text);
    NSURL *url = text.length ? [NSURL URLWithString:text] : nil;
    if (!url && webContents != DPPeekHoveredPage) return;  // Other pages, the warm one included, clear their own.
    DPPeekHovered = [@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString] ? url : nil;
    DPPeekHoveredPage = webContents;
    DPPeekLookAhead();
}

static void DPInstallPeek(void) {
    DPPeekInstallPages();
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate);
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPWebContent_decidePolicy);
        DPHook(DPDiaWebContent, @selector(webContents:didChangeStatusText:), (IMP)DPWebContent_status);
    });
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:^NSEvent *(NSEvent *event) {
        DPPeekLookAhead();
        return event;
    }];
}

static NSString *DPVerifyPeek(DPPatch *patch) {
    Class delegate = objc_getClass(DPDiaWebContent);
    if (class_getMethodImplementation(delegate, @selector(webContents:decidePolicyForNavigationAction:)) != (IMP)DPWebContent_decidePolicy)
        return @"link clicks don't reach Peek";
    if (class_getMethodImplementation(delegate, @selector(webContents:didCreateNewWebContent:targetURL:disposition:)) != (IMP)DPWebContent_didCreate)
        return @"new windows don't reach Peek";
    return nil;
}

DP_PATCH(DPPeek) {
    .key = @"peek",
    .order = 104,
    .title = @"Peek on Shift-Click",
    .detail = @"Shift-click a link to preview it in a card over the page, like Arc. Click outside, press Escape or ⌘W to close it, ⌘O to open it as a tab, or use the buttons beside it.",
    .symbol = @"eye.fill",
    .tint = @"systemMintColor",
    .section = @"Links",
    .classes = DPClasses(DPDiaBrowserContext, DPDiaWebContents, DPDiaWebContentsConfiguration, DPDiaContentPane),
    .install = DPInstallPeek,
    .verify = DPVerifyPeek,
    .rows = DPPeekSettingsRows,
    .hint = @"Tip: right after Dia starts, open or switch to any tab once to start Peek.",
};
