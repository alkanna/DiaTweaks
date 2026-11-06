#import "SafeMode/SafeMode.h"
#import <dlfcn.h>
#import <mach-o/loader.h>

// Shorter-lived launches that don't quit normally count as crashes. Long, since patches often crash on a first resize or new tab.
static const int64_t DPSurviveSeconds = 180;

NSInteger DPSafeMode;
static NSURL *DPStateURL;
static NSMutableDictionary *DPState;

static NSString *DPBuildUUID(const struct mach_header_64 *header) {
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const uint8_t *)command + command->cmdsize))
        if (command->cmd == LC_UUID) return [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
    return @"";
}

static void DPSurvived(void) {
    if (![DPState[@"launching"] boolValue]) return;
    DPState[@"launching"] = @NO;
    [DPState writeToURL:DPStateURL error:nil];
}

void DPBeginLaunch(void) {
    Dl_info info;
    dladdr((const void *)DPBeginLaunch, &info);
    DPStateURL = [NSURL fileURLWithPath:[@(info.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"safe-mode.plist"]];
    // A new build may be the fix, so it starts over.
    NSString *build = DPBuildUUID(info.dli_fbase);
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:DPStateURL error:nil];
    DPState = [saved[@"build"] isEqual:build] ? [saved mutableCopy] : [NSMutableDictionary dictionaryWithObject:build forKey:@"build"];
    NSInteger crashes = [DPState[@"launching"] boolValue] ? [DPState[@"crashes"] integerValue] + 1 : 0;
    DPSafeMode = [DPState[@"level"] integerValue];
    if (crashes == 2 && DPSafeMode < 2) DPSafeMode++, crashes = 0;
    [DPState addEntriesFromDictionary:@{@"level": @(DPSafeMode), @"crashes": @(crashes), @"launching": @YES}];
    [DPState writeToURL:DPStateURL error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPSurviveSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPSurvived(); });
    DPOnQuit(^{ DPSurvived(); });
}

void DPLeaveSafeMode(void) {
    DPState = [NSMutableDictionary dictionaryWithObject:DPState[@"build"] forKey:@"build"];
    [DPState writeToURL:DPStateURL error:nil];
}
