#import "RKApp.h"
#import "RKHost.h"
#import "RKSidebar.h"

@interface RKApp (RoutingTests)
- (void)replaceRoute;
- (void)selectHost:(NSString *)hostID;
- (void)steerPane:(NSString *)paneID text:(NSString *)text;
- (void)willSleep:(NSNotification *)notification;
- (void)didWake:(NSNotification *)notification;
@end

@interface FixtureHost : NSObject <RKHost>
@property dispatch_semaphore_t entered;
@property dispatch_semaphore_t resume;
@property BOOL holdSnapshot;
@property BOOL dropSend;
@property NSString *identity;
@property (atomic) NSUInteger sends;
@end
@implementation FixtureHost
- (instancetype)init {
    if ((self = [super init])) {
        _entered = dispatch_semaphore_create(0);
        _resume = dispatch_semaphore_create(0);
        _identity = NSUUID.UUID.UUIDString;
    }
    return self;
}
- (id)request:(NSString *)op arguments:(NSDictionary *)args error:(NSError **)error {
    if ([op isEqual:@"snapshot"]) {
        if (self.holdSnapshot) {
            dispatch_semaphore_signal(self.entered);
            dispatch_semaphore_wait(self.resume, DISPATCH_TIME_FOREVER);
        }
        return @{@"panes":@[@{@"id":@"%0", @"target":self.identity, @"managed":@YES}], @"attention":@{}};
    }
    NSCAssert([op isEqual:@"steer"] && [args[@"target"] isEqual:self.identity], @"Mutation crossed host boundary");
    self.sends++;
    if (!self.dropSend) return @YES;
    dispatch_semaphore_signal(self.entered);
    dispatch_semaphore_wait(self.resume, DISPATCH_TIME_FOREVER);
    *error = [NSError errorWithDomain:RKTransportErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"Delivery unconfirmed"}];
    return nil;
}
@end

@interface FixtureSidebar : NSObject
@property NSString *status;
@property NSString *displayed;
@property NSUInteger displayedSnapshots;
@property NSUInteger acknowledgements;
@end
@implementation FixtureSidebar
- (void)switchToHost:(NSString *)hostID { self.displayed = nil; }
- (void)showDisconnectedLastSeen:(NSDate *)date {}
- (void)displayPanes:(NSArray *)panes attention:(NSDictionary *)rows {
    self.displayed = [panes.firstObject objectForKey:@"target"];
    self.displayedSnapshots++;
}
- (void)showStatus:(NSString *)status { self.status = status; }
- (void)didSendText:(NSString *)text forPane:(NSString *)pane { self.acknowledgements++; }
@end

@interface FixtureApp : RKApp
@property FixtureHost *nextHost;
@end
@implementation FixtureApp
- (void)replaceRoute {
    [super replaceRoute];
    [[self valueForKey:@"route"] setValue:self.nextHost forKey:@"host"];
}
@end

static void waitFor(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSCAssert(condition(), @"Routing event timed out");
}

static void waitForEntry(FixtureHost *host) {
    NSCAssert(dispatch_semaphore_wait(host.entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, @"Host was never called");
}

int main(void) {
    @autoreleasepool {
        FixtureApp *app = [FixtureApp new];
        FixtureSidebar *sidebar = [FixtureSidebar new];
        [app setValue:sidebar forKey:@"sidebar"];
        FixtureHost *local = [FixtureHost new], *remote = [FixtureHost new], *reconnected = [FixtureHost new];
        local.holdSnapshot = YES;
        app.nextHost = local;
        [app selectHost:@"local"];
        waitForEntry(local);
        app.nextHost = remote;
        [app selectHost:@"debra"];
        waitFor(^BOOL{ return [sidebar.displayed isEqual:remote.identity]; });
        dispatch_semaphore_signal(local.resume);
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        NSCAssert(sidebar.displayedSnapshots == 1, @"A late local snapshot replaced the Debra view");

        remote.dropSend = YES;
        [app steerPane:@"%0" text:@"first"];
        waitForEntry(remote);
        [app steerPane:@"%0" text:@"queued"];
        app.nextHost = reconnected;
        [app willSleep:nil];
        [app didWake:nil];
        waitFor(^BOOL{ return [sidebar.displayed isEqual:reconnected.identity]; });
        dispatch_semaphore_signal(remote.resume);
        waitFor(^BOOL{ return [sidebar.status isEqual:@"Delivery unconfirmed"]; });
        NSCAssert(remote.sends == 1 && reconnected.sends == 0 && sidebar.acknowledgements == 0,
                  @"Queued or unconfirmed send replayed or cleared a draft");
        [app steerPane:@"%0" text:@"explicit new send"];
        waitFor(^BOOL{ return sidebar.acknowledgements == 1; });
        NSCAssert(reconnected.sends == 1, @"New explicit send was not delivered");
    }
    puts("host routing passed (late snapshots, queued commands, sleep, uncertain delivery)");
}
