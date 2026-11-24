#import "RKVoice.h"
#import <AVFoundation/AVFoundation.h>

static const NSTimeInterval RKVoiceMinimumClip = 0.3;
static const NSTimeInterval RKVoiceMaximumClip = 120;
static const NSTimeInterval RKVoiceTranscriptionTimeout = 60;

typedef NS_ENUM(NSInteger, RKVoiceState) {
    RKVoiceIdle,
    RKVoiceAwaitingPermission,
    RKVoiceRecording,
    RKVoiceTranscribing,
};

@interface RKVoice ()
@property (nonatomic, copy) void (^status)(NSString *);
@property (nonatomic) RKVoiceState state;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, weak) NSTextView *editor;
@property (nonatomic, weak) NSWindow *editorWindow;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) NSURL *clipURL;
@property (nonatomic, strong) NSDate *recordingStarted;
@property (nonatomic, strong) NSTask *task;
@end

@implementation RKVoice

- (instancetype)initWithStatus:(void (^)(NSString *))status {
    if ((self = [super init])) {
        _status = [status copy];
    }
    return self;
}

- (void)dealloc {
    [_recorder stop];
    if (_task.isRunning) [_task terminate];
    if (_clipURL) [NSFileManager.defaultManager removeItemAtURL:_clipURL error:nil];
}

#pragma mark - Public

- (void)beginWithEditor:(NSTextView *)editor {
    if (self.state != RKVoiceIdle) return;  // key repeat, or a clip still transcribing
    if (!editor.isEditable || !editor.window || editor.window.firstResponder != editor || editor.hiddenOrHasHiddenAncestor) {
        [self report:@"Dictation needs a focused FauxRK prompt."];
        return;
    }
    if (![self toolsAreReady]) return;

    self.generation += 1;
    self.editor = editor;
    self.editorWindow = editor.window;
    [self startWhenMicrophoneIsAuthorized:self.generation];
}

- (void)finish {
    switch (self.state) {
        case RKVoiceAwaitingPermission:
            // Key-up arrived before the permission prompt was answered.
            // The prompt result must not start a recording nobody is holding.
            [self resetAttempt];
            return;
        case RKVoiceRecording:
            [self stopRecordingAndTranscribe];
            return;
        case RKVoiceIdle:
        case RKVoiceTranscribing:
            return;
    }
}

- (void)cancel {
    BOOL wasActive = self.state != RKVoiceIdle;
    if (self.task.isRunning) [self.task terminate];
    [self resetAttempt];
    if (wasActive) [self report:@"Dictation cancelled."];
}

#pragma mark - Microphone

- (void)startWhenMicrophoneIsAuthorized:(NSUInteger)generation {
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
        case AVAuthorizationStatusAuthorized:
            [self startRecording];
            return;
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            [self report:@"Microphone access is off. Enable FauxRK in System Settings > Privacy & Security > Microphone."];
            [self resetAttempt];
            return;
        case AVAuthorizationStatusNotDetermined:
            [self requestMicrophoneAccess:generation];
            return;
    }
}

- (void)requestMicrophoneAccess:(NSUInteger)generation {
    if (![NSBundle.mainBundle objectForInfoDictionaryKey:@"NSMicrophoneUsageDescription"]) {
        // Without the usage string macOS terminates the process on request.
        [self report:@"FauxRK cannot ask for the microphone: NSMicrophoneUsageDescription is missing from Info.plist."];
        [self resetAttempt];
        return;
    }
    self.state = RKVoiceAwaitingPermission;
    [self report:@"Waiting for microphone permission…"];
    __weak RKVoice *weakSelf = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf microphoneAccessGranted:granted generation:generation];
        });
    }];
}

- (void)microphoneAccessGranted:(BOOL)granted generation:(NSUInteger)generation {
    BOOL stillHeld = generation == self.generation && self.state == RKVoiceAwaitingPermission;
    if (!granted) {
        [self report:@"Microphone access denied. Dictation is unavailable."];
    } else if (!stillHeld) {
        [self report:@"Microphone access granted. Hold F10 again to dictate."];
    }
    if (!granted || !stillHeld) {
        if (generation == self.generation) [self resetAttempt];
        return;
    }
    if (![self editorIsStillUsable] || self.editorWindow.firstResponder != self.editor) {
        [self report:@"Dictation stopped because the original prompt lost focus."];
        [self resetAttempt];
        return;
    }
    [self startRecording];
}

