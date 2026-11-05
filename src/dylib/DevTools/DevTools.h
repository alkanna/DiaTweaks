// Tools for writing patches, on with `defaults write com.diapatches devTools -bool YES` and a relaunch of Dia.
#import "StdPatch/StdPatch.h"

void DPInstallDevTools(void);
NSString *DPDescribeViews(NSView *root);
void DPTraceLayoutLoops(void);  // Writes what keeps a window's layout dirty to layout-loops.txt beside the dylib.  // One line per view: class, frame, label, rounded corners, and whether it's hidden.
