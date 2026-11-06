#import "LittleDia.h"
#import <Carbon/Carbon.h>

static NSRect DPLittleDiaFrame(void) {
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *each in NSScreen.screens)
        if (NSMouseInRect(NSEvent.mouseLocation, each.frame, NO)) screen = each;
    NSRect visible = screen.visibleFrame;
    NSSize wanted = DPLittleDiaSize();
    NSSize size = NSMakeSize(round(MIN(wanted.width, NSWidth(visible) * 0.95)), round(MIN(wanted.height, NSHeight(visible) * 0.95)));
    return NSMakeRect(round(NSMidX(visible) - size.width / 2), round(NSMidY(visible) - size.height / 2), size.width, size.height);
}

// Links clicked in Dia, and any sent while Option is held, open as Dia would. So does anything that isn't a web page.
static NSURL *DPLittleDiaLink(NSAppleEventDescriptor *event) {
    if (event.eventClass != kInternetEventClass || event.eventID != kAEGetURL) return nil;
    NSString *string = [event paramDescriptorForKeyword:keyDirectObject].stringValue;
    NSURL *url = string ? [NSURL URLWithString:string] : nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqual:@"http"] && ![scheme isEqual:@"https"]) return nil;
    if ([event attributeDescriptorForKeyword:keySenderPIDAttr].int32Value == getpid()) return nil;
    if (NSEvent.modifierFlags & NSEventModifierFlagOption) return nil;
    return url;
}

static BOOL DPOpenInLittleDia(NSURL *url, void (^missed)(void)) {
    NSRect frame = DPLittleDiaFrame();
    CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame) - NSMaxY(frame);  // Chromium measures down from the top.
    NSDictionary *request = @{@"action" : @"open", @"url" : url.absoluteString, @"left" : @(NSMinX(frame)), @"top" : @(top),
                              @"width" : @(NSWidth(frame)), @"height" : @(NSHeight(frame))};
    DPNoteStackForLink();
    if (!DPSendToLittleDia(request)) return NO;
    DPExpectLittleDiaWindow(frame, missed);
    return YES;
}

// A link that opens Dia arrives before its extensions have loaded, so it waits for them, up to 10 seconds.
static void DPOpenWhenReady(NSURL *url, void (^fallback)(void), int tries) {
    if (DPOpenInLittleDia(url, fallback)) return;
    if (tries <= 0 || !DPLittleDiaStarting()) return fallback();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPOpenWhenReady(url, fallback, tries - 1); });
}

static void DPOpenURLEvents_handle(id self, SEL _cmd, NSAppleEventDescriptor *event, NSAppleEventDescriptor *reply) {
    NSURL *url = DPLittleDia.on ? DPLittleDiaLink(event) : nil;
    if (!url) return DPCallOriginal(DPOpenURLEvents_handle, self, event, reply);
    DPLinkArrived();
    DPOpenWhenReady(url, ^{ DPCallOriginal(DPOpenURLEvents_handle, self, event, [NSAppleEventDescriptor nullDescriptor]); }, 40);
}

void DPInstallLittleDiaRoute(void) {
    DPHook(DPDiaOpenURLEvents, @selector(handleEvent:withReplyEvent:), (IMP)DPOpenURLEvents_handle);
}
