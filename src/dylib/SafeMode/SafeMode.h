#import "StdPatch/StdPatch.h"

// 0: normal. 1: Dia died twice at launch, so no patch or command hooks. 2: it kept dying, so nothing.
extern NSInteger DPSafeMode;
void DPBeginLaunch(void);
void DPLeaveSafeMode(void);
