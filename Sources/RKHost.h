#import <Foundation/Foundation.h>

// The UI sends the same requests to an in-process host or a helper over SSH.
@protocol RKHost <NSObject>
- (id)request:(NSString *)operation arguments:(NSDictionary *)arguments error:(NSError **)error;
@end

@interface RKLocalHost : NSObject <RKHost>
- (instancetype)initForSSHHelper;
- (void)finishBackgroundWork;
@end

@interface RKRemoteHost : NSObject <RKHost>
- (instancetype)initWithDestination:(NSString *)destination helperURL:(NSURL *)helperURL;
// Only snapshot may reconnect. User actions require an established connection.
- (void)disconnect;
@end

FOUNDATION_EXPORT NSString *const RKTransportErrorDomain;
