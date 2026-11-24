#import "RKSidebar.h"
#import "RKSidebarViews.h"

@interface RKSpawnView : RKPanelView
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate;
- (void)acknowledgePrompt:(NSString *)prompt;
@end
