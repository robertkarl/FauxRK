#import <Cocoa/Cocoa.h>
extern NSString *const RKAlertsThisMac;
extern NSString *const RKAlertsDebra;
@interface RKAlerts : NSObject
- (instancetype)initWithOpen:(void (^)(NSString *managedIdentity))open;
- (void)updatePanes:(NSArray<NSDictionary *> *)panes attention:(NSDictionary<NSString *, NSDictionary *> *)rows;
// "This Mac" (default) or "Debra". Switching removes the previous computer's notifications and ignores its late completions.
- (void)selectComputer:(NSString *)computer;
// Call after a remote reconnect. The next update with resolved authorization folds the outstanding backlog into a single
// summary notification (or consumes it silently when RK is in front). Clicking the summary opens with an empty identity.
- (void)beginCatchUp;
@end
