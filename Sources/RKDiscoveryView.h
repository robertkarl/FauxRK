#import "RKSidebar.h"

@interface RKDiscoveryView : NSView
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate;
- (void)displayPanes:(NSArray<NSDictionary *> *)panes;
@end
