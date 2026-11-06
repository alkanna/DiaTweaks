#import "StdPatch/StdPatch.h"
#include <spawn.h>
#include <sys/xattr.h>

// 1Password's helper turns the patched Dia away, so diapatch stands in and relays through the original Dia.

extern DPPatch DPOnePassword;

static const char *DPDiapatch(void) {
    static char path[PATH_MAX];
    static dispatch_once_t once;
    dispatch_once(&once, ^{ strlcpy(path, DPAppSupport(@"DiaPatches/bin/diapatch").fileSystemRepresentation, sizeof path); });
    return path;
}

static int DPSpawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *files, const posix_spawnattr_t *attrs, char *const argv[], char *const envp[]) {
    const char *name = path ? strrchr(path, '/') : NULL;
    if (!DPOnePassword.on || !name || strcmp(name, "/1Password-BrowserSupport")) return posix_spawn(pid, path, files, attrs, argv, envp);
    int argc = 0;
    while (argv[argc]) argc++;
    char *redirected[argc + 1];
    memcpy(redirected, argv, (argc + 1) * sizeof *argv);
    redirected[0] = (char *)DPDiapatch();
    return posix_spawn(pid, redirected[0], files, attrs, redirected, envp);
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *replacee; } DPInterposeSpawn = {
    (const void *)DPSpawn, (const void *)posix_spawn
};

static NSString *DPAgentPlist(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.diapatches.passwords.plist"]; }

static NSString *DPLaunchctl(NSArray<NSString *> *arguments, int *status) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = arguments;
    task.standardOutput = task.standardError = [NSPipe pipe];
    if (![task launchAndReturnError:nil]) return *status = -1, nil;
    NSData *output = [[task.standardOutput fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    *status = task.terminationStatus;
    return [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
}

static NSString *gAgentError;

// The relay runs as a launch agent, which macOS can unload or block from Login Items & Extensions.
static void DPApplyOnePassword(DPPatch *patch) {
    int status;
    NSString *domain = [NSString stringWithFormat:@"gui/%d", getuid()];
    gAgentError = nil;
    if (!patch->on || !DPLaunchctl(@[ @"print", [domain stringByAppendingString:@"/com.diapatches.passwords"] ], &status) || status == 0) return;
    removexattr(DPAgentPlist().fileSystemRepresentation, "com.apple.quarantine", 0);  // diapatch run from Dia writes it quarantined, which launchd refuses
    NSString *output = DPLaunchctl(@[ @"bootstrap", domain, DPAgentPlist() ], &status);
    if (status != 0) gAgentError = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *DPOnePasswordProblem(DPPatch *patch) {
    NSString *host = DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.1password.1password.json");
    if (![NSFileManager.defaultManager fileExistsAtPath:host]) return @"The 1Password app isn’t installed, or hasn’t set up its browser support yet. Open 1Password, then try again.";
    if (![NSFileManager.defaultManager fileExistsAtPath:DPAgentPlist()]) return [NSString stringWithFormat:@"%@ is missing. Install DiaTweaks again to put it back.", DPAgentPlist()];
    int status;
    DPLaunchctl(@[ @"print", [NSString stringWithFormat:@"gui/%d/com.diapatches.passwords", getuid()] ], &status);
    if (status != 0)
        return [NSString stringWithFormat:@"DiaTweaks’ background helper isn’t running%@. If it’s off in System Settings → General → Login Items & Extensions, turn it on and try again.",
                                          gAgentError.length ? [NSString stringWithFormat:@" (%@)", gAgentError] : @""];
    return DPRelayProblem();
}

DP_PATCH(DPOnePassword) {
    .key = @"onePassword",
    .order = 102,
    .title = @"Allow 1Password",
    .detail = @"Connect the 1Password extension to the 1Password app. The app turns away a patched Dia, so while the extension is connected, the original Dia that DiaTweaks keeps runs in the background to talk to it. Experimental.",
    .symbol = @"lock.shield.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .apply = DPApplyOnePassword,
    .ready = DPOnePasswordProblem,
};
