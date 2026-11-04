#import "Bar.h"

@implementation DPBar (Input)

- (void)runQuery {
    NSString *query = self.typed ?: @"";
    __weak DPBar *weakSelf = self;
    [self.sources query:query done:^(NSArray<DPBarItem *> *items) {
        DPBar *bar = weakSelf;
        if (bar.hiding || ![bar.typed isEqualToString:query]) return;
        // Suggestions turn up late and shouldn't move the selection.
        DPBarItem *selected = [bar.results itemAtRow:bar.results.selected];
        bar.shownQuery = query;
        bar.results.items = items;
        NSUInteger kept = selected ? [items indexOfObjectIdenticalTo:selected] : NSNotFound;
        if (kept != NSNotFound) bar.results.selected = kept;
        [bar layoutForRows:MIN(DPBarMaxRows, items.count)];
        [bar updateFieldIcon];
        [bar applyCompletionFrom:items];
    }];
}

- (void)updateFieldIcon {
    NSInteger selected = self.results.selected;
    DPBarItem *top = [self.results itemAtRow:selected];
    if (selected <= 0) {
        NSString *text = (self.field.currentEditor.string ?: self.field.stringValue).lowercaseString;
        NSString *site = self.completionURL ?: DPResolveURL(text);
        NSImage *favicon = site ? [self.sources.icons iconFor:site space:nil] : nil;
        if (favicon) {
            self.fieldIcon.image = favicon;
            return;
        }
    }
    NSImage *image = top ? [self iconForItem:top] : nil;
    self.fieldIcon.image = image ?: [NSImage imageWithSystemSymbolName:top.symbol ?: @"magnifyingglass" accessibilityDescription:nil];
}

- (NSImage *)iconForItem:(DPBarItem *)item {
    if (item.kind == DPBarKindCommand || item.kind == DPBarKindPage || item.kind == DPBarKindSearch || item.kind == DPBarKindSuggestion) return nil;
    return [self.sources.icons iconFor:item.url space:item.space];
}

// "git" becomes "git|hub.com", with the suffix selected.
- (void)applyCompletionFrom:(NSArray<DPBarItem *> *)items {
    if (self.suppressCompletion) return;
    NSString *url = nil;
    NSString *site = [self.sources completionFor:self.typed inItems:items url:&url];
    NSTextView *editor = (NSTextView *)self.field.currentEditor;
    // Replacing the string would abort an input method's composition.
    if (!site || !editor || editor.hasMarkedText || ![editor.string isEqualToString:self.typed]) return;
    self.completionURL = url;
    NSString *suffix = [site substringFromIndex:self.typed.length];
    editor.string = [self.typed stringByAppendingString:suffix];
    editor.selectedRange = NSMakeRange(self.typed.length, suffix.length);
    [self updateFieldIcon];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSString *now = self.field.stringValue;
    // Don't complete straight back what was just deleted.
    self.suppressCompletion = now.length <= self.typed.length && [self.typed hasPrefix:now];
    self.typed = now;
    self.completionURL = nil;
    [self runQuery];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    NSInteger count = self.results.items.count;
    if (selector == @selector(moveDown:) || selector == @selector(moveUp:)) {
        if (count) {
            self.results.selected = (self.results.selected + (selector == @selector(moveDown:) ? 1 : -1) + count) % count;
            [self updateFieldIcon];
        }
        return YES;
    }
    if (selector == @selector(insertTab:)) {
        textView.selectedRange = NSMakeRange(textView.string.length, 0);
        self.typed = textView.string;
        [self runQuery];
        return YES;
    }
    if (selector == @selector(insertNewline:)) {
        [self commitInNewTab:NO];
        return YES;
    }
    if (selector == @selector(cancelOperation:)) {
        [self close];
        return YES;
    }
    return NO;
}

- (void)commitInNewTab:(BOOL)newTab {
    BOOL completed = ![self.field.currentEditor.string isEqualToString:self.typed] && self.results.selected == 0
        && DPBarReturnTakesCompletion([self.results itemAtRow:0].kind, newTab);
    BOOL stale = ![self.shownQuery isEqualToString:self.typed];
    [self activateRow:completed || stale ? -1 : self.results.selected forceNewTab:newTab];
}

- (void)activateRow:(NSInteger)row forceNewTab:(BOOL)forceNewTab {
    NSWindow *window = self.host;
    DPBarItem *item = [self.results itemAtRow:row];
    NSString *text = self.field.currentEditor.string ?: self.field.stringValue, *query = self.typed;
    NSString *completionURL = self.completionURL, *typedURL = DPResolveURL(text) ?: [self.sources searchURLFor:text];
    [self close];
    if (!item) {
        if (!text.length) return;
        item = [DPBarItem new];
        item.kind = DPBarKindURL;
        item.title = text;
        item.url = typedURL;
    }
    if (item.kind == DPBarKindCommand) {
        NSMenuItem *entry = item.menuItem;
        dispatch_async(dispatch_get_main_queue(), ^{ [NSApp sendAction:entry.action to:entry.target from:entry]; });
        return;
    }
    if (item.kind == DPBarKindTab) return DPBarFocusTab(item.windowId, item.profileIndex, item.tabId);
    NSString *url = item.url;
    // An accepted completion keeps its http and port.
    if (item.kind == DPBarKindURL) url = completionURL ?: ([text isEqualToString:item.title] ? url : typedURL);
    // Clicked before the results caught up, so search what's typed now.
    if (item.kind == DPBarKindSearch && ![query isEqualToString:item.title]) url = [self.sources searchURLFor:query];
    if (!url) return;
    BOOL newTab = self.opensNewTab || forceNewTab;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (newTab) DPBarOpenInNewTab(window, url);
        else DPBarNavigate(window, url);
    });
}

@end
