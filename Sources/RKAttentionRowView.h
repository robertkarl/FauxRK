#import <AppKit/AppKit.h>

/// A single actionable handoff in the sidebar's Needs attention section.
@interface RKAttentionRowView : NSView
@property(nonatomic, copy) void (^answerChoice)(NSDictionary *choice);
- (void)focusForReview;
- (instancetype)initWithPaneTitle:(NSString *)title
                          request:(NSDictionary *)request
                           action:(dispatch_block_t)open;
@end
