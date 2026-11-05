// Finds what keeps a window's layout dirty. AppKit aborts Dia once a layout pass repeats past the number of views in
// the window, and its crash report only shows AppKit's own frames. This counts, per view, how often it's marked dirty
// or moved within one turn of the run loop, and once one passes the limit, writes its ancestry and the backtrace that
// did it to layout-loops.txt beside the dylib. On with the developer tools.
#import "DevTools/DevTools.h"
#import <dlfcn.h>

static const NSUInteger DPLoopLimit = 150;
static const NSUInteger DPMaxReports = 12;
static NSMapTable<NSView *, NSMutableDictionary<NSString *, NSNumber *> *> *DPCounts;
static NSMutableSet<NSString *> *DPReported;
static NSString *DPReportPath;
static const NSUInteger DPRecentCount = 24;
static NSMutableArray<NSString *> *DPRecent;  // The latest frame changes, which show what a loop keeps undoing.

static void DPRemember(NSView *view, NSRect from, NSRect to) {
    if (!NSThread.isMainThread || !view.window) return;
    [DPRecent addObject:[NSString stringWithFormat:@"%s %p %@ -> %@ (in %s)", object_getClassName(view), view, NSStringFromRect(from), NSStringFromRect(to), object_getClassName(view.superview)]];
    if (DPRecent.count > DPRecentCount) [DPRecent removeObjectAtIndex:0];
}

static void DPReport(NSView *view, NSString *kind) {
    NSString *key = [NSString stringWithFormat:@"%s %@", object_getClassName(view), kind];
    if ([DPReported containsObject:key] || DPReported.count >= DPMaxReports) return;
    [DPReported addObject:key];
    NSMutableString *out = [NSMutableString stringWithFormat:@"== %@ %@ past %lu in one run loop turn\n", NSDate.date, key, (unsigned long)DPLoopLimit];
    for (NSView *up = view; up; up = up.superview) [out appendFormat:@"  in %s %@%@\n", object_getClassName(up), NSStringFromRect(up.frame), up.hidden ? @" hidden" : @""];
    [out appendString:@"  latest frame changes, oldest first:\n"];
    for (NSString *change in DPRecent) [out appendFormat:@"    %@\n", change];
    for (NSString *frame in NSThread.callStackSymbols) [out appendFormat:@"  %@\n", frame];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:DPReportPath];
    if (!file) {
        [NSFileManager.defaultManager createFileAtPath:DPReportPath contents:nil attributes:nil];
        file = [NSFileHandle fileHandleForWritingAtPath:DPReportPath];
    }
    [file seekToEndOfFile];
    [file writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static void DPCount(NSView *view, NSString *kind) {
    if (!NSThread.isMainThread || !view.window) return;
    NSMutableDictionary *counts = [DPCounts objectForKey:view];
    if (!counts) [DPCounts setObject:counts = [NSMutableDictionary dictionary] forKey:view];
    NSUInteger n = [counts[kind] unsignedIntegerValue] + 1;
    counts[kind] = @(n);
    if (n == DPLoopLimit) DPReport(view, kind);
}

static void DPView_setNeedsLayout(NSView *self, SEL _cmd, BOOL needs) {
    if (needs) DPCount(self, @"needsLayout");
    DPCallOriginal(DPView_setNeedsLayout, self, needs);
}

static void DPView_setNeedsUpdateConstraints(NSView *self, SEL _cmd, BOOL needs) {
    if (needs) DPCount(self, @"needsUpdateConstraints");
    DPCallOriginal(DPView_setNeedsUpdateConstraints, self, needs);
}

static void DPView_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    if (!NSEqualSizes(size, self.frame.size)) {
        DPRemember(self, self.frame, (NSRect){self.frame.origin, size});
        DPCount(self, @"setFrameSize");
    }
    DPCallOriginal(DPView_setFrameSize, self, size);
}

static void DPView_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    if (!NSEqualPoints(origin, self.frame.origin)) {
        DPRemember(self, self.frame, (NSRect){origin, self.frame.size});
        DPCount(self, @"setFrameOrigin");
    }
    DPCallOriginal(DPView_setFrameOrigin, self, origin);
}

void DPTraceLayoutLoops(void) {
    Dl_info dylib;
    dladdr((const void *)DPTraceLayoutLoops, &dylib);
    DPReportPath = [@(dylib.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"layout-loops.txt"];
    DPCounts = [NSMapTable weakToStrongObjectsMapTable];
    DPReported = [NSMutableSet set];
    DPRecent = [NSMutableArray array];
    DPHookClass(NSView.class, @selector(setNeedsLayout:), (IMP)DPView_setNeedsLayout);
    DPHookClass(NSView.class, @selector(setNeedsUpdateConstraints:), (IMP)DPView_setNeedsUpdateConstraints);
    DPHookClass(NSView.class, @selector(setFrameSize:), (IMP)DPView_setFrameSize);
    DPHookClass(NSView.class, @selector(setFrameOrigin:), (IMP)DPView_setFrameOrigin);
    // A loop never lets the run loop wait, so the counts start over each time it does.
    CFRunLoopObserverRef reset = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, true, 0, ^(CFRunLoopObserverRef o, CFRunLoopActivity a) {
        [DPCounts removeAllObjects];
    });
    CFRunLoopAddObserver(CFRunLoopGetMain(), reset, kCFRunLoopCommonModes);
}
