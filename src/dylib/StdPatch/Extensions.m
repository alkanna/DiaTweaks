#import "StdPatch/StdPatch.h"

static NSMutableArray<NSString *> *DPExtensionFolders;

// Dia passes Chromium its command line here. Chromium keeps only the last --load-extension, so one flag lists every
// folder, any Dia passed first.
static id DPConfiguration_init(id self, SEL _cmd, int argc, NSArray<NSString *> *argv, NSString *profilePath, NSUInteger applicationID,
                               BOOL isProduction, NSUInteger restorationPolicy, BOOL loadAllProfiles, BOOL quitRunLoop, NSString *suiteName) {
    static NSString *const flag = @"--load-extension=";
    NSMutableArray<NSString *> *args = [argv mutableCopy], *folders = [NSMutableArray array];
    for (NSString *arg in argv)
        if ([arg hasPrefix:flag]) {
            [folders addObject:[arg substringFromIndex:flag.length]];
            [args removeObject:arg];
        }
    [folders addObjectsFromArray:DPExtensionFolders];
    [args addObject:[flag stringByAppendingString:[folders componentsJoinedByString:@","]]];
    return DPCallOriginal(DPConfiguration_init, self, argc + (int)(args.count - argv.count), args, profilePath, applicationID, isProduction,
                          restorationPolicy, loadAllProfiles, quitRunLoop, suiteName);
}

void DPLoadExtension(NSString *folder) {
    if (!DPExtensionFolders) {
        DPExtensionFolders = [NSMutableArray array];
        DPHook("ArcBrowserApplicationConfiguration", @selector(init:argv:profilePath:applicationID:isProduction:sessionRestorationPolicy:shouldLoadAllProfilesAtStartup:quitRunLoopOnTermination:userDefaultsSuiteName:),
               (IMP)DPConfiguration_init);
    }
    if (![DPExtensionFolders containsObject:folder]) [DPExtensionFolders addObject:folder];
}
