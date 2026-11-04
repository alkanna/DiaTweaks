#import "StdPatch/StdPatch.h"

static const NSUInteger DPBarMaxRows = 8;

typedef NS_ENUM(NSInteger, DPBarKind) {
    DPBarKindSearch,
    DPBarKindURL,      // What was typed, when it reads as an address.
    DPBarKindCommand,
    DPBarKindPage,
    DPBarKindTab,
    DPBarKindBookmark,
    DPBarKindHistory,
    DPBarKindSuggestion,
};

typedef NS_ENUM(NSInteger, DPBarMatch) { DPBarMatchNone, DPBarMatchContains, DPBarMatchPrefix, DPBarMatchExact };

@interface DPBarItem : NSObject
@property (nonatomic) DPBarKind kind;
@property (nonatomic, copy) NSString *title, *detail, *url, *symbol, *tabId, *windowId, *space;
@property (nonatomic, strong) NSMenuItem *menuItem;
@property (nonatomic) NSInteger tier;  // Lower lists first.
@property (nonatomic) NSInteger profileIndex;
@property (nonatomic) BOOL showsSpace, windowShowsSpace;
@property (nonatomic) double frecency, rank;
@end

NSString *DPResolveURL(NSString *input);   // nil if it reads as a search.
NSString *DPSearchURL(NSString *engineTemplate, NSString *text);
NSString *DPSearchEngineName(NSString *searchURL);
NSString *DPLikeEscape(NSString *text);
NSString *DPPrettyURL(NSString *url);
NSString *DPShortcutText(NSString *key, NSEventModifierFlags modifiers);
DPBarMatch DPBarMatchOf(NSArray<NSString *> *words, NSString *title, NSString *url);
NSInteger DPBarTier(DPBarKind kind, DPBarMatch match, NSUInteger queryLength);  // Negative means drop it.
void DPBarSortItems(NSMutableArray<DPBarItem *> *items);
void DPBarSortByRecency(NSMutableArray<DPBarItem *> *tabs, NSDictionary<NSString *, NSNumber *> *lastUsed);
NSMutableArray<DPBarItem *> *DPBarArrangeTabs(NSArray<DPBarItem *> *tabs, NSString *space, NSString *windowId);
BOOL DPBarReturnTakesCompletion(DPBarKind topRow, BOOL forceNewTab);
NSString *DPSuggestURL(NSString *suggestTemplate, NSString *text);
NSArray<NSString *> *DPParseSuggestions(NSData *json, NSString *query);

void DPBarHoldScriptedWindows(BOOL hold);
BOOL DPBarCanScript(NSWindow *window);
BOOL DPBarCanListSpaces(NSWindow *window);
NSString *DPBarURLOfWindow(NSWindow *window);  // nil on a blank tab.
NSString *DPBarActiveTabId(NSWindow *window);
void DPBarNavigate(NSWindow *window, NSString *url);
void DPBarOpenInNewTab(NSWindow *window, NSString *url);
BOOL DPBarCanOpenTabDirectly(void);
void DPBarNoteActiveTab(NSWindow *window);
void DPBarFocusTab(NSString *windowId, NSInteger profileIndex, NSString *tabId);
NSString *DPBarSpaceOfWindow(NSWindow *window);  // nil for a private window, which has no space.
NSArray<DPBarItem *> *DPBarLoadTabs(NSWindow *window, NSString *space);  // A nil space lists only `window`'s own tabs.

NSArray<DPBarItem *> *DPBarLoadCommands(void);
NSArray<DPBarItem *> *DPBarLoadPages(void);

// Databases only ever get read through our own clones.
void DPBarDropProfileSnapshot(void);
void DPBarUseSpace(NSString *space);  // Picks the profile folder to read. nil means the last used one.
NSArray<DPBarItem *> *DPBarLoadBookmarks(void);
NSString *DPBarLoadSearchTemplate(NSString **suggestTemplate);  // nil means Google. No suggest template if Dia's setting is off.
NSArray<DPBarItem *> *DPBarLoadHistory(NSArray<NSString *> *words);
// Columns are NSString, NSData, NSNumber or NSNull.
void DPBarQueryProfile(NSString *space, NSString *file, NSString *sql, NSArray *args, void (^row)(NSArray *columns));

@interface DPBarIcons : NSObject
@property (nonatomic, copy) void (^changed)(void);  // Runs on main.
@property (nonatomic) BOOL disabled;
- (void)prepare;
- (void)preload:(NSString *)url space:(NSString *)space;          // Blocks, so call it off the main thread.
- (NSImage *)iconFor:(NSString *)url space:(NSString *)space;     // Never blocks: nil until loaded, then `changed` runs.
@end

@interface DPBarSources : NSObject
@property (nonatomic, strong, readonly) DPBarIcons *icons;
@property (nonatomic, strong, readonly) NSString *activeURL;
- (void)prepareForWindow:(NSWindow *)window;
- (void)query:(NSString *)text done:(void (^)(NSArray<DPBarItem *> *items))done;  // `done` runs on main.
// What to complete `text` to ("git" gives "github.com"). `url` gets the address behind it.
- (NSString *)completionFor:(NSString *)text inItems:(NSArray<DPBarItem *> *)items url:(NSString **)url;
- (NSString *)searchURLFor:(NSString *)text;
@end

BOOL DPCommandBarShow(NSWindow *window, BOOL newTab);  // NO if `window` isn't a browser window.
BOOL DPCommandBarIsKey(void);
BOOL DPCommandBarSuggests(void);
BOOL DPCommandBarCoversAllSpaces(void);
BOOL DPCommandBarIsShown(NSWindow *window);
BOOL DPCommandBarAnimates(void);  // The option is on, and Reduce Motion is off.
BOOL DPCommandBarIsAnimating(void);
void DPCommandBarClose(void);
void DPCommandBarCommitInNewTab(void);
NSString *DPCommandBarText(void);
