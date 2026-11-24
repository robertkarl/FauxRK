#import "RKHost.h"
#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>

NSString *const RKTransportErrorDomain = @"net.robertkarl.FauxRK.SSH";
static NSString *const RKRemoteActionErrorDomain = @"net.robertkarl.FauxRK.RemoteAction";
static const NSUInteger RKMaxRequest = 4 * 1024 * 1024;
static const NSUInteger RKMaxReply = 16 * 1024 * 1024;

static NSError *RKSSHError(NSString *description) {
    return [NSError errorWithDomain:RKTransportErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:description}];
}

// read(2) returns each available pipe fragment; Foundation's length-based
// file reads can wait for the full requested byte count on a live pipe.
static NSData *readChunk(NSFileHandle *handle) {
    uint8_t bytes[32768];
    ssize_t count;
    do { count = read(handle.fileDescriptor,bytes,sizeof(bytes)); } while (count < 0 && errno == EINTR);
    return count > 0 ? [NSData dataWithBytes:bytes length:(NSUInteger)count] : nil;
}

static NSString *shellQuoted(NSString *s) {
    return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static NSString *installCommand(NSData *binary) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(binary.bytes,(CC_LONG)binary.length,bytes);
    NSMutableString *hash = [NSMutableString string];
    for (size_t i=0;i<sizeof(bytes);i++) [hash appendFormat:@"%02x",bytes[i]];
    // The only interpolated fields are a hex digest and a decimal byte count.
    // Do not send the request stream until the bootstrap confirms exec readiness.
    NSString *script = [NSString stringWithFormat:
        @"set -eu\n"
        "umask 077\n"
        "if [ \"$(/usr/bin/id -u)\" = 0 ]; then echo 'FauxRK requires a regular SSH account.' >&2; exit 1; fi\n"
        "dir=\"$HOME/Library/Application Support/FauxRK/Helpers\"\n"
        "hash=%@\n"
        "/bin/mkdir -p \"$dir\"\n"
        "helper=\"$dir/FauxRKHost-$hash\"\n"
        "digest() { /usr/bin/shasum -a 256 < \"$1\" | /usr/bin/cut -d ' ' -f 1; }\n"
        "if [ ! -x \"$helper\" ] || [ \"$(digest \"$helper\")\" != \"$hash\" ]; then\n"
        "  tmp=$(/usr/bin/mktemp \"$dir/.install.XXXXXXXX\")\n"
        "  trap '/bin/rm -f \"$tmp\"' EXIT\n"
        "  trap 'exit 1' HUP INT TERM\n"
        "  echo FAUXRK_UPLOAD_1\n"
        "  /usr/bin/head -c %lu > \"$tmp\"\n"
        "  if [ \"$(digest \"$tmp\")\" != \"$hash\" ]; then echo 'FauxRK helper checksum mismatch.' >&2; exit 1; fi\n"
        "  /bin/chmod 700 \"$tmp\"\n"
        "  /bin/mv -f \"$tmp\" \"$helper\"\n"
        "  trap - EXIT HUP INT TERM\n"
        "fi\n"
        "echo FAUXRK_READY_1\n"
        "exec \"$helper\"\n",hash,(unsigned long)binary.length];
    return [@"exec /bin/sh -c " stringByAppendingString:shellQuoted(script)];
}

@interface RKPendingRequest : NSObject
@property id value;
@property NSError *error;
@property BOOL submitted;
@end
@implementation RKPendingRequest
@end

// A connection owns exactly one SSH process and one generation of request IDs.
// EOF or a timeout invalidates the generation and wakes every waiter.
@interface RKSSHChannel : NSObject
- (instancetype)initWithExecutable:(NSString *)executable destination:(NSString *)destination helper:(NSURL *)helper;
- (BOOL)reportedLoss;
- (void)close:(NSString *)reason;
- (id)request:(NSString *)op args:(NSDictionary *)args timeout:(NSTimeInterval)timeout error:(NSError **)error;
@end

@implementation RKSSHChannel {
    NSCondition *_state;
    NSTask *_task;
    NSFileHandle *_writer;
    NSData *_helper;
    NSString *_diagnostic;
    NSError *_failure;
    BOOL _ready, _uploadRequested, _lossReported;
    NSUInteger _scanned;
    NSMutableDictionary<NSString *, RKPendingRequest *> *_pending;
    dispatch_queue_t _outputQueue;
}

- (instancetype)initWithExecutable:(NSString *)executable destination:(NSString *)destination helper:(NSURL *)helper {
    if ((self = [super init])) {
        _state = [NSCondition new];
        _pending = [NSMutableDictionary dictionary];
        _outputQueue = dispatch_queue_create("net.robertkarl.FauxRK.ssh-writes", DISPATCH_QUEUE_SERIAL);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            [self run:executable destination:destination helper:helper];
        });
    }
    return self;
}

- (BOOL)reportedLoss {
    [_state lock];
    BOOL reported = _failure && _lossReported;
    [_state unlock];
    return reported;
}

