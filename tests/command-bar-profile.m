// Reading Dia's databases must not drop the locks Dia holds on them. make test runs this.
#import "Patches/CommandBar/CommandBar.h"
#include <fcntl.h>
#include <sqlite3.h>
#include <sys/wait.h>
#include <unistd.h>

// A process can't see that it lost its own locks, so ask another one.
static BOOL DPLockedFromOutside(const char *path) {
    pid_t child = fork();
    if (child == 0) {
        int fd = open(path, O_RDWR);
        struct flock probe = {.l_type = F_WRLCK, .l_whence = SEEK_SET};
        fcntl(fd, F_GETLK, &probe);
        _exit(probe.l_type == F_UNLCK);
    }
    int status;
    waitpid(child, &status, 0);
    return WEXITSTATUS(status) == 0;
}

int main(void) {
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data"];
    NSString *history = nil;  // Ends up as Profile 1's, the space the lock check below reads.
    for (NSArray<NSString *> *space in @[@[@"Default", @"https://first.example/", @"First"], @[@"Profile 1", @"https://second.example/", @"Second"]]) {
        NSString *folder = [root stringByAppendingPathComponent:space[0]];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        history = [folder stringByAppendingPathComponent:@"History"];
        [NSFileManager.defaultManager removeItemAtPath:history error:nil];
        sqlite3 *db;
        sqlite3_open(history.fileSystemRepresentation, &db);
        NSString *sql = [NSString stringWithFormat:@"CREATE TABLE urls (url, title, visit_count, typed_count, last_visit_time, hidden);"
                                                    "INSERT INTO urls VALUES ('%@', '%@ example', 5, 1, 13300000000000000, 0);", space[1], space[2]];
        sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
        sqlite3_close(db);
    }
    NSDictionary *state = @{@"profile": @{@"last_used": @"Default", @"info_cache": @{@"Default": @{@"name": @"Space 1"}, @"Profile 1": @{@"name": @"Repos GH"}}}};
    [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:[root stringByAppendingPathComponent:@"Local State"] atomically:YES];

    int fd = open(history.fileSystemRepresentation, O_RDWR);
    struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET};
    if (fcntl(fd, F_SETLK, &lock) != 0 || !DPLockedFromOutside(history.fileSystemRepresentation)) return NSLog(@"FAIL couldn't take the lock"), 1;

    int failures = 0;
    // A name that matches no space falls back to the last used.
    for (NSArray<NSString *> *pair in @[@[@"Repos GH", @"Second example"], @[@"Space 1", @"First example"], @[@"No such space", @"First example"]]) {
        DPBarUseSpace(pair[0]);
        NSArray<DPBarItem *> *rows = DPBarLoadHistory(@[@"example"]);
        if (rows.count != 1 || ![rows[0].title isEqualToString:pair[1]]) failures++, NSLog(@"FAIL space %@ read %@", pair[0], rows.firstObject.title);
    }
    DPBarUseSpace(@"Repos GH");
    DPBarLoadHistory(@[@"example"]);
    if (!DPLockedFromOutside(history.fileSystemRepresentation)) failures++, NSLog(@"FAIL reading dropped Dia's lock");
    if (!failures) NSLog(@"command bar profile: ok");
    return failures != 0;
}
