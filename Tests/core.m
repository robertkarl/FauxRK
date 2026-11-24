#import <Foundation/Foundation.h>
#import "../Sources/RKCore.h"

static void require(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr,"%s\n", message.UTF8String); exit(1); }
}
static NSDictionary *row(RKCore *core, NSString *pid) {
    NSError *error;
    NSArray *rows = [core panes:&error];
    require(rows != nil, error.localizedDescription ?: @"No inventory");
    for (NSDictionary *r in rows) if ([r[@"id"] isEqual:pid]) return r;
    return nil;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        require(argc >= 3, @"missing fixture IDs");
        NSString *mode = @(argv[1]), *pid = @(argv[2]);
        RKCore *core = [RKCore new];
        NSError *error;
        if ([mode isEqual:@"spawn"]) {
            NSString *fixture = NSProcessInfo.processInfo.environment[@"RK_TEST_WORKSPACE"];
            NSString *newID = [core spawnPreset:@"Astra Medium" directory:fixture prompt:@"--hello\n$(touch BAD); #{pane_id} 'quote' 💬" error:&error];
            require(newID != nil,error.localizedDescription ?: @"failed to spawn");
            require([row(core,newID)[@"managed"] boolValue], @"new session unmarked");
            puts(newID.UTF8String);
            return 0;
        }
        NSDictionary *before = row(core,pid);
        require(before != nil, @"Missing fixture");
        if ([mode isEqual:@"unmanaged"]) {
            require(![core end:before[@"target"] error:&error],@"Ended an unmanaged pane");
            return 0;
        }
        if ([mode isEqual:@"end"]) {
            require([core end:before[@"target"] error:&error],error.localizedDescription ?: @"end failed");
            return 0;
        }
        if ([mode isEqual:@"siblings"]) {
            require(![core end:before[@"target"] error:&error], @"end allowed on session with siblings");
            return 0;
        }
        if ([mode isEqual:@"send"]) {
            require([core sendText:@"-- literal ' and ; $(touch BAD)\nnext line" toPane:before[@"target"] error:&error], error.localizedDescription ?: @"paste failed");
            return 0;
        }
        if ([mode isEqual:@"stale"]) {
            require(![core interrupt:[before[@"target"] stringByAppendingString:@"x"] error:&error],@"stale intent accepted");
            return 0;
        }
        if ([mode isEqual:@"shell"]) {
            require(![core sendText:@"touch BAD" toPane:before[@"target"] error:&error],@"shell prompt received arbitrary text");
            return 0;
        }
        require(![before[@"managed"] boolValue],@"unexpected automatic capture");
        require([core capture:before[@"target"] error:&error],error.localizedDescription ?: @"capture failed");
        NSDictionary *after = row(core,pid);
        require([after[@"managed"] boolValue] && [after[@"rkID"] length],@"capture marker missing");
        require([before[@"panePID"] isEqual:after[@"panePID"]],@"Capture replaced the live process");
        require(![before[@"sessionID"] isEqual:after[@"sessionID"]],@"capture left pane in old session");
        require(![core interrupt:before[@"target"] error:&error],@"pre-capture selection still valid");
        puts([after[@"sessionID"] UTF8String]);
    }
}