- (void)close:(NSString *)reason {
    [_state lock];
    if (_failure) { [_state unlock]; return; }
    _failure = RKSSHError(reason);
    NSTask *task = _task;
    [_state broadcast];
    [_state unlock];
    if (task.running) [task terminate];
}

- (void)run:(NSString *)executable destination:(NSString *)destination helper:(NSURL *)url {
    @autoreleasepool {
        NSError *error;
        NSData *binary = url.isFileURL ? [NSData dataWithContentsOfURL:url options:0 error:&error] : nil;
        if (!binary.length || binary.length > 64 * 1024 * 1024) {
            [self close:@"The bundled FauxRK helper is missing or unreadable."]; return;
        }
        NSCharacterSet *hostChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@:._-[]"];
        if (!destination.length || [destination hasPrefix:@"-"] || [destination rangeOfCharacterFromSet:hostChars.invertedSet].location != NSNotFound) {
            [self close:@"The SSH destination is invalid."]; return;
        }
        NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe], *diagnostics = [NSPipe pipe];
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:executable];
        task.arguments = @[@"-T",@"-o",@"BatchMode=yes",@"-o",@"StrictHostKeyChecking=yes",@"-o",@"ConnectTimeout=5",@"-o",@"ConnectionAttempts=1",
            @"-o",@"ServerAliveInterval=5",@"-o",@"ServerAliveCountMax=2",@"-o",@"ClearAllForwardings=yes",
            @"--",destination,installCommand(binary)];
        task.standardInput = input;
        task.standardOutput = output;
        task.standardError = diagnostics;
        // A dropped SSH process must return EPIPE, not signal the GUI process.
        fcntl(input.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1);
        [_state lock];
        if (_failure) { [_state unlock]; return; }
        BOOL launched = [task launchAndReturnError:&error];
        if (launched) {
            _task = task; _writer = input.fileHandleForWriting; _helper = binary;
        }
        [_state unlock];
        if (!launched) { [self close:error.localizedDescription ?: @"Could not start SSH."]; return; }

        dispatch_group_t drain = dispatch_group_create();
        dispatch_group_async(drain,dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            NSMutableData *tail = [NSMutableData data];
            while (YES) {
                @autoreleasepool {
                    NSData *data = readChunk(diagnostics.fileHandleForReading);
                    if (!data.length) break;
                    [tail appendData:data];
                    if (tail.length > 2048) [tail replaceBytesInRange:NSMakeRange(0,tail.length-2048) withBytes:NULL length:0];
                }
            }
            NSString *s = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding];
            [_state lock]; self->_diagnostic = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; [_state unlock];
        });
        NSMutableData *buffer = [NSMutableData data];
        while (YES) {
            @autoreleasepool {
                NSData *chunk = readChunk(output.fileHandleForReading);
                if (!chunk.length) break;
                [buffer appendData:chunk];
                if (![self consumeLines:buffer]) break;
            }
        }
        dispatch_group_wait(drain,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC));
        [_state lock]; NSString *detail = _diagnostic; [_state unlock];
        [self close:detail.length ? detail : @"The SSH connection closed."];
    }
}

- (BOOL)consumeLines:(NSMutableData *)buffer {
    const unsigned char *bytes = buffer.bytes;
    NSUInteger start=0;
    for (NSUInteger i=_scanned; i<buffer.length; i++) {
        if (i-start > RKMaxReply) { [self close:@"The remote response exceeded the size limit."]; return NO; }
        if (bytes[i] != '\n') continue;
        NSData *line = [buffer subdataWithRange:NSMakeRange(start,i-start)];
        if (![self receive:line]) return NO;
        start = i+1;
    }
    if (start) [buffer replaceBytesInRange:NSMakeRange(0,start) withBytes:NULL length:0];
    _scanned = buffer.length;
    return YES;
}

- (BOOL)receive:(NSData *)line {
    [_state lock];
    if (_failure) { [_state unlock]; return NO; }
    if (!_ready) {
        NSString *text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
        if ([text isEqual:@"FAUXRK_READY_1"]) {
            _ready = YES; _helper = nil; [_state broadcast]; [_state unlock]; return YES;
        }
        if ([text isEqual:@"FAUXRK_UPLOAD_1"] && !_uploadRequested) {
            _uploadRequested = YES;
            NSData *binary = _helper;
            [_state unlock];
            [self enqueue:binary request:nil];
            return YES;
        }
        [_state unlock];
        [self close:@"SSH returned an unexpected helper startup message."]; return NO;
    }
    NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
    NSString *identifier = [reply isKindOfClass:NSDictionary.class] ? reply[@"id"] : nil;
    RKPendingRequest *pending = [identifier isKindOfClass:NSString.class] ? _pending[identifier] : nil;
    if (!pending || pending.value || pending.error || (!reply[@"value"] && ![reply[@"error"] isKindOfClass:NSString.class])) {
        [_state unlock]; [self close:@"Received an invalid response from the remote helper."]; return NO;
    }
    if ([reply[@"error"] isKindOfClass:NSString.class]) {
        pending.error = [NSError errorWithDomain:RKRemoteActionErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:reply[@"error"]}];
    } else {
        pending.value = reply[@"value"];
    }
    [_state broadcast];
    [_state unlock];
    return YES;
}

