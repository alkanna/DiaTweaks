#import "CommandBar.h"
#include <sqlite3.h>
#include <os/lock.h>
#include <sys/clonefile.h>

static NSDictionary *DPReadJSONObject(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

static NSString *DPUserData(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data"]; }

// Dia's spaces are Chromium profiles, and Local State has their names.
// ponytail: if two spaces share a name, either folder may match. Match on something else if Dia ever allows that.
static NSString *DPFolderOfSpace(NSString *space) {
    NSString *root = DPUserData();
    id profile = DPReadJSONObject([root stringByAppendingPathComponent:@"Local State"])[@"profile"];
    if (![profile isKindOfClass:NSDictionary.class]) return @"Default";
    id cache = profile[@"info_cache"];
    if (space && [cache isKindOfClass:NSDictionary.class])
        for (NSString *folder in cache)
            if ([cache[folder] isKindOfClass:NSDictionary.class] && [cache[folder][@"name"] isEqual:space]) return folder;
    id last = profile[@"last_used"];
    BOOL isDirectory = NO;
    BOOL valid = [last isKindOfClass:NSString.class] && [last length] && ![last hasPrefix:@"."] && ![last containsString:@"/"]
        && [NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:last] isDirectory:&isDirectory] && isDirectory;
    return valid ? last : @"Default";
}

static NSString *DPCurrentFolder;
static NSMutableDictionary<NSString *, NSString *> *DPFolders;
static os_unfair_lock DPFolderLock = OS_UNFAIR_LOCK_INIT;

void DPBarUseSpace(NSString *space) {
    NSString *folder = DPFolderOfSpace(space);
    os_unfair_lock_lock(&DPFolderLock);
    DPCurrentFolder = folder;
    DPFolders = space ? [NSMutableDictionary dictionaryWithObject:folder forKey:space] : [NSMutableDictionary new];
    os_unfair_lock_unlock(&DPFolderLock);
}

static NSString *DPFolder(void) {
    os_unfair_lock_lock(&DPFolderLock);
    NSString *folder = DPCurrentFolder;
    os_unfair_lock_unlock(&DPFolderLock);
    return folder ?: DPFolderOfSpace(nil);
}

static NSString *DPFolderFor(NSString *space) {
    if (!space) return DPFolder();
    os_unfair_lock_lock(&DPFolderLock);
    NSString *folder = DPFolders[space];
    os_unfair_lock_unlock(&DPFolderLock);
    if (folder) return folder;
    folder = DPFolderOfSpace(space);
    os_unfair_lock_lock(&DPFolderLock);
    DPFolders[space] = folder;
    os_unfair_lock_unlock(&DPFolderLock);
    return folder;
}

static NSString *DPPathIn(NSString *folder, NSString *file) {
    return [[DPUserData() stringByAppendingPathComponent:folder] stringByAppendingPathComponent:file];
}

static NSString *DPBarProfilePath(NSString *file) { return DPPathIn(DPFolder(), file); }

// clonefile can't cross volumes.
static NSString *DPSnapshotFolder(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/com.diapatches.commandbar"]; }

static dispatch_queue_t DPSnapshotQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.diapatches.commandbar.snapshot", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

void DPBarDropProfileSnapshot(void) {
    dispatch_async(DPSnapshotQueue(), ^{ [NSFileManager.defaultManager removeItemAtPath:DPSnapshotFolder() error:nil]; });
}

// Closing any descriptor for a file drops every POSIX lock this process holds on it, Dia's too. So never open the real files.
// ponytail: no clones off APFS, so no history there. Copy with a helper process if that matters.
static NSString *DPSnapshot(NSString *folder, NSString *file) {
    __block NSString *copy;
    NSString *original = DPPathIn(folder, file);
    dispatch_sync(DPSnapshotQueue(), ^{
        // Folder in the name so a slow query from another space can't leave us its clone.
        copy = [DPSnapshotFolder() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", folder, file]];
        NSFileManager *files = NSFileManager.defaultManager;
        if ([files fileExistsAtPath:copy]) return;
        [files createDirectoryAtPath:DPSnapshotFolder() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
        for (NSString *suffix in @[@"-journal", @"-wal", @""]) {  // Database last. A newer journal is safe to replay, an older one isn't.
            NSString *source = [original stringByAppendingString:suffix];
            clonefile(source.fileSystemRepresentation, [copy stringByAppendingString:suffix].fileSystemRepresentation, 0);
        }
    });
    return copy;
}

void DPBarQueryProfile(NSString *space, NSString *file, NSString *sql, NSArray *args, void (^row)(NSArray *columns)) {
    NSString *path = [DPSnapshot(DPFolderFor(space), file) stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    sqlite3 *db = NULL;
    // Writable because recovering a journal writes to the file. It's our clone, so that's fine.
    if (sqlite3_open_v2([@"file:" stringByAppendingString:path].UTF8String, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_URI, NULL) == SQLITE_OK) {
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
            for (int i = 0; i < (int)args.count; i++) sqlite3_bind_text(statement, i + 1, [args[i] UTF8String], -1, SQLITE_TRANSIENT);
            while (sqlite3_step(statement) == SQLITE_ROW) @autoreleasepool {
                NSMutableArray *columns = [NSMutableArray new];
                for (int i = 0; i < sqlite3_column_count(statement); i++) {
                    switch (sqlite3_column_type(statement, i)) {
                        case SQLITE_INTEGER: [columns addObject:@(sqlite3_column_int64(statement, i))]; break;
                        case SQLITE_FLOAT: [columns addObject:@(sqlite3_column_double(statement, i))]; break;
                        case SQLITE_TEXT: [columns addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, i)] ?: @""]; break;
                        case SQLITE_BLOB: [columns addObject:[NSData dataWithBytes:sqlite3_column_blob(statement, i) length:sqlite3_column_bytes(statement, i)]]; break;
                        default: [columns addObject:NSNull.null];
                    }
                }
                row(columns);
            }
        }
        sqlite3_finalize(statement);
    }
    sqlite3_close(db);
}

static void DPWalkBookmarks(NSDictionary *node, NSMutableArray<DPBarItem *> *items) {
    // Picking a row should never run a script.
    if ([node[@"type"] isEqual:@"url"] && [node[@"url"] isKindOfClass:NSString.class] && ![[node[@"url"] lowercaseString] hasPrefix:@"javascript:"]) {
        DPBarItem *item = [DPBarItem new];
        item.kind = DPBarKindBookmark;
        item.title = node[@"name"];
        item.url = node[@"url"];
        item.symbol = @"bookmark";
        item.frecency = 1;
        [items addObject:item];
    }
    id children = node[@"children"];
    if (![children isKindOfClass:NSArray.class]) return;
    for (id child in children) if ([child isKindOfClass:NSDictionary.class]) DPWalkBookmarks(child, items);
}

NSArray<DPBarItem *> *DPBarLoadBookmarks(void) {
    id roots = DPReadJSONObject(DPBarProfilePath(@"Bookmarks"))[@"roots"];
    NSMutableArray<DPBarItem *> *items = [NSMutableArray new];
    if (![roots isKindOfClass:NSDictionary.class]) return items;
    for (id root in [roots allValues]) if ([root isKindOfClass:NSDictionary.class]) DPWalkBookmarks(root, items);
    return items;
}

NSString *DPBarLoadSearchTemplate(NSString **suggestTemplate) {
    NSDictionary *preferences = DPReadJSONObject(DPBarProfilePath(@"Preferences"));
    id provider = preferences[@"default_search_provider"];
    id guid = [provider isKindOfClass:NSDictionary.class] ? provider[@"guid"] : nil;
    if (![guid isKindOfClass:NSString.class]) return nil;
    id search = preferences[@"search"];
    BOOL suggests = ![search isKindOfClass:NSDictionary.class] || ![search[@"suggest_enabled"] isEqual:@NO];
    __block NSString *url = nil, *suggest = nil;
    DPBarQueryProfile(nil, @"Web Data", @"SELECT url, suggest_url FROM keywords WHERE sync_guid = ?1 LIMIT 1", @[guid], ^(NSArray *columns) {
        if ([columns[0] isKindOfClass:NSString.class] && [columns[0] length]) url = columns[0];
        if (suggests && [columns[1] isKindOfClass:NSString.class]) suggest = columns[1];
    });
    *suggestTemplate = suggest;
    return url;
}

NSArray<DPBarItem *> *DPBarLoadHistory(NSArray<NSString *> *words) {
    if (!words.count) return @[];
    NSMutableString *where = [NSMutableString stringWithString:@"hidden = 0"];
    NSMutableArray<NSString *> *args = [NSMutableArray new];
    for (NSString *word in words) {
        // LIKE only folds ASCII case, so try upper and capitalized forms of everything else.
        NSArray<NSString *> *forms = [word canBeConvertedToEncoding:NSASCIIStringEncoding] ? @[word] : @[word, word.uppercaseString, word.capitalizedString];
        NSMutableArray<NSString *> *any = [NSMutableArray new];
        for (NSString *form in forms) {
            [args addObject:[NSString stringWithFormat:@"%%%@%%", DPLikeEscape(form)]];
            [any addObject:[NSString stringWithFormat:@"url LIKE ?%1$lu ESCAPE '\\' OR title LIKE ?%1$lu ESCAPE '\\'", (unsigned long)args.count]];
        }
        [where appendFormat:@" AND (%@)", [any componentsJoinedByString:@" OR "]];
    }
    NSString *sql = [NSString stringWithFormat:@"SELECT url, title, visit_count, typed_count, last_visit_time FROM urls WHERE %@ "
                                                "ORDER BY typed_count * 2 + visit_count DESC, last_visit_time DESC LIMIT 80", where];
    NSMutableArray<DPBarItem *> *items = [NSMutableArray new];
    double now = (NSDate.date.timeIntervalSince1970 + 11644473600.0) * 1e6;  // Chromium time: microseconds since 1601.
    DPBarQueryProfile(nil, @"History", sql, args, ^(NSArray *columns) {
        if (![columns[0] isKindOfClass:NSString.class]) return;
        DPBarItem *item = [DPBarItem new];
        item.kind = DPBarKindHistory;
        item.url = columns[0];
        item.title = [columns[1] isKindOfClass:NSString.class] && [columns[1] length] ? columns[1] : item.url;
        item.symbol = @"globe";
        double ageDays = MAX(0, (now - [columns[4] doubleValue]) / 8.64e10);
        // Uncapped, so a site visited thousands of times outranks one visited dozens of times.
        item.frecency = log2([columns[2] doubleValue] + 1) * 0.6 + log2([columns[3] doubleValue] + 1) * 0.8 + 1.5 / (1 + ageDays / 7);
        [items addObject:item];
    });
    return items;
}
