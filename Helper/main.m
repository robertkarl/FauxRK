#import <Foundation/Foundation.h>
#import <errno.h>
#import <signal.h>
#import <stdatomic.h>
#import <unistd.h>
#import "RKHost.h"

static const NSUInteger RKMaxRequest = 4 * 1024 * 1024;
static atomic_bool RKOutputClosed;

// stdout is exclusively the JSONL reply stream. Preview jobs may finish in
// parallel, so serialize the entire frame including its trailing newline.
static void reply(id requestID, id value, NSString *message) {
    id identifier = requestID ?: NSNull.null;
    NSDictionary *envelope = value ? @{@"id":identifier, @"value":value} :
        @{@"id":identifier, @"error":message ?: @"The host could not complete the operation."};
    NSData *json = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:NULL];
    if (!json) json = [NSJSONSerialization dataWithJSONObject:
        @{@"id":identifier, @"error":@"Could not encode the RK response."} options:0 error:NULL];
    NSMutableData *frame = [json mutableCopy];
    [frame appendBytes:"\n" length:1];
    @synchronized (RKLocalHost.class) {
        if (atomic_load(&RKOutputClosed)) return;
        const unsigned char *p = frame.bytes;
        size_t left = frame.length;
        while (left) {
            ssize_t count = write(STDOUT_FILENO, p, left);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) {
                // A Preview can discover the disconnect while the main thread
                // is still submitting an answer. Let that operation finish.
                atomic_store(&RKOutputClosed,true);
                return;
            }
            p += count; left -= count;
        }
    }
}

static void serveFrame(NSData *frame, RKLocalHost *host, NSOperationQueue *previews) {
    id json = [NSJSONSerialization JSONObjectWithData:frame options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) {
        reply(nil,nil,@"Expected one JSON request object per line.");
        return;
    }
    NSDictionary *message = json;
    NSString *identifier = message[@"id"];
    if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length > 128) {
        reply(nil,nil,@"Missing or invalid RK request identifier.");
        return;
    }
    NSString *op = message[@"op"];
    NSDictionary *args = message[@"args"];
    if (message.count != 3 || ![op isKindOfClass:NSString.class] || ![args isKindOfClass:NSDictionary.class]) {
        reply(identifier,nil,@"An RK request requires id, op and args.");
        return;
    }
    void (^perform)(void) = ^{
        @autoreleasepool {
            NSError *error = nil;
            id result = [host request:op arguments:args error:&error];
            reply(identifier,result,error.localizedDescription);
        }
    };
    if ([op isEqual:@"preview"]) {
        if (previews.operationCount >= (NSUInteger)previews.maxConcurrentOperationCount) reply(identifier,nil,@"Pane previews are busy. Try again shortly.");
        else [previews addOperationWithBlock:perform];
    } else {
        // Inventory and all mutations run in wire order.
        perform();
    }
}

int main(int argc, const char *argv[]) {
    if (argc != 1) return 2;
    // Finish an accepted mutation if SSH disconnects during its execution.
    signal(SIGHUP, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
    @autoreleasepool {
        RKLocalHost *host = [[RKLocalHost alloc] initForSSHHelper];
        NSOperationQueue *previews = [NSOperationQueue new];
        previews.maxConcurrentOperationCount = 3;
        NSMutableData *line = [NSMutableData new];
        BOOL oversized = NO;
        unsigned char bytes[16384];
        while (!atomic_load(&RKOutputClosed)) {
            ssize_t n = read(STDIN_FILENO,bytes,sizeof bytes);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            const unsigned char *p = bytes, *end = bytes+n;
            while (p < end && !atomic_load(&RKOutputClosed)) {
                const unsigned char *newline = memchr(p, '\n', end-p);
                NSUInteger length = (NSUInteger)((newline ?: end)-p);
                if (line.length + length > RKMaxRequest) { oversized = YES; line.length = 0; }
                if (!oversized) [line appendBytes:p length:length];
                if (!newline) break;
                @autoreleasepool {
                    if (oversized) reply(nil,nil,@"The RK request exceeds the maximum frame size.");
                    else serveFrame(line,host,previews);
                }
                line.length = 0;
                oversized = NO;
                p = newline+1;
            }
        }
        // Incomplete lines are never executed. Work awaiting an explicit
        // response ends with the connection; existing managed agents live in tmux.
        [previews cancelAllOperations];
    }
    return 0;
}
