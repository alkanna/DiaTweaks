#import "CommandBar.h"

static NSArray *DPHeldWindows;

static NSArray *DPScriptedWindows(void) {
    if (DPHeldWindows) return DPHeldWindows;
    @try { return [NSApp valueForKey:@"appleScriptWindows"]; }
    @catch (__unused NSException *e) { return nil; }
}

void DPBarHoldScriptedWindows(BOOL hold) {
    DPHeldWindows = nil;
    if (hold) DPHeldWindows = DPScriptedWindows();
}

static id DPScriptedWindow(NSWindow *window) {
    @try {
        for (id scripted in DPScriptedWindows())
            if ([[scripted valueForKey:@"windowId"] isEqual:window.identifier]) return scripted;
    } @catch (__unused NSException *e) {}
    return nil;
}

static id DPActiveTab(NSWindow *window) {
    @try { return [DPScriptedWindow(window) valueForKey:@"activeTab"]; }
    @catch (__unused NSException *e) { return nil; }
}

static NSString *DPSpaceOf(id scripted) {
    id name = [[scripted valueForKey:@"activeProfile"] valueForKey:@"name"];
    return [name isKindOfClass:NSString.class] ? name : nil;
}

NSString *DPBarSpaceOfWindow(NSWindow *window) {
    @try { return DPSpaceOf(DPScriptedWindow(window)); }
    @catch (__unused NSException *e) { return nil; }
}

BOOL DPBarCanScript(NSWindow *window) { return DPActiveTab(window) != nil; }

NSString *DPBarActiveTabId(NSWindow *window) {
    @try { return [DPActiveTab(window) valueForKey:@"tabId"]; }
    @catch (__unused NSException *e) { return nil; }
}

BOOL DPBarCanListSpaces(NSWindow *window) {
    @try {
        NSArray *profiles = [DPScriptedWindow(window) valueForKey:@"appleScriptProfiles"];
        if (!profiles.count) return NO;
        [profiles valueForKey:@"orderedIndex"];
        id tab = [[profiles[0] valueForKey:@"appleScriptTabs"] firstObject];
        return !tab || [tab respondsToSelector:NSSelectorFromString(@"focus:")];
    } @catch (__unused NSException *e) { return NO; }
}

NSString *DPBarURLOfWindow(NSWindow *window) {
    @try {
        id url = [DPActiveTab(window) valueForKey:@"URL"];
        return [url isKindOfClass:NSString.class] ? url : nil;
    } @catch (__unused NSException *e) { return nil; }
}

void DPBarNavigate(NSWindow *window, NSString *url) {
    id tab = DPActiveTab(window);
    if (!url.length || !tab) return;
    @try { [tab setValue:url forKey:@"URL"]; }
    @catch (NSException *e) { NSLog(@"[DiaPatches] command bar couldn't navigate: %@", e); }
}

