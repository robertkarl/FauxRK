#import "RKAlerts.h"
#import <UserNotifications/UserNotifications.h>

@interface RKAlerts () <UNUserNotificationCenterDelegate>
@property (copy) void (^open)(NSString *);
@property (copy) BOOL (^foreground)(void);
@property UNUserNotificationCenter *center;
@property NSUserDefaults *defaults;
@property NSMutableDictionary<NSString *, NSString *> *delivered;
@property NSMutableSet<NSString *> *pending;
@property NSDictionary<NSString *, NSString *> *live;
@property BOOL requested;
@property BOOL authorized;
@property NSString *store;
@end

@implementation RKAlerts
- (instancetype)initWithOpen:(void (^)(NSString *))open {
    return [self initWithOpen:open center:UNUserNotificationCenter.currentNotificationCenter
                     defaults:NSUserDefaults.standardUserDefaults foreground:^BOOL{ return NSApp.isActive; }];
}

- (instancetype)initWithOpen:(void (^)(NSString *))open center:(UNUserNotificationCenter *)center
                    defaults:(NSUserDefaults *)defaults foreground:(BOOL (^)(void))foreground {
    if (!(self = [super init])) return nil;
    _open = [open copy];
    _foreground = [foreground copy];
    _defaults = defaults;
    NSString *socket = NSProcessInfo.processInfo.environment[@"RK_TMUX_SOCKET"] ?: @"default";
    _store = [@"RKAlertState." stringByAppendingString:socket];
    _delivered = [[defaults dictionaryForKey:_store] mutableCopy] ?: [NSMutableDictionary dictionary];
    _pending = [NSMutableSet set];
    _center = center;
    _center.delegate = self;
    return self;
}

- (void)authorize {
    if (self.requested) return;
    self.requested = YES;
    [self.center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL allowed, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.authorized = allowed; });
    }];
}

- (void)sendRow:(NSDictionary *)row pane:(NSDictionary *)pane identity:(NSString *)identity {
    NSString *fingerprint = row[@"fingerprint"];
    if (!self.authorized || [pane[@"focused"] boolValue] || self.foreground()) return;
    if ([self.delivered[identity] isEqual:fingerprint] || [self.pending containsObject:identity]) return;
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = [pane[@"title"] length] ? pane[@"title"] : pane[@"session"];
    content.body = row[@"summary"] ?: row[@"question"] ?: @"Agent needs attention";
    content.userInfo = @{@"identity":identity};
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identity content:content trigger:nil];
    [self.pending addObject:identity];
    __weak typeof(self) weakSelf = self;
    [self.center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.pending removeObject:identity];
            if (error) return;
            if ([self.live[identity] isEqual:fingerprint]) {
                self.delivered[identity] = fingerprint;
                [self.defaults setObject:self.delivered forKey:self.store];
            } else {
                [self.center removeDeliveredNotificationsWithIdentifiers:@[identity]];
            }
        });
    }];
}

- (void)updatePanes:(NSArray<NSDictionary *> *)panes attention:(NSDictionary<NSString *,NSDictionary *> *)rows {
    NSMutableDictionary *live = [NSMutableDictionary dictionary];
    NSMutableArray *waiting = [NSMutableArray array];
    for (NSDictionary *pane in panes) {
        if (![pane[@"managed"] boolValue]) continue;
        [self authorize];
        NSString *identity = pane[@"rkID"];
        NSDictionary *row = rows[pane[@"id"]];
        NSString *fingerprint = row[@"fingerprint"];
        if (!identity.length || !fingerprint.length) continue;
        live[identity] = fingerprint;
        [waiting addObject:pane];
    }
    self.live = live;
    [self clearObsoleteDeliveries];
    for (NSDictionary *pane in waiting) {
        [self sendRow:rows[pane[@"id"]] pane:pane identity:pane[@"rkID"]];
    }
}

- (void)clearObsoleteDeliveries {
    NSMutableArray *obsolete = [NSMutableArray array];
    [self.delivered enumerateKeysAndObjectsUsingBlock:^(NSString *identity, NSString *fingerprint, BOOL *stop) {
        if (![fingerprint isEqual:self.live[identity]]) [obsolete addObject:identity];
    }];
    if (!obsolete.count) return;
    [self.center removeDeliveredNotificationsWithIdentifiers:obsolete];
    [self.delivered removeObjectsForKeys:obsolete];
    [self.defaults setObject:self.delivered forKey:self.store];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))done {
    UNNotificationRequest *request = response.notification.request;
    NSString *identity = request.content.userInfo[@"identity"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([identity isKindOfClass:NSString.class] && identity.length && [identity isEqual:request.identifier]) self.open(identity);
        done();
    });
}
@end
