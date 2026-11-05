#import "EdgeToEdge.h"

// Dia hangs a popup, such as the command bar, from the address field. Edge-to-edge moves the field up and left with
// the page, so the popup went with it and its top left the window. This puts it back where Dia meant it.

static char DPPopoverKey;

static CGFloat DPTop(NSView *parent, NSRect rect) { return parent.isFlipped ? NSMinY(rect) : NSMaxY(rect); }

// How far edge-to-edge moved the toolbar a popup at `frame` hangs from. Zero for one that isn't level with it.
static NSPoint DPPopoverShift(NSView *popover, NSRect frame) {
    for (NSView *container in DPContainers) {
        NSValue *requested = DPRequestedFrame(container);
        NSView *parent = container.superview;
        if (!requested || parent != popover.superview || container.isHiddenOrHasHiddenAncestor) continue;
        NSView *bar = DPFindView(container, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaNavigationBar); });
        if (!bar) continue;
        NSRect barFrame = [parent convertRect:bar.bounds fromView:bar];
        if (parent.isFlipped ? NSMinY(frame) >= NSMaxY(barFrame) : NSMaxY(frame) <= NSMinY(barFrame)) return NSZeroPoint;
        NSRect asked = requested.rectValue, now = container.frame;
        return NSMakePoint(NSMinX(asked) - NSMinX(now), DPTop(parent, asked) - DPTop(parent, now));
    }
    return NSZeroPoint;
}

// Dia may set the frame again from the origin it read back, so the origin we gave is mapped back to Dia's.
static NSPoint DPPopoverOrigin(NSView *popover, NSRect frame) {
    NSArray<NSValue *> *last = DPGet(popover, &DPPopoverKey);
    NSPoint dia = last && NSEqualPoints(frame.origin, last[1].pointValue) ? last[0].pointValue : frame.origin;
    NSPoint shift = DPPopoverShift(popover, NSMakeRect(dia.x, dia.y, NSWidth(frame), NSHeight(frame)));
    NSPoint ours = NSMakePoint(dia.x + shift.x, dia.y + shift.y);
    DPSet(popover, &DPPopoverKey, @[ [NSValue valueWithPoint:dia], [NSValue valueWithPoint:ours] ]);
    return ours;
}

static void DPPopover_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    frame.origin = DPPopoverOrigin(self, frame);
    DPCallOriginal(DPPopover_setFrame, self, frame);
}

static void DPPopover_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    DPCallOriginal(DPPopover_setFrameOrigin, self, DPPopoverOrigin(self, (NSRect){ origin, self.frame.size }));
}

void DPInstallPopover(void) {
    DPHook(DPDiaPopoverRoot, @selector(setFrame:), (IMP)DPPopover_setFrame);
    DPHook(DPDiaPopoverRoot, @selector(setFrameOrigin:), (IMP)DPPopover_setFrameOrigin);
}
