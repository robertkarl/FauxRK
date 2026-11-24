#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
@protocol RKSidebarDelegate <NSObject>
- (void)spawnPreset:(NSString *)preset directory:(NSString *)directory prompt:(NSString *)prompt;
- (void)sortPanesByActivity;
- (void)capturePane:(NSString *)paneID;
- (void)previewPane:(NSString *)paneID;
- (void)steerPane:(NSString *)paneID text:(NSString *)text;
- (void)interruptPane:(NSString *)paneID;
- (void)endPane:(NSString *)paneID;
- (void)openTerminalForPane:(NSString *)paneID;
- (void)readAttentionForPane:(NSString *)paneID fingerprint:(NSString *)fingerprint;
- (void)answerPane:(NSString *)paneID fingerprint:(NSString *)fingerprint choice:(NSDictionary *)choice;
@end

@interface RKSidebar : NSWindowController
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate;
// All methods run on the main thread. Panes arrive in display order.
- (void)displayPanes:(NSArray<NSDictionary *> *)panes attention:(NSDictionary<NSString *, NSDictionary *> *)attention;
- (void)showStatus:(NSString *)message;
- (void)showPreview:(NSString *)text forPane:(NSString *)paneID;
- (void)revealPane:(NSString *)paneID;
- (void)showSpawn;
- (void)showSpawnInProject:(NSString *)directory;
// Acknowledge successful submission without erasing edits made while it was pending.
- (void)didSendText:(NSString *)text forPane:(NSString *)paneID;
- (void)didSpawnWithPrompt:(NSString *)prompt;
- (nullable NSTextView *)focusedPromptEditor;
@end
NS_ASSUME_NONNULL_END