static void DPRunScript(NSString *source) {
    NSDictionary *error = nil;
    [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (error) NSLog(@"[DiaPatches] command bar script failed: %@", error[NSAppleScriptErrorMessage]);
}

static NSString *DPQuoted(NSString *text) {
    text = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [NSString stringWithFormat:@"\"%@\"", [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
}

// By path, because the bundle ID can hit the original Dia when the iCloud Passwords relay has it open.
static NSString *DPSelf(void) { return [@"application " stringByAppendingString:DPQuoted(NSBundle.mainBundle.bundlePath)]; }

// nil unless Dia overrides this. NSObject's version returns an object and opens no tab.
static Class DPDirectTabClass(void) {
    static Class tab;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL create = @selector(newScriptingObjectOfClass:forValueForKey:withContentsValue:properties:);
        Class window = NSClassFromString(@"DiaAppleScriptWindow");
        if (window && class_getMethodImplementation(window, create) != class_getMethodImplementation(NSObject.class, create)) tab = NSClassFromString(@"DiaAppleScriptTab");
    });
    return tab;
}

BOOL DPBarCanOpenTabDirectly(void) { return DPDirectTabClass() != nil; }

// No script to compile and no Apple Event. Saved about 70 ms with 334 tabs open.
static BOOL DPOpenTabDirectly(NSWindow *window, NSString *url) {
    Class tab = DPDirectTabClass();
    if (!tab) return NO;
    @try {
        return [DPScriptedWindow(window) newScriptingObjectOfClass:tab forValueForKey:@"appleScriptTabs"
                                                 withContentsValue:nil properties:@{@"URL": url}] != nil;
    } @catch (NSException *e) {
        NSLog(@"[DiaPatches] command bar couldn't open a tab directly: %@", e);
        return NO;
    }
}

void DPBarOpenInNewTab(NSWindow *window, NSString *url) {
    if (!window.identifier || !url.length || DPOpenTabDirectly(window, url)) return;
    DPRunScript([NSString stringWithFormat:@"tell %@\n  tell (first window whose id is %@) to make new tab with properties {URL:%@}\nend tell",
                 DPSelf(), DPQuoted(window.identifier), DPQuoted(url)]);
}

void DPBarFocusTab(NSString *windowId, NSInteger profileIndex, NSString *tabId) {
    if (!windowId || !tabId) return;
    NSString *owner = [NSString stringWithFormat:@"(first window whose id is %@)", DPQuoted(windowId)];
    if (profileIndex) owner = [NSString stringWithFormat:@"profile %ld of %@", (long)profileIndex, owner];
    NSString *source = [NSString stringWithFormat:@"tell %@\n  focus (first tab of %@ whose id is %@)\nend tell", DPSelf(), owner, DPQuoted(tabId)];
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.diapatches.commandbar.focus", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)); });
    dispatch_async(queue, ^{ DPRunScript(source); });
}

static NSMutableDictionary<NSString *, NSNumber *> *DPTabLastUsed;

void DPBarNoteActiveTab(NSWindow *window) {
    static NSUInteger uses;
    NSString *tab = DPBarActiveTabId(window);
    if (!tab) return;
    if (!DPTabLastUsed) DPTabLastUsed = [NSMutableDictionary new];
    DPTabLastUsed[tab] = @(++uses);
}

static void DPAddTabs(NSMutableArray<DPBarItem *> *items, NSMutableDictionary<NSString *, DPBarItem *> *known, id owner, NSString *windowId, NSString *shown, NSString *space, NSInteger profileIndex) {
    for (id tab in [owner valueForKey:@"appleScriptTabs"]) {
        NSString *tabId = [tab valueForKey:@"tabId"];
        DPBarItem *same = tabId ? known[tabId] : nil;
        NSString *url = same ? same.url : [tab valueForKey:@"URL"];
        if (![url isKindOfClass:NSString.class] || !url.length || [url hasPrefix:@"dia://"]) continue;
        DPBarItem *item = [DPBarItem new];
        item.kind = DPBarKindTab;
        item.title = same ? same.title : [tab valueForKey:@"title"] ?: url;
        item.url = url;
        item.detail = @"Switch to Tab";
        item.tabId = tabId;
        item.windowId = windowId;
        item.space = space;
        item.profileIndex = profileIndex;
        item.windowShowsSpace = [shown isEqual:space];
        item.symbol = @"square.on.square";
        item.frecency = 3;
        [items addObject:item];
        if (tabId && !same) known[tabId] = item;
    }
}

static void DPAddAllSpaces(NSMutableArray<DPBarItem *> *items, NSMutableDictionary<NSString *, DPBarItem *> *known, id scripted, NSString *windowId, NSString *shown) {
    @try {
        for (id profile in [scripted valueForKey:@"appleScriptProfiles"])
            DPAddTabs(items, known, profile, windowId, shown, [profile valueForKey:@"name"], [[profile valueForKey:@"orderedIndex"] integerValue]);
    } @catch (NSException *e) {
        NSLog(@"[DiaPatches] command bar couldn't list spaces: %@", e);
        DPAddTabs(items, known, scripted, windowId, shown, shown, 0);
    }
}

NSArray<DPBarItem *> *DPBarLoadTabs(NSWindow *window, NSString *space) {
    NSMutableArray<DPBarItem *> *items = [NSMutableArray new];
    NSMutableDictionary<NSString *, DPBarItem *> *known = [NSMutableDictionary new];
    @try {
        if (!space) DPAddTabs(items, known, DPScriptedWindow(window), window.identifier, nil, nil, 0);
        else for (id scripted in DPScriptedWindows()) {
            // Private windows are in this list too. They have no space, so this keeps their tabs out of normal windows.
            NSString *shown = DPSpaceOf(scripted), *windowId = [scripted valueForKey:@"windowId"];
            if (shown && DPCommandBarCoversAllSpaces()) DPAddAllSpaces(items, known, scripted, windowId, shown);
            else if ([shown isEqual:space]) DPAddTabs(items, known, scripted, windowId, shown, shown, 0);
        }
    } @catch (__unused NSException *e) {}
    NSMutableArray<DPBarItem *> *tabs = DPBarArrangeTabs(items, space, window.identifier);
    DPBarSortByRecency(tabs, DPTabLastUsed);
    return tabs;
}
