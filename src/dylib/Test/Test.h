#import "StdPatch/StdPatch.h"

void DPRunTests(NSString *reportPath);
NSMutableArray<NSArray<NSString *> *> *DPScenarios(void);  // [name, one '0' or '1' per patch]
NSString *DPBits(const int8_t *state);
