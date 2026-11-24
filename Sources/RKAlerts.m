#import "RKAlerts.h"
#import <UserNotifications/UserNotifications.h>

@interface RKAlerts () <UNUserNotificationCenterDelegate>
@property (copy) void (^open)(NSString *);
@property UNUserNotificationCenter *center;
@property NSMutableDictionary<NSString *, NSString *> *delivered;
@property NSMutableSet<NSString *> *pending;
@property BOOL requested;
@property BOOL authorized;
@property NSString *store;
@end

@implementation RKAlerts
- (instancetype)initWithOpen:(void (^)(NSString *))open {
    if ((self = [super init])) {
        _open = [open copy];
        NSString *socket = NSProcessInfo.processInfo.environment[@"RK_TMUX_SOCKET"] ?: @"default";
        _store = [@"RKAlertState." stringByAppendingString:socket];
        _delivered = [[NSUserDefaults.standardUserDefaults dictionaryForKey:_store] mutableCopy] ?: [NSMutableDictionary dictionary];
        _pending = [NSMutableSet set];
        _center = UNUserNotificationCenter.currentNotificationCenter;
        _center.delegate = self;
    }
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
    if (!self.authorized || !fingerprint.length || [self.delivered[identity] isEqual:fingerprint] || [self.pending containsObject:identity]) return;
    if ([pane[@"focused"] boolValue] || NSApp.isActive) return;
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = [pane[@"title"] length] ? pane[@"title"] : pane[@"session"];
    content.body = row[@"summary"] ?: row[@"question"] ?: @"Agent needs attention";
    content.userInfo = @{@"pane":pane[@"id"], @"identity":identity};
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identity content:content trigger:nil];
    [self.pending addObject:identity];
    __weak typeof(self) weakSelf = self;
    [self.center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.pending removeObject:identity];
            if (!error) {
                self.delivered[identity] = fingerprint;
                [NSUserDefaults.standardUserDefaults setObject:self.delivered forKey:self.store];
            }
        });
    }];
}

- (void)updatePanes:(NSArray<NSDictionary *> *)panes attention:(NSDictionary<NSString *,NSDictionary *> *)rows {
    NSMutableSet *live = [NSMutableSet set];
    for (NSDictionary *pane in panes) {
        if (![pane[@"managed"] boolValue]) continue;
        [self authorize];
        NSString *identity = pane[@"rkID"];
        NSDictionary *row = rows[pane[@"id"]];
        if (!row) continue;
        [live addObject:identity];
        [self sendRow:row pane:pane identity:identity];
    }
    NSMutableSet *resolved = [NSMutableSet setWithArray:self.delivered.allKeys];
    [resolved minusSet:live];
    if (resolved.count) {
        [self.center removeDeliveredNotificationsWithIdentifiers:resolved.allObjects];
        [self.delivered removeObjectsForKeys:resolved.allObjects];
        [NSUserDefaults.standardUserDefaults setObject:self.delivered forKey:self.store];
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))done {
    NSString *identity = response.notification.request.content.userInfo[@"identity"];
    dispatch_async(dispatch_get_main_queue(), ^{ if (identity) self.open(identity); done(); });
}
@end
