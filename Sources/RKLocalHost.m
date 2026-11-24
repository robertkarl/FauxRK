#import "RKHost.h"
#import "RKCore.h"
#import "RKRemoteTerminal.h"

static id RKHostFailure(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"RKHostOperation" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}

static BOOL RKText(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0;
}

static BOOL RKValidChoice(NSDictionary *choice) {
    if (![choice isKindOfClass:NSDictionary.class] || !RKText(choice[@"label"])) return NO;
    NSSet *allowed = [NSSet setWithArray:@[@"label", @"text", @"key", @"keys", @"draft"]];
    if (![[NSSet setWithArray:choice.allKeys] isSubsetOfSet:allowed]) return NO;
    NSUInteger forms = (choice[@"text"] != nil) + (choice[@"key"] != nil) + (choice[@"keys"] != nil);
    if (forms != 1) return NO;
    if (choice[@"draft"] && (![choice[@"draft"] isKindOfClass:NSNumber.class] || !choice[@"text"])) return NO;
    if (choice[@"text"]) return RKText(choice[@"text"]);
    if (choice[@"key"]) return RKText(choice[@"key"]);
    NSArray *keys = choice[@"keys"];
    if (![keys isKindOfClass:NSArray.class] || !keys.count || keys.count > 16) return NO;
    for (id key in keys) if (!RKText(key)) return NO;
    return YES;
}

static BOOL RKValidTarget(NSString *target) {
    static NSRegularExpression *format;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        format = [NSRegularExpression regularExpressionWithPattern:@"\\A%[0-9]+\\|[0-9]+-[0-9]+-[0-9]+\\|([A-Fa-f0-9-]{36})?\\z" options:0 error:NULL];
    });
    return [format firstMatchInString:target options:0 range:NSMakeRange(0,target.length)] != nil;
}

static NSDictionary<NSString *,NSArray<NSString *> *> *RKOperationFields(void) {
    static NSDictionary *fields;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *target = @[@"target"];
        fields = @{@"snapshot":@[@"provider?", @"model?", @"focusToken?"], @"spawn":@[@"preset", @"directory", @"prompt?"],
            @"capture":target, @"interrupt":target, @"end":target, @"preview":target, @"attach":target, @"open":target,
            @"steer":@[@"target",@"text"], @"read":@[@"id",@"fingerprint"], @"answer":@[@"id",@"fingerprint",@"choice"]};
    });
    return fields;
}

static NSString *RKArgumentError(NSString *operation, NSDictionary *args) {
    NSArray *fields = RKOperationFields()[operation];
    if (!fields) return @"Unknown FauxRK host operation.";
    if (![args isKindOfClass:NSDictionary.class]) return @"Host arguments must be a JSON object.";
    NSMutableSet *allowed = [NSMutableSet new];
    for (NSString *field in fields) {
        BOOL optional = [field hasSuffix:@"?"];
        NSString *key = optional ? [field substringToIndex:field.length-1] : field;
        [allowed addObject:key];
        id value = args[key];
        if (optional && !value) continue;
        BOOL valid;
        if ([key isEqual:@"choice"]) valid = RKValidChoice(value);
        else if ([key isEqual:@"prompt"] || [key isEqual:@"focusToken"] || [key isEqual:@"model"]) valid = [value isKindOfClass:NSString.class];
        else valid = RKText(value);
        if (!valid) return [NSString stringWithFormat:@"Invalid or missing '%@' for %@.",key,operation];
    }
    if (![[NSSet setWithArray:args.allKeys] isSubsetOfSet:allowed]) return @"Unexpected FauxRK host argument.";
    if (args[@"target"] && !RKValidTarget(args[@"target"])) return @"A complete pane identity from a recent snapshot is required.";
    return nil;
}

@interface RKLocalHost ()
@property(nonatomic) RKCore *core;
@property(nonatomic) RKMonitor *monitor;
@property(nonatomic) BOOL sshHelper;
@end

