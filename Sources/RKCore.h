#import <Foundation/Foundation.h>

// All tmux operations target the local server. Tests may select RK_TMUX_SOCKET.
@interface RKCore : NSObject
// Each pane has string fields id, session, window, command, path, title, activity,
// and numeric fields managed, focused, attached. id is the tmux %pane_id.
- (NSArray<NSDictionary *> *)panes:(NSError **)error;
- (NSString *)spawnPreset:(NSString *)preset directory:(NSString *)directory prompt:(NSString *)prompt error:(NSError **)error;
- (BOOL)capture:(NSString *)paneID error:(NSError **)error;
- (BOOL)sendText:(NSString *)text toPane:(NSString *)paneID error:(NSError **)error;
- (BOOL)sendKey:(NSString *)key toPane:(NSString *)paneID error:(NSError **)error;
- (NSString *)screen:(NSString *)paneID error:(NSError **)error;
- (BOOL)interrupt:(NSString *)paneID error:(NSError **)error;
- (BOOL)end:(NSString *)paneID error:(NSError **)error;
- (BOOL)openWindow:(NSString *)paneID error:(NSError **)error;
@end

@interface RKMonitor : NSObject
- (instancetype)initWithCore:(RKCore *)core;
// Call from a serial background queue. Rows keyed by pane id. Stable row fields:
// kind ("input", "maybe", "complete"), summary, question, fingerprint, choices
// (array of {label,key} or {label,text}), suggestedReply (optional).
- (NSDictionary<NSString *,NSDictionary *> *)update:(NSArray<NSDictionary *> *)panes;
- (void)markRead:(NSString *)paneID fingerprint:(NSString *)fingerprint;
- (BOOL)answer:(NSDictionary *)choice pane:(NSString *)paneID fingerprint:(NSString *)fingerprint error:(NSError **)error;
- (NSString *)preview:(NSString *)paneID error:(NSError **)error;
@end
