#import <Foundation/Foundation.h>
#import "NativeSceneInitializers.h"

static NSUInteger destroyed=0;
@interface FailingScene : NSObject <CGNativeSceneInitializers>
@end
@implementation FailingScene
- (instancetype)initWithOptions:(id)options {self=[super init];self=nil;return nil;}
- (instancetype)initWithContentsOf:(NSURL *)url options:(id)options error:(NSError **)error {
    self=[super init];
    if(error)*error=[NSError errorWithDomain:@"OwnershipRegression" code:1 userInfo:nil];
    self=nil;return nil;
}
- (void)dealloc {destroyed++;}
@end
int main(void) {
    @autoreleasepool {
        for(NSUInteger i=0;i<1000;i++) {
            @autoreleasepool {
                if(CGCreateSceneWithOptions(FailingScene.class,nil)!=nil)return 1;
                NSError *error=nil;
                if(CGCreateSceneAtURL(FailingScene.class,[NSURL fileURLWithPath:@"/not-a-scene"],nil,&error)!=nil || !error)return 2;
            }
        }
        if(destroyed!=2000)return 3;
        puts("PASS: 2,000 failing initializers disposed their receivers exactly once.");
    }
    return 0;
}
