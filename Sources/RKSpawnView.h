#import "RKSidebar.h"
#import "RKSidebarViews.h"

@interface RKSpawnView : RKPanelView
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate remote:(BOOL)remote;
- (BOOL)chooseProject:(NSString *)directory;
- (void)acknowledgePrompt:(NSString *)prompt;
@end