- (void)enqueue:(NSData *)payload request:(RKPendingRequest *)pending {
    dispatch_async(_outputQueue, ^{
        [self->_state lock];
        BOOL active = !self->_failure;
        NSFileHandle *writer = self->_writer;
        if (active) pending.submitted = YES;
        [self->_state unlock];
        if (!active) return;
        NSError *error;
        if (![writer writeData:payload error:&error]) [self close:error.localizedDescription ?: @"The SSH write failed."];
    });
}

- (id)request:(NSString *)op args:(NSDictionary *)args timeout:(NSTimeInterval)timeout error:(NSError **)error {
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *record = @{@"id":identifier,@"op":op,@"args":args ?: @{}};
    NSData *json = [NSJSONSerialization isValidJSONObject:record] ? [NSJSONSerialization dataWithJSONObject:record options:0 error:nil] : nil;
    if (!json || json.length > RKMaxRequest) {
        if (error) *error = [NSError errorWithDomain:RKRemoteActionErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"This request could not be encoded within the helper's size limit."}];
        return nil;
    }
    NSMutableData *wire = [json mutableCopy]; [wire appendBytes:"\n" length:1];
    [_state lock];
    BOOL snapshot = [op isEqual:@"snapshot"];
    if (snapshot) {
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:16];
        while (!_ready && !_failure && [_state waitUntilDate:limit]) {}
    }
    if (!_ready || _failure) {
        BOOL timedOut = snapshot && !_failure;
        if (_failure || timedOut) _lossReported = YES;
        NSError *cause = _failure ?: RKSSHError(timedOut ? @"Timed out connecting to the remote helper." : @"The remote host is disconnected.");
        [_state unlock];
        if (timedOut) [self close:cause.localizedDescription];
        if (error) *error = cause;
        return nil;
    }
    RKPendingRequest *pending = [RKPendingRequest new];
    _pending[identifier] = pending;
    [self enqueue:wire request:pending];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!pending.value && !pending.error && !_failure && [_state waitUntilDate:limit]) {}
    id value = pending.value;
    NSError *cause = pending.error ?: _failure;
    NSTask *timedOutTask = nil;
    if (!value && !cause) {
        // Invalidate before releasing the write lock. A queued message that
        // timed out before submission must never reach a later connection.
        cause = RKSSHError(@"Timed out waiting for the remote helper.");
        _failure = cause;
        timedOutTask = _task;
        [_state broadcast];
    }
    if (!value && !pending.error && _failure) _lossReported = YES;
    BOOL uncertain = !value && !pending.error && pending.submitted && !snapshot && ![op isEqual:@"preview"] && ![op isEqual:@"attach"] && ![op isEqual:@"read"];
    [_pending removeObjectForKey:identifier];
    [_state unlock];
    if (timedOutTask.running) [timedOutTask terminate];
    if (!value && error) {
        if (uncertain) {
            NSString *message = [NSString stringWithFormat:@"%@ Delivery is unconfirmed. Check the agent before resending.",cause.localizedDescription];
            *error = [NSError errorWithDomain:RKTransportErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:message}];
        } else { *error = cause; }
    }
    return value;
}
@end

@implementation RKRemoteHost {
    NSString *_destination;
    NSURL *_helperURL;
    RKSSHChannel *_channel;
    BOOL _retired;
}

- (instancetype)initWithDestination:(NSString *)destination helperURL:(NSURL *)helperURL {
    if ((self = [super init])) { _destination = destination.copy; _helperURL = helperURL.copy; }
    return self;
}

- (NSString *)sshExecutable { return @"/usr/bin/ssh"; }
- (NSTimeInterval)timeoutForOperation:(NSString *)operation { return [operation isEqual:@"preview"] ? 40 : 15; }

- (id)request:(NSString *)operation arguments:(NSDictionary *)arguments error:(NSError **)error {
    RKSSHChannel *channel;
    @synchronized (self) {
        if (!_retired && [operation isEqual:@"snapshot"] && (!_channel || _channel.reportedLoss)) {
            _channel = [[RKSSHChannel alloc] initWithExecutable:self.sshExecutable destination:_destination helper:_helperURL];
        }
        channel = _channel;
    }
    if (!channel) {
        if (error) *error = RKSSHError(@"The remote host is disconnected.");
        return nil;
    }
    return [channel request:operation args:arguments timeout:[self timeoutForOperation:operation] error:error];
}

- (void)disconnect {
    @synchronized (self) {
        _retired = YES;
        [_channel close:@"Disconnected from the selected host."];
        _channel = nil;
    }
}

- (void)dealloc { [self disconnect]; }
@end
