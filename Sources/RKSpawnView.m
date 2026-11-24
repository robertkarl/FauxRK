#import "RKSpawnView.h"

@interface RKSpawnView ()
@property (nonatomic, weak) id<RKSidebarDelegate> delegate;
@property (nonatomic) NSPopUpButton *presets;
@property (nonatomic) NSPopUpButton *directories;
@property (nonatomic) NSString *chosenPath;
@property (nonatomic) RKPromptView *prompt;
@end

@implementation RKSpawnView
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate {
    if (!(self = [super initWithTint:RKTintViolet])) return nil;
    _delegate = delegate;
    _presets = [self pickerWithTitles:@[@"Astra Medium", @"Fable Medium", @"Opus", @"Luna Medium"] label:@"Agent preset"];
    _directories = [self pickerWithTitles:@[@"~/Code/regina/", @"~/homelab/", @"~/Code/unbiasedbob-private/", @"Choose another folder…"] label:@"Working directory"];
    _directories.target = self;
    _directories.action = @selector(selectDirectory:);
    _chosenPath = _directories.titleOfSelectedItem;
    RKAddFullWidth(self.body, RKLabel(@"Spawn agent", 15, NSFontWeightSemibold));
    [self addLabeledControl:_presets label:@"Preset"];
    [self addLabeledControl:_directories label:@"Directory"];
    _prompt = [[RKPromptView alloc] initWithHint:@"First prompt (optional)…"];
    [_prompt.editor setAccessibilityIdentifier:@"spawn-prompt"];
    RKAddFullWidth(self.body, _prompt);
    NSStackView *actions = RKRow(5);
    [actions addArrangedSubview:RKDetail(@"Hold F10 in a prompt to dictate")];
    [actions addArrangedSubview:RKSpring()];
    __weak typeof(self) weak = self;
    [actions addArrangedSubview:[RKActionButton title:@"Launch" symbol:@"arrow.up.right" help:@"Launch captured agent" tint:RKTintViolet action:^{
        [weak.delegate spawnPreset:weak.presets.titleOfSelectedItem directory:weak.chosenPath.stringByExpandingTildeInPath prompt:weak.prompt.editor.string.copy];
    }]];
    RKAddFullWidth(self.body, actions);
    return self;
}
- (NSPopUpButton *)pickerWithTitles:(NSArray<NSString *> *)titles label:(NSString *)label {
    NSPopUpButton *picker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [picker addItemsWithTitles:titles];
    [picker setAccessibilityLabel:label];
    picker.font = [NSFont systemFontOfSize:12];
    return picker;
}
- (void)addLabeledControl:(NSView *)control label:(NSString *)text {
    NSStackView *row = RKRow(8);
    NSTextField *label = RKDetail(text);
    [label.widthAnchor constraintEqualToConstant:54].active = YES;
    [row addArrangedSubview:label];
    [row addArrangedSubview:control];
    RKAddFullWidth(self.body, row);
}
- (void)selectDirectory:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem != sender.numberOfItems - 1) {
        self.chosenPath = sender.titleOfSelectedItem;
        return;
    }
    [sender selectItemWithTitle:self.chosenPath];
    NSOpenPanel *picker = [NSOpenPanel openPanel];
    picker.canChooseFiles = NO;
    picker.canChooseDirectories = YES;
    picker.allowsMultipleSelection = NO;
    picker.directoryURL = [NSURL fileURLWithPath:self.chosenPath.stringByExpandingTildeInPath];
    [picker beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        [self chooseProject:picker.URL.path];
    }];
}
- (void)chooseProject:(NSString *)directory {
    self.chosenPath = directory.stringByAbbreviatingWithTildeInPath;
    if (![self.directories itemWithTitle:self.chosenPath]) {
        [self.directories insertItemWithTitle:self.chosenPath atIndex:self.directories.numberOfItems - 1];
    }
    [self.directories selectItemWithTitle:self.chosenPath];
}
- (void)acknowledgePrompt:(NSString *)prompt {
    if (![self.prompt.editor.string isEqual:prompt]) return;
    self.prompt.editor.string = @"";
    [self.prompt.editor didChangeText];
    self.hidden = YES;
}
@end
