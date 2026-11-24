#import "RKApp.h"
int main(int argc, const char **argv) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        RKApp *delegate = [RKApp new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
        (void)delegate;
    }
    return 0;
}
