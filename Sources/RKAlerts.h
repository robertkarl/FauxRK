#import <Cocoa/Cocoa.h>
@interface RKAlerts : NSObject
- (instancetype)initWithOpen:(void (^)(NSString *paneID))open;
- (void)updatePanes:(NSArray<NSDictionary *> *)panes attention:(NSDictionary<NSString *, NSDictionary *> *)rows;
@end