#pragma mark - Recording

- (void)startRecording {
    NSString *name = [NSString stringWithFormat:@"rk-voice-%@.wav", NSUUID.UUID.UUIDString];
    self.clipURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];

    // whisper.cpp reads 16 kHz mono 16-bit PCM WAV natively; no conversion step.
    NSDictionary *format = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @16000,
        AVNumberOfChannelsKey: @1,
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsBigEndianKey: @NO,
    };
    NSError *error = nil;
    if (![self recordToURL:self.clipURL settings:format error:&error]) {
        [self report:[NSString stringWithFormat:@"Could not start recording: %@",
                      error.localizedDescription ?: @"no input device"]];
        [self resetAttempt];
        return;
    }
    self.recordingStarted = [NSDate date];
    self.state = RKVoiceRecording;
    [self report:@"Listening… release F10 to transcribe."];
}

- (BOOL)recordToURL:(NSURL *)url settings:(NSDictionary *)settings error:(NSError **)error {
    self.recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:error];
    return [self.recorder recordForDuration:RKVoiceMaximumClip];
}

- (void)stopRecordingAndTranscribe {
    // The recorder stops itself at the maximum length, so time the clip ourselves.
    NSTimeInterval duration = MIN(-self.recordingStarted.timeIntervalSinceNow, RKVoiceMaximumClip);
    [self.recorder stop];
    self.recorder = nil;
    if (duration < RKVoiceMinimumClip) {
        [self report:@"Too short to transcribe. Hold F10 while speaking."];
        [self resetAttempt];
        return;
    }
    self.state = RKVoiceTranscribing;
    [self report:@"Transcribing…"];
    [self transcribe:self.clipURL generation:self.generation];
}

#pragma mark - Transcription

- (void)transcribe:(NSURL *)clip generation:(NSUInteger)generation {
    NSString *outputBase = clip.path.stringByDeletingPathExtension;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:[RKVoice whisperCLIPath]];
    task.arguments = @[@"-m", [RKVoice modelPath], @"-f", clip.path,
                       @"-l", [RKVoice language], @"-nt", @"-np",
                       @"-otxt", @"-of", outputBase];
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;

    __weak RKVoice *weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        NSString *transcript = [RKVoice readTranscript:outputBase status:finished.terminationStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf transcriptionFinished:transcript generation:generation];
        });
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self report:[NSString stringWithFormat:@"whisper-cli failed to start: %@", error.localizedDescription]];
        [self resetAttempt];
        return;
    }
    self.task = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RKVoiceTranscriptionTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (task.isRunning) [task terminate];
    });
}

+ (NSString *)readTranscript:(NSString *)outputBase status:(int)status {
    NSString *path = [outputBase stringByAppendingPathExtension:@"txt"];
    NSString *text = status == 0 ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    return text;
}

- (void)transcriptionFinished:(NSString *)transcript generation:(NSUInteger)generation {
    if (generation != self.generation) return;  // cancelled or superseded
    NSString *draft = [RKVoice cleanTranscript:transcript];
    if (!transcript) {
        [self report:@"Transcription failed. Check whisper-cli and the model."];
    } else if (draft.length == 0) {
        [self report:@"No speech recognized."];
    } else if (![self editorIsStillUsable]) {
        [self report:@"Transcription discarded: the prompt it was meant for is gone."];
    } else if ([self insertDraft:draft]) {
        [self report:@"Draft inserted. Review before sending."];
    } else {
        [self report:@"The prompt could not accept the transcript."];
    }
    [self resetAttempt];
}

+ (NSString *)cleanTranscript:(NSString *)transcript {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [transcript componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0 || [RKVoice isNonSpeechMarker:trimmed]) continue;
        [lines addObject:trimmed];
    }
    return [lines componentsJoinedByString:@" "];
}

// Whisper labels silence and noise as "[BLANK_AUDIO]", "(music)", etc.
+ (BOOL)isNonSpeechMarker:(NSString *)line {
    return ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) ||
           ([line hasPrefix:@"("] && [line hasSuffix:@")"]);
}

#pragma mark - Editor

