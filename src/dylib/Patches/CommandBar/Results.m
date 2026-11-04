#import "Bar.h"

@implementation DPBarResults

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)setItems:(NSArray<DPBarItem *> *)items {
    _items = [items copy];
    _selected = items.count ? 0 : -1;
    self.needsDisplay = YES;
}

- (void)setSelected:(NSInteger)selected {
    _selected = selected;
    self.needsDisplay = YES;
}

- (DPBarItem *)itemAtRow:(NSInteger)row {
    return row >= 0 && row < (NSInteger)self.items.count ? self.items[row] : nil;
}

- (NSRect)rectForRow:(NSInteger)row {
    return NSMakeRect(DPBarListInset, DPBarListInset + row * DPBarRowHeight, NSWidth(self.bounds) - DPBarListInset * 2, DPBarRowHeight);
}

- (NSInteger)rowForEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    for (NSInteger row = 0; row < (NSInteger)self.items.count; row++) if (NSPointInRect(point, [self rectForRow:row])) return row;
    return -1;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)mouseMoved:(NSEvent *)event {
    NSInteger row = [self rowForEvent:event];
    if (row >= 0 && row != self.selected) self.selected = row;
}

- (void)mouseDown:(NSEvent *)event {
    NSInteger row = [self rowForEvent:event];
    if (row >= 0) [self.bar activateRow:row forceNewTab:NO];
}

- (void)drawSymbol:(NSString *)name size:(CGFloat)size weight:(NSFontWeight)weight in:(NSRect)rect tint:(NSColor *)tint {
    NSImage *symbol = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]
                       imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
    if (!symbol) return;
    NSImage *tinted = [NSImage imageWithSize:symbol.size flipped:NO drawingHandler:^BOOL(NSRect target) {
        [symbol drawInRect:target];
        [tint set];
        NSRectFillUsingOperation(target, NSCompositingOperationSourceIn);
        return YES;
    }];
    NSRect fit = NSMakeRect(NSMidX(rect) - symbol.size.width / 2, NSMidY(rect) - symbol.size.height / 2, symbol.size.width, symbol.size.height);
    [tinted drawInRect:fit fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}

static void DPFillTile(NSRect rect, NSColor *color) {
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:7 yRadius:7] fill];
}

- (void)drawIconOf:(DPBarItem *)item in:(NSRect)rect {
    if (item.kind == DPBarKindCommand || item.kind == DPBarKindPage) {
        BOOL command = item.kind == DPBarKindCommand;
        DPFillTile(NSInsetRect(rect, -4, -4), command ? NSColor.labelColor : DPBarColor(1, 0.14, 0, 0.08));
        [self drawSymbol:item.symbol size:13 weight:NSFontWeightMedium in:rect tint:command ? NSColor.windowBackgroundColor : NSColor.labelColor];
        return;
    }
    NSImage *icon = [self.bar iconForItem:item];
    if (!icon) return [self drawSymbol:item.symbol size:15 weight:NSFontWeightRegular in:rect tint:NSColor.secondaryLabelColor];
    [icon drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}

- (void)drawRect:(NSRect)dirty {
    // About 6.4:1 contrast in both modes. macOS's tertiary label is about 2:1 here.
    NSColor *detailColor = DPBarColor(1, 0.58, 0, 0.64);
    NSFont *titleFont = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium], *detailFont = [NSFont systemFontOfSize:15];
    NSMutableParagraphStyle *truncating = [NSMutableParagraphStyle new];
    truncating.lineBreakMode = NSLineBreakByTruncatingMiddle;
    for (NSInteger index = 0; index < (NSInteger)self.items.count; index++) {
        DPBarItem *item = self.items[index];
        NSRect row = [self rectForRow:index];
        BOOL selected = index == self.selected;
        if (selected) {
            [DPBarColor(1, 0.10, 0, 0.07) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:row xRadius:10 yRadius:10] fill];
        }
        NSRect iconRect = NSMakeRect(NSMinX(row) + 14, NSMidY(row) - 10, 20, 20);
        [self drawIconOf:item in:iconRect];

        CGFloat x = NSMaxX(iconRect) + 16, maxX = NSMaxX(row) - 16;
        if (item.kind == DPBarKindTab) {
            NSRect chip = NSMakeRect(maxX - 24, NSMidY(row) - 14, 28, 28);
            DPFillTile(chip, selected ? NSColor.labelColor : DPBarColor(1, 0.16, 0, 0.09));
            [self drawSymbol:@"arrow.right" size:13 weight:NSFontWeightSemibold in:chip tint:selected ? NSColor.windowBackgroundColor : NSColor.labelColor];
            NSDictionary *attributes = @{NSFontAttributeName: selected ? titleFont : detailFont, NSForegroundColorAttributeName: selected ? NSColor.labelColor : detailColor};
            NSSize size = [item.detail sizeWithAttributes:attributes];
            [item.detail drawAtPoint:NSMakePoint(NSMinX(chip) - 12 - size.width, NSMidY(row) - size.height / 2) withAttributes:attributes];
            maxX = NSMinX(chip) - 28 - size.width;
        } else if (item.kind == DPBarKindCommand && item.detail.length) {
            NSDictionary *attributes = @{NSFontAttributeName: detailFont, NSForegroundColorAttributeName: detailColor};
            NSSize size = [item.detail sizeWithAttributes:attributes];
            [item.detail drawAtPoint:NSMakePoint(maxX - size.width, NSMidY(row) - size.height / 2) withAttributes:attributes];
            maxX -= size.width + 16;
        }

        NSString *detail = item.kind == DPBarKindSearch || item.kind == DPBarKindSuggestion || item.kind == DPBarKindURL ? item.detail
                         : item.kind == DPBarKindHistory || item.kind == DPBarKindBookmark || item.kind == DPBarKindPage ? DPPrettyURL(item.url)
                         : item.kind == DPBarKindTab && item.showsSpace ? item.space : nil;
        NSDictionary *titleAttributes = @{NSFontAttributeName: titleFont, NSForegroundColorAttributeName: NSColor.labelColor, NSParagraphStyleAttributeName: truncating};
        NSString *title = item.title ?: @"";
        NSSize titleSize = [title sizeWithAttributes:titleAttributes];
        CGFloat titleWidth = MIN(titleSize.width, (maxX - x) * (detail.length ? 0.6 : 1));
        [title drawInRect:NSMakeRect(x, NSMidY(row) - titleSize.height / 2, titleWidth, titleSize.height) withAttributes:titleAttributes];
        if (!detail.length) continue;
        NSDictionary *detailAttributes = @{NSFontAttributeName: detailFont, NSForegroundColorAttributeName: detailColor, NSParagraphStyleAttributeName: truncating};
        NSString *text = [@"· " stringByAppendingString:detail];
        NSSize detailSize = [text sizeWithAttributes:detailAttributes];
        CGFloat detailX = x + titleWidth + 8;
        [text drawInRect:NSMakeRect(detailX, NSMidY(row) - detailSize.height / 2, MAX(0, maxX - detailX), detailSize.height) withAttributes:detailAttributes];
    }
}

@end
