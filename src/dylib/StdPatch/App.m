#import "StdPatch/StdPatch.h"

void DPOnLaunch(void (^block)(void)) {
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *_) { block(); }];
}

void DPOnQuit(void (^block)(void)) {
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *_) { block(); }];
}

// Menu items hold their target weakly; representedObject keeps it alive.
@interface DPMenuAction : NSObject
@property (nonatomic, copy) void (^action)(void);
@end

@implementation DPMenuAction
- (void)run:(id)sender { self.action(); }
@end

static NSMenu *DPMenuTitled(NSString *title) {
    NSMenu *bar = NSApp.mainMenu;
    return (title ? [bar itemWithTitle:title] : bar.itemArray.firstObject).submenu;
}

static void DPSetAction(NSMenuItem *item, void (^action)(void)) {
    DPMenuAction *target = [DPMenuAction new];
    target.action = action;
    item.representedObject = target;
    item.target = target;
    item.action = @selector(run:);
}

NSMenuItem *DPMenuItem(NSString *title, void (^action)(void)) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    DPSetAction(item, action);
    return item;
}

NSMenuItem *DPAddMenuItem(NSString *menu, NSString *title, void (^action)(void)) {
    NSMenuItem *item = DPMenuItem(title, action);
    [DPMenuTitled(menu) addItem:item];
    return item;
}

void DPOnMenuItem(NSString *menu, NSString *titlePrefix, void (^action)(void)) {
    for (NSMenuItem *item in DPMenuTitled(menu).itemArray)
        if ([item.title hasPrefix:titlePrefix]) DPSetAction(item, action);
}
