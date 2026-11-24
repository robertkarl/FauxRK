#import "RKVoice.h"

static void Check(BOOL ok, NSString *message) {
    if (ok) return;
    NSLog(@"Voice regression: %@", message);
    exit(1);
}

@interface RKVoice (Capture)
- (void)startRecording;
- (void)startWhenMicrophoneIsAuthorized:(NSUInteger)generation;
- (BOOL)recordToURL:(NSURL *)url settings:(NSDictionary *)settings error:(NSError **)error;
@end

// Substitute only microphone input. The recorder lifecycle, local CLI launch,
// transcript parsing, and AppKit editor are exercised through RKVoice's public API.
@interface FixtureVoice : RKVoice
@property NSURL *source;
@property NSUInteger recordings;
@end
@implementation FixtureVoice
- (void)startWhenMicrophoneIsAuthorized:(NSUInteger)generation { [self startRecording]; }
- (BOOL)recordToURL:(NSURL *)url settings:(NSDictionary *)settings error:(NSError **)error {
    self.recordings++;
    return [NSFileManager.defaultManager copyItemAtURL:self.source toURL:url error:error];
}
@end

@interface Form : NSObject <NSTextViewDelegate>
@property NSWindow *window;
@property NSTextView *prompt, *other;
@property NSMutableArray<NSString *> *messages;
@property FixtureVoice *voice;
@property NSUInteger submits;
@end

@implementation Form
- (instancetype)initWithWAV:(NSString *)path {
    if (!(self = [super init])) return nil;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _prompt = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 80, 300, 80)];
    _prompt.delegate = self;
    _other = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 80)];
    [_window.contentView addSubview:_prompt];
    [_window.contentView addSubview:_other];
    [_window makeKeyAndOrderFront:nil];
    _messages = [NSMutableArray array];
    __weak Form *weak = self;
    _voice = [[FixtureVoice alloc] initWithStatus:^(NSString *message) {
        [weak.messages addObject:message];
    }];
    _voice.source = [NSURL fileURLWithPath:path];
    return self;
}

- (BOOL)textView:(NSTextView *)view doCommandBySelector:(SEL)command {
    if (command != @selector(insertNewline:)) return NO;
    self.submits++;
    return YES;
}

- (void)beginClip {
    Check([self.window makeFirstResponder:self.prompt], @"Focus original prompt");
    [self.voice beginWithEditor:self.prompt];
    Check([self.messages.lastObject hasPrefix:@"Listening"], self.messages.lastObject ?: @"No recording began");
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.34]];
}

- (void)releaseKey {
    [self.voice finish];
    Check([self.messages.lastObject hasPrefix:@"Transcribing"], @"Releasing key starts transcription");
}

- (void)await:(NSString *)expected {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:65];
    while ([self.messages.lastObject hasPrefix:@"Transcribing"] && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    Check([self.messages.lastObject hasPrefix:expected], [NSString stringWithFormat:@"Expected %@; got %@", expected, self.messages.lastObject]);
}
@end

static void VerifyTranscript(Form *form) {
    form.prompt.string = @"Project stale";
    form.prompt.selectedRange = NSMakeRange(8, 5);
    [form beginClip];
    [form releaseKey];
    [form.window makeFirstResponder:form.other];
    [form await:@"Draft inserted"];
    Check([form.prompt.string hasPrefix:@"Project "] && [form.prompt.string localizedCaseInsensitiveContainsString:@"green building"], form.prompt.string);
    Check(![form.prompt.string containsString:@"stale"], @"Replace selected words");
    Check(!form.other.string.length && form.window.firstResponder == form.other, @"Do not redirect transcript or steal focus");
    Check(!form.submits && form.prompt.isEditable, @"Transcript remains an editable, unsent draft");
    NSLog(@"Recognized draft: %@", form.prompt.string);
}

static void VerifyFocusAndCancellation(Form *form) {
    NSUInteger clips = form.voice.recordings;
    [form.window makeFirstResponder:form.other];
    [form.voice beginWithEditor:form.prompt];
    Check(form.voice.recordings == clips, @"Unfocused field must never begin recording");
    NSString *original = form.prompt.string;
    [form beginClip];
    [form releaseKey];
    form.prompt.hidden = YES;
    [form await:@"Transcription discarded"];
    Check([form.prompt.string isEqual:original], @"Do not insert into a collapsed prompt");
    form.prompt.hidden = NO;
    [form beginClip];
    [form releaseKey];
    [form.voice cancel];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    Check([form.messages.lastObject hasPrefix:@"Dictation cancelled"] && [form.prompt.string isEqual:original], @"Ignore stale callbacks after cancellation");
    Check(!form.submits, @"Cancel does not submit");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc >= 2, @"Missing WAV fixture");
        [NSApplication sharedApplication];
        Form *form = [[Form alloc] initWithWAV:[NSString stringWithUTF8String:argv[1]]];
        VerifyTranscript(form);
        if (argc == 2) VerifyFocusAndCancellation(form);
        [form.window orderOut:nil];
        puts("voice fixtures passed");
    }
}