// The draft goes only to the editor that was focused at key-down, and only
// while it is still in the same window and editable. Focus moving elsewhere
// is fine; the editor being torn down or re-parented is not.
- (BOOL)editorIsStillUsable {
    NSTextView *editor = self.editor;
    return editor.isEditable && editor.window && editor.window == self.editorWindow && !editor.hiddenOrHasHiddenAncestor;
}

// Inserts at the current selection through the text system so undo works and
// delegates see the change. Never sends Return or calls any submit action.
- (BOOL)insertDraft:(NSString *)draft {
    NSTextView *editor = self.editor;
    NSRange range = editor.selectedRange;
    if (range.location > editor.string.length || range.length > editor.string.length - range.location) {
        range = NSMakeRange(editor.string.length, 0);
    }
    NSString *text = [self draft:draft spacedForRange:range inString:editor.string];
    if (![editor shouldChangeTextInRange:range replacementString:text]) return NO;
    [editor.textStorage replaceCharactersInRange:range withString:text];
    [editor didChangeText];
    [editor setSelectedRange:NSMakeRange(range.location + text.length, 0)];
    [editor scrollRangeToVisible:editor.selectedRange];
    return YES;
}

- (NSString *)draft:(NSString *)draft spacedForRange:(NSRange)range inString:(NSString *)string {
    if (range.location == 0) return draft;
    unichar before = [string characterAtIndex:range.location - 1];
    BOOL needsSpace = ![NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:before];
    return needsSpace ? [@" " stringByAppendingString:draft] : draft;
}

#pragma mark - State

- (void)resetAttempt {
    [self.recorder stop];
    self.recorder = nil;
    self.task = nil;
    if (self.clipURL) [NSFileManager.defaultManager removeItemAtURL:self.clipURL error:nil];
    self.clipURL = nil;
    self.recordingStarted = nil;
    self.editor = nil;
    self.editorWindow = nil;
    self.state = RKVoiceIdle;
    self.generation += 1;  // invalidates any callback still in flight
}

- (void)report:(NSString *)message {
    if (self.status) self.status(message);
}

#pragma mark - Local tools

- (BOOL)toolsAreReady {
    if (![RKVoice whisperCLIPath]) {
        [self report:@"whisper-cli not found. Run scripts/setup-voice.sh or set RK_WHISPER_CLI."];
        return NO;
    }
    if (![RKVoice modelPath]) {
        [self report:@"No Whisper model found. Run scripts/setup-voice.sh or set RK_WHISPER_MODEL."];
        return NO;
    }
    return YES;
}

+ (NSString *)whisperCLIPath {
    return [self firstExecutable:@[NSProcessInfo.processInfo.environment[@"RK_WHISPER_CLI"] ?: @"",
                                   @"/opt/homebrew/bin/whisper-cli",
                                   @"/usr/local/bin/whisper-cli"]];
}

// Preference order: explicit override, the model installed by setup-voice.sh,
// then well-known whisper.cpp cache locations. Faster models come first.
+ (NSString *)modelPath {
    NSString *home = NSHomeDirectory();
    NSString *rk = [home stringByAppendingPathComponent:@"Library/Application Support/RK/whisper"];
    NSString *cache = [home stringByAppendingPathComponent:@".cache/whisper-cpp"];
    NSString *models = [home stringByAppendingPathComponent:@"models/whisper"];
    NSArray<NSString *> *candidates = @[
        NSProcessInfo.processInfo.environment[@"RK_WHISPER_MODEL"] ?: @"",
        [rk stringByAppendingPathComponent:@"ggml-model.bin"],
        [cache stringByAppendingPathComponent:@"ggml-large-v3-turbo-q5_0.bin"],
        [cache stringByAppendingPathComponent:@"ggml-small.en.bin"],
        [cache stringByAppendingPathComponent:@"ggml-base.en.bin"],
        [models stringByAppendingPathComponent:@"ggml-large-v3-turbo-q5_0.bin"],
        [models stringByAppendingPathComponent:@"ggml-large-v3-turbo.bin"],
    ];
    for (NSString *path in candidates) {
        if (path.length && [NSFileManager.defaultManager isReadableFileAtPath:path]) return path;
    }
    return nil;
}

+ (NSString *)language {
    NSString *language = NSProcessInfo.processInfo.environment[@"RK_WHISPER_LANGUAGE"];
    return language.length ? language : @"en";
}

+ (NSString *)firstExecutable:(NSArray<NSString *> *)paths {
    for (NSString *path in paths) {
        if (path.length && [NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

@end
