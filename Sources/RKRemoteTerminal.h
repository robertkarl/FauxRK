#import <Foundation/Foundation.h>

@class RKCore;

// Laptop-side terminal attachments to a remote host's managed tmux sessions.
@interface RKRemoteTerminal : NSObject
// Metadata includes sessionID, the tmux binary, and the resolved socketPath.
// Earlier helpers may omit socketPath to use the default server. The target is
// the managed live target "%pane|generation|uuid". Opens a fresh local iTerm2 window running
// ssh -t to destination. On the remote side a guard re-checks the pane's generation and
// ownership marker before attaching, and registers this iTerm session for focus matching.
+ (BOOL)openAttachment:(NSDictionary *)metadata target:(NSString *)target destination:(NSString *)destination error:(NSError **)error;
// The unique ID of iTerm2's focused session, or @"" when iTerm2 is not frontmost or
// Automation is not already authorized. Never prompts.
+ (NSString *)focusedToken;
// Helper side: the pane shown by the live tmux client that an attachment registered for
// token, or nil when no attached client is registered under that token.
+ (NSString *)focusedPaneForToken:(NSString *)token core:(RKCore *)core;
@end
