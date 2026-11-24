#import "RKHost.h"
#import <CommonCrypto/CommonDigest.h>

static void Require(BOOL valid, NSString *reason) {
    if (!valid) @throw [NSException exceptionWithName:@"RemoteFixture" reason:reason userInfo:nil];
}
static void Pass(const char *phase) { printf("PASS %s\n",phase); fflush(stdout); }
static id Call(RKRemoteHost *host, NSString *op, NSDictionary *args) {
    NSError *error = nil;
    id result = [host request:op arguments:args error:&error];
    Require(result != nil, [NSString stringWithFormat:@"%@ failed: %@",op,error.localizedDescription ?: @"no response"]);
    return result;
}
static NSDictionary *Snapshot(RKRemoteHost *host) {
    return Call(host, @"snapshot", @{@"provider":@"local"});
}
static NSDictionary *Pane(NSDictionary *snapshot, NSString *pid) {
    for (NSDictionary *p in snapshot[@"panes"]) if ([p[@"id"] isEqual:pid]) return p;
    return nil;
}
static NSDictionary *WaitForRow(RKRemoteHost *host, NSString *pid, NSString *kind, NSString *content, NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    do {
        NSDictionary *row = Snapshot(host)[@"attention"][pid];
        NSString *text = [NSString stringWithFormat:@"%@ %@",row[@"question"] ?: @"",row[@"summary"] ?: @""];
        if ([row[@"kind"] isEqual:kind] && [text localizedCaseInsensitiveContainsString:content]) return row;
        [NSThread sleepForTimeInterval:.25];
    } while (deadline.timeIntervalSinceNow > 0);
    Require(NO, [NSString stringWithFormat:@"Timed out waiting for fixture's %@ event",kind]);
    return nil;
}
static NSString *Digest(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i=0; i<sizeof(bytes); i++) [result appendFormat:@"%02x",bytes[i]];
    return result;
}
static RKRemoteHost *Connect(NSString *dest, NSString *helper) {
    return [[RKRemoteHost alloc] initWithDestination:dest helperURL:[NSURL fileURLWithPath:helper]];
}
static NSSet *OtherTargets(NSDictionary *snapshot, NSString *fixtureID) {
    NSMutableSet *targets = [NSMutableSet set];
    for (NSDictionary *pane in snapshot[@"panes"]) {
        if (![pane[@"id"] isEqual:fixtureID]) [targets addObject:pane[@"target"]];
    }
    return targets;
}
static void End(RKRemoteHost *host, NSDictionary *pane) {
    Call(host,@"end",@{@"target":pane[@"target"]});
    Require(Pane(Snapshot(host),pane[@"id"]) == nil, @"Disposable session survived end");
}

static void Exercise(NSString *dest, NSString *helper, NSString *pid, NSString *nonce) {
    RKRemoteHost *host = Connect(dest,helper);
    NSDictionary *initial = Snapshot(host);
    NSDictionary *fixture = Pane(initial,pid);
    NSString *name = [@"fauxrk-test-" stringByAppendingString:nonce];
    Require(fixture && [fixture[@"session"] isEqual:name] && ![fixture[@"managed"] boolValue], @"Fixture identity mismatch; refusing to act");
    NSSet *originalTargets = OtherTargets(initial,pid);
    Pass("SSH helper and initial snapshot");
    Call(host,@"capture",@{@"target":fixture[@"target"]});
    NSDictionary *managed = Pane(Snapshot(host),pid);
    Require([managed[@"managed"] boolValue] && [managed[@"panePID"] isEqual:fixture[@"panePID"]], @"Capture failed to transfer the live process");
    Pass("capture preserves pane and process identity");
    NSString *message = [NSString stringWithFormat:@"show me the pdf for %@\nverbatim: 'quote' \"nested\" $(literal) #{} café →",nonce];
    Call(host,@"steer",@{@"target":managed[@"target"], @"text":message});
    NSDictionary *row = WaitForRow(host,pid,@"input",Digest(message),5);
    Pass("verbatim multiline/Unicode steer and five-second blocker detection");
    NSDictionary *yes = nil;
    for (NSDictionary *choice in row[@"choices"]) if ([choice[@"text"] isEqual:@"y"]) yes=choice;
    Require(yes != nil,@"Missing terminal approval choice");
    Call(host,@"answer",@{@"id":pid,@"fingerprint":row[@"fingerprint"],@"choice":yes});
    NSDictionary *done = WaitForRow(host,pid,@"complete",@"approval received",5);
    Call(host,@"read",@{@"id":pid,@"fingerprint":done[@"fingerprint"]});
    Require(Snapshot(host)[@"attention"][pid] == nil,@"Read receipt did not clear completed turn");
    Pass("answer and read");
    NSDictionary *attach = Call(host,@"attach",@{@"target":managed[@"target"]});
    Require([attach[@"sessionID"] isEqual:managed[@"sessionID"]] && [attach[@"binary"] isAbsolutePath],@"Invalid attach destination");
    [host disconnect];
    host = Connect(dest,helper);
    NSDictionary *reconnected = Snapshot(host);
    Require([Pane(reconnected,pid)[@"target"] isEqual:managed[@"target"]] && !reconnected[@"attention"][pid],@"Reconnect lost managed identity or read receipt");
    Pass("reconnect, stable card and remote attach metadata");
    Call(host,@"interrupt",@{@"target":managed[@"target"]});
    WaitForRow(host,pid,@"complete",@"interrupt received",5);
    Pass("Ctrl-C reached the live remote pane");
    End(host,managed);
    NSString *marker = [@"FauxRK-" stringByAppendingString:nonce];
    NSString *prompt = [NSString stringWithFormat:@"For a UI smoke test, reply with only this exact text: %@. Do not use tools or change files.",marker];
    NSString *spawnID = Call(host,@"spawn",@{@"preset":@"Luna Medium",@"directory":@"~/Code/regina/",@"prompt":prompt});
    NSDictionary *spawn = Pane(Snapshot(host),spawnID);
    Require([spawn[@"managed"] boolValue] && [spawn[@"preset"] isEqual:@"Luna Medium"] && [spawn[@"path"] hasSuffix:@"/Code/regina"],@"Spawn did not create requested preset/project");
    Pass("real Luna Medium spawn in allowed remote directory");
    WaitForRow(host,spawnID,@"complete",marker,90);
    Pass("real agent completed the remote first turn");
    End(host,spawn);
    Require([originalTargets isSubsetOfSet:OtherTargets(Snapshot(host),pid)],@"A pre-existing pane changed identity during verification");
    [host disconnect];
    Pass("ended both fixtures; all original pane identities remain");
}

int main(int argc,const char **argv) {
    @autoreleasepool {
        if (argc!=5) return 2;
        @try { Exercise(@(argv[1]),@(argv[2]),@(argv[3]),@(argv[4])); }
        @catch(NSException *error) { fprintf(stderr,"FAIL %s\n",error.reason.UTF8String); return 1; }
    }
    return 0;
}
