#import <Foundation/Foundation.h>
@interface RKPaneOrder : NSObject
- (NSArray<NSDictionary *> *)arrange:(NSArray<NSDictionary *> *)panes resort:(BOOL)resort;
@end
