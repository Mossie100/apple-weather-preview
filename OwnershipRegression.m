#import <Foundation/Foundation.h>
#import "NativeSceneInitializers.h"
#import "NativeProbe.h"

@interface MockWorld : NSObject
@property(nonatomic,strong) id payload;
+ (id)worldWithURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error;
- (BOOL)loadCoreEntityManagerFromURL:(NSURL *)url options:(NSDictionary *)options infoOut:(NSMutableDictionary *)info error:(NSError **)error;
@end
@implementation MockWorld
+ (id)worldWithURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error{
    if([url.lastPathComponent isEqualToString:@"fail"]){if(error)*error=CGProbeError(42,@"Expected loader failure");return nil;}
    return [self new];
}
- (BOOL)loadCoreEntityManagerFromURL:(NSURL *)url options:(NSDictionary *)options infoOut:(NSMutableDictionary *)info error:(NSError **)error{info[@"checked"]=@YES;return YES;}
@end

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
        NSError *error=nil;
        NSDictionary *result=CGInvoke(MockWorld.class,@"worldWithURL:options:error:",@[[NSURL fileURLWithPath:@"/good"],@{},NSNull.null],&error);
        if(error || ![result[@"value"]isKindOfClass:MockWorld.class])return 4;
        MockWorld *world=result[@"value"];
        if(!CGSetObject(world,@"setPayload:",@"retained") || ![world.payload isEqual:@"retained"])return 5;
        result=CGInvoke(MockWorld.class,@"worldWithURL:options:error:",@[[NSURL fileURLWithPath:@"/fail"],@{},NSNull.null],&error);
        if(error.code!=42 || result[@"value"]!=NSNull.null)return 6;
        NSMutableDictionary *info=[NSMutableDictionary dictionary];
        result=CGInvoke(world,@"loadCoreEntityManagerFromURL:options:infoOut:error:",@[[NSURL fileURLWithPath:@"/good"],@{},info,NSNull.null],&error);
        if(error || ![result[@"value"]boolValue] || ![info[@"checked"]boolValue])return 7;
        if(CGInvoke(world,@"init",@[],&error) || error.code!=1)return 8;
        if(CGInvoke(world,@"missingSelector",@[],&error) || error.code!=2)return 9;
        if(CGInvoke(world,@"loadCoreEntityManagerFromURL:options:infoOut:error:",@[@1],&error) || error.code!=2)return 10;
        puts("PASS: 2,000 failing initializers disposed their receivers exactly once.");
        puts("PASS: object results, NSError out-parameters, BOOL results, mutable info, setter lifetime, ownership and signature guards.");
    }
    return 0;
}
