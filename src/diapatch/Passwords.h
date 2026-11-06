#import <Foundation/Foundation.h>

extern NSString *const DPPasswordsAgent;
extern NSString *const DPCopyFolder;

BOOL DPIsPasswordsOrigin(const char *origin);
BOOL DPIsPasswordsHandoff(int argc, const char *argv[]);
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]);
int DPRunPasswordsHandoff(void);
int DPRunPasswordsRelay(NSString *home, NSString *app);
NSDictionary *DPPasswordsAgentPlist(NSString *home, NSString *diapatch, NSDictionary *environment);
