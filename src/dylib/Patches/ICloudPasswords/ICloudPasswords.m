#import "StdPatch/StdPatch.h"
#include <libproc.h>

// The extension asks for Apple's host by name, and Chromium prefers a user's copy of a host over the system's.

extern DPPatch DPICloudPasswords;

static NSString *const kAppleHost = @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json";

static NSString *DPHostManifestPath(void) { return DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json"); }

static NSError *gWriteError;

static void DPRegisterHost(BOOL on) {
    gWriteError = nil;
    NSData *existing = [NSData dataWithContentsOfFile:DPHostManifestPath()];
    NSDictionary *host = existing ? [NSJSONSerialization JSONObjectWithData:existing options:0 error:nil] : nil;
    if (existing && !([host isKindOfClass:NSDictionary.class] && [host[@"path"] isEqual:DPAppSupport(@"DiaPatches/bin/diapatch")])) return;  // another app's
    if (!on) return (void)[NSFileManager.defaultManager removeItemAtPath:DPHostManifestPath() error:nil];
    NSDictionary *manifest = @{
        @"name" : @"com.apple.passwordmanager",
        @"description" : @"DiaTweaks relay to iCloud Passwords",
        @"path" : DPAppSupport(@"DiaPatches/bin/diapatch"),
        @"type" : @"stdio",
        @"allowed_origins" : @[ @"chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/", @"chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" ],
    };
    NSError *error;
    BOOL written = [NSFileManager.defaultManager createDirectoryAtPath:DPHostManifestPath().stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]
        && [[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] writeToFile:DPHostManifestPath() options:NSDataWritingAtomic error:&error];
    gWriteError = written ? nil : error;
}

static NSString *DPICloudPasswordsProblem(DPPatch *patch) {
    NSDictionary *apple = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:kAppleHost] ?: NSData.data options:0 error:nil];
    if (![apple isKindOfClass:NSDictionary.class] || ![apple[@"path"] isKindOfClass:NSString.class] || ![NSFileManager.defaultManager isExecutableFileAtPath:apple[@"path"]])
        return @"This Mac doesn’t have Apple’s iCloud Passwords helper, which comes with macOS 14 and later.";
    if (gWriteError) return [NSString stringWithFormat:@"Couldn’t write %@: %@", DPHostManifestPath(), gWriteError.localizedDescription];
    return DPRelayProblem() ?: DPHostProblem(DPHostManifestPath(), @"com.apple.passwordmanager");
}

// The relay's original Dia outlives this one by seconds, and Dia refuses to start while it runs. This runs before Dia checks.
static void DPStopOriginalDia(void) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    NSArray<NSString *> *originals = @[ DPAppSupport(@"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia").stringByResolvingSymlinksInPath, @"/Applications/.DiaTweaks/Dia.app/Contents/MacOS/Dia" ];
    int capacity = proc_listallpids(NULL, 0) + 64;
    pid_t pids[capacity];
    int count = proc_listallpids(pids, capacity * (int)sizeof *pids);
    for (int i = 0; i < count; i++) {
        if (proc_pidpath(pids[i], path, sizeof path) <= 0 || ![originals containsObject:@(path)]) continue;
        kill(pids[i], SIGKILL);
        for (int tries = 0; tries < 50 && kill(pids[i], 0) == 0; tries++) usleep(20000);
    }
}

static void DPInstallICloudPasswords(void) {
    DPStopOriginalDia();
    DPRegisterHost(DPICloudPasswords.on);
}

static void DPApplyICloudPasswords(DPPatch *patch) { DPRegisterHost(patch->on); }

DP_PATCH(DPICloudPasswords) {
    .key = @"icloudPasswords",
    .order = 101,
    .title = @"Allow iCloud Passwords",
    .detail = @"AutoFill passwords from Apple Passwords with the iCloud Passwords extension. A patched Dia can’t start Apple’s helper, so each time the extension connects, the original Dia that DiaTweaks keeps opens for a moment, without windows, to start it. Experimental.",
    .symbol = @"apple.passwords key.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .install = DPInstallICloudPasswords,
    .apply = DPApplyICloudPasswords,
    .ready = DPICloudPasswordsProblem,
};