@implementation RKLocalHost
- (instancetype)init { return [self initForSSH:NO]; }
- (instancetype)initForSSHHelper { return [self initForSSH:YES]; }
- (instancetype)initForSSH:(BOOL)remote {
    if ((self = [super init])) {
        _sshHelper = remote;
        _core = [[RKCore alloc] initWithDesktopFocus:!remote];
        _monitor = [[RKMonitor alloc] initWithCore:_core];
    }
    return self;
}

- (BOOL)configureHelper:(NSDictionary *)args error:(NSError **)error {
    if (!args.count) return YES;
    if (!self.sshHelper) {
        RKHostFailure(error, @"Local snapshots use the preferences configured on this Mac.");
        return NO;
    }
    NSString *provider = args[@"provider"], *model = args[@"model"];
    if (provider && ![@[@"sonnet", @"local"] containsObject:provider]) {
        RKHostFailure(error, @"Unknown helper provider.");
        return NO;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *prior = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *domain = [prior mutableCopy] ?: [NSMutableDictionary new];
    if (provider) domain[@"RKHelperProvider"] = provider;
    if (model) domain[@"RKLocalModel"] = model.length ? model : @"qwen3:4b";
    // Each SSH connection owns a helper process. These overrides disappear
    // on disconnect and do not write the remote user's RK preferences.
    if (![domain isEqual:prior]) [defaults setVolatileDomain:domain forName:NSArgumentDomain];
    return YES;
}

- (id)request:(NSString *)operation arguments:(NSDictionary *)args error:(NSError **)error {
    if (!RKText(operation)) return RKHostFailure(error, @"A host operation is required.");
    NSString *invalid = RKArgumentError(operation,args);
    if (invalid) return RKHostFailure(error, invalid);
    NSString *target = args[@"target"];
    if ([operation isEqual:@"snapshot"]) {
        if (![self configureHelper:args error:error]) return nil;
        NSArray *panes = [self.core panes:error];
        if (!panes) return nil;
        NSString *token = args[@"focusToken"];
        if (self.sshHelper && token.length) {
            NSString *focused = [RKRemoteTerminal focusedPaneForToken:token core:self.core];
            if (focused) {
                NSMutableArray *inventory = [panes mutableCopy];
                for (NSUInteger i = 0; i < inventory.count; i++) {
                    if (![inventory[i][@"id"] isEqual:focused]) continue;
                    NSMutableDictionary *pane = [inventory[i] mutableCopy];
                    pane[@"focused"] = @YES;
                    inventory[i] = pane;
                    break;
                }
                panes = inventory;
            }
        }
        return @{@"panes":panes, @"attention":[self.monitor update:panes]};
    }
    if ([operation isEqual:@"spawn"]) {
        NSString *directory = args[@"directory"];
        NSArray *folders = @[@"~/Code/regina/", @"~/homelab/", @"~/Code/unbiasedbob-private/"];
        if (self.sshHelper && ![folders containsObject:directory])
            return RKHostFailure(error, @"Choose one of Debra’s three project directories.");
        return [self.core spawnPreset:args[@"preset"] directory:directory prompt:args[@"prompt"] ?: @"" error:error];
    }
    if ([operation isEqual:@"preview"]) return [self.monitor preview:target error:error];
    if ([operation isEqual:@"attach"]) return [self.core attachMetadata:target error:error];
    if ([operation isEqual:@"read"]) {
        [self.monitor markRead:args[@"id"] fingerprint:args[@"fingerprint"]];
        return @YES;
    }
    BOOL done;
    if ([operation isEqual:@"capture"]) done = [self.core capture:target error:error];
    else if ([operation isEqual:@"end"]) done = [self.core end:target error:error];
    else if ([operation isEqual:@"interrupt"]) done = [self.core interrupt:target error:error];
    else if ([operation isEqual:@"steer"]) done = [self.monitor steer:args[@"text"] toTarget:target error:error];
    else if ([operation isEqual:@"answer"]) done = [self.monitor answer:args[@"choice"] pane:args[@"id"] fingerprint:args[@"fingerprint"] error:error];
    else if ([operation isEqual:@"open"] && !self.sshHelper) done = [self.core openWindow:target error:error];
    else return RKHostFailure(error, @"This operation is unavailable on this host.");
    return done ? @YES : nil;
}
@end
