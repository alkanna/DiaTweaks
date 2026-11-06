#import "StdPatch/Hide.h"

extern DPPatch DPTurnOffAI;

// Settings rows and shortcuts named after one of Dia's AI features.
BOOL DPIsAITitle(NSString *title);

void DPInstallAIRows(void);
void DPApplyAIRows(void);
