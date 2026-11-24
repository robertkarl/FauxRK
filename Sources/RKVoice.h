#import <Cocoa/Cocoa.h>
@interface RKVoice : NSObject
- (instancetype)initWithStatus:(void (^)(NSString *))status;
- (void)beginWithEditor:(NSTextView *)editor;
- (void)finish;
- (void)cancel;
@end
