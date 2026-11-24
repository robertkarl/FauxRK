#import "RKSidebar.h"
#import "RKSidebarViews.h"

NSString *RKPaneTitle(NSDictionary *pane);
NSString *RKRequestKind(NSDictionary *request);
RKTint RKRequestTint(NSDictionary *request);

@interface RKAgentCardView : RKPanelView
@property (nonatomic, readonly) NSString *paneID;
@property (nonatomic, copy) dispatch_block_t requestEnd;
@property (nonatomic, copy) dispatch_block_t openCard;
@property (nonatomic, getter=isExpanded) BOOL expanded;
- (instancetype)initWithPaneID:(NSString *)paneID delegate:(id<RKSidebarDelegate>)delegate;
- (void)updatePane:(NSDictionary *)pane request:(NSDictionary *)request;
- (void)acknowledgeText:(NSString *)text;
@end
