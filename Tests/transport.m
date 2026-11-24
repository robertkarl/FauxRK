#import "RKHost.h"

@interface FixtureHost : RKRemoteHost
@end
@implementation FixtureHost
- (NSString *)sshExecutable { return NSProcessInfo.processInfo.environment[@"RK_FIXTURE_SSH"]; }
- (NSTimeInterval)timeoutForOperation:(NSString *)operation { return [operation isEqual:@"hang"] ? 0.3 : 5; }
@end

static void check(BOOL ok, NSString *msg) {
    if (!ok) { fprintf(stderr,"%s\n",msg.UTF8String); exit(1); }
}
static NSString *path(NSString *file) {
    return [NSProcessInfo.processInfo.environment[@"RK_FIXTURE_ACCOUNT"] stringByAppendingPathComponent:file];
}
static FixtureHost *host(NSString *binary) {
    return [[FixtureHost alloc] initWithDestination:@"test@Debra" helperURL:[NSURL fileURLWithPath:path(binary)]];
}
static NSDictionary *snapshot(FixtureHost *h) {
    NSError *error;
    NSDictionary *v = [h request:@"snapshot" arguments:@{} error:&error];
    check([v[@"ok"] boolValue],error.localizedDescription ?: @"Could not fetch snapshot");
    return v;
}
static NSArray *installed(void) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtPath:path(@"Library/Application Support/FauxRK/Helpers") error:nil];
}
static BOOL waitForFile(NSString *name) {
    for(int i=0;i<100;i++) {
        if ([NSFileManager.defaultManager fileExistsAtPath:path(name)]) return YES;
        [NSThread sleepForTimeInterval:0.03];
    }
    return NO;
}
int main(void) { @autoreleasepool {
    NSError *error;
    FixtureHost *h = host(@"helper-v1");
    check(![h request:@"spawn" arguments:@{} error:&error] && [error.domain isEqual:RKTransportErrorDomain],@"Action attempted before snapshot");
    check(![NSFileManager.defaultManager fileExistsAtPath:path(@"connections")],@"An action initiated SSH");
    NSDictionary *one = snapshot(h);
    check(installed().count == 1,@"First connect did not install a single matching helper");
    NSString *installedPath = [path(@"Library/Application Support/FauxRK/Helpers") stringByAppendingPathComponent:installed().firstObject];
    check([[NSData dataWithContentsOfFile:installedPath] isEqual:[NSData dataWithContentsOfFile:path(@"helper-v1")]],@"Installed bytes differ");
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:installedPath error:nil];
    check([attrs[NSFilePosixPermissions] intValue] == 0700,@"Executable is not owner-only");

    dispatch_semaphore_t previewDone = dispatch_semaphore_create(0);
    __block NSString *answer;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        answer = [h request:@"preview" arguments:@{} error:nil];
        dispatch_semaphore_signal(previewDone);
    });
    check(waitForFile(@"preview-started"),@"Preview did not start");
    check([snapshot(h)[@"pid"] isEqual:one[@"pid"]],@"Snapshot opened a second SSH connection");
    [NSData.data writeToFile:path(@"finish-preview") atomically:YES];
    check(!dispatch_semaphore_wait(previewDone,dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC)) && [answer isEqual:@"preview complete"],@"Preview response was misrouted");
    check(![h request:@"rejected" arguments:@{} error:&error] && ![error.domain isEqual:RKTransportErrorDomain],@"Operation rejection was classified as transport loss");
    check([snapshot(h)[@"pid"] isEqual:one[@"pid"]],@"A helper-side action error closed the channel");

    NSString *literal = @"- quoted '; $(touch BAD)\nsecond line 🥑";
    check([[h request:@"echo" arguments:@{@"text":literal} error:&error] isEqual:literal],@"JSON text did not round-trip");
    check(![h request:@"steer" arguments:@{@"text":literal} error:&error] && [error.domain isEqual:RKTransportErrorDomain] && error.code == 2,@"Missing unconfirmed delivery after disconnect");
    check(![h request:@"steer" arguments:@{} error:&error] && error.code == 1,@"Action reconnected disconnected host");
    NSDictionary *two = snapshot(h);
    check(![two[@"pid"] isEqual:one[@"pid"]],@"Snapshot did not reconnect");
    check([[NSString stringWithContentsOfFile:path(@"sent") encoding:NSUTF8StringEncoding error:nil] isEqual:@"once\n"],@"A mutation was replayed");
    NSDictionary *after = [NSFileManager.defaultManager attributesOfItemAtPath:installedPath error:nil];
    check([attrs[NSFileSystemFileNumber] isEqual:after[NSFileSystemFileNumber]],@"Identical helper was reinstalled");
    check(![h request:@"hang" arguments:@{} error:&error] && error.code==2,@"Timed out request did not become unconfirmed");
    snapshot(h);
    [h disconnect];
    check(![h request:@"snapshot" arguments:@{} error:&error],@"Retired host reconnected");

    [@"corrupt" writeToFile:installedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    FixtureHost *repaired = host(@"helper-v1");
    snapshot(repaired); [repaired disconnect];
    check([[NSData dataWithContentsOfFile:installedPath] isEqual:[NSData dataWithContentsOfFile:path(@"helper-v1")]],@"Corrupted helper did not self-repair");
    FixtureHost *upgraded = host(@"helper-v2");
    snapshot(upgraded);
    check(installed().count == 2,@"New helper build did not install");
    NSString *releasePath = path(@"finish-preview");
    [NSFileManager.defaultManager removeItemAtPath:releasePath error:nil];
    dispatch_semaphore_t left = dispatch_semaphore_create(0);
    __block NSError *previewError;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{ [upgraded request:@"preview" arguments:@{} error:&previewError]; dispatch_semaphore_signal(left); });
    [NSThread sleepForTimeInterval:.1];
    [upgraded disconnect];
    check(!dispatch_semaphore_wait(left,dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC)) && [previewError.domain isEqual:RKTransportErrorDomain],@"Switch did not wake pending preview");
    puts("ssh transport passed (install, reuse, upgrade, out-of-order preview, uncertain delivery, timeout, reconnect, switch)");
}}
