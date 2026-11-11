#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#include <stdlib.h>
#import "NativeProbe.h"

static NSString *Describe(id value){NSString *s=[value description]?:@"nil";return s.length>6000?[[s substringToIndex:6000]stringByAppendingString:@" [truncated]"]:s;}
static NSString *ImageHash(NSData *data){
    if(!data)return @"unavailable";unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *s=[NSMutableString string];for(NSUInteger i=0;i<sizeof(bytes);i++)[s appendFormat:@"%02x",bytes[i]];return s;
}
static NSDictionary *SamplePixels(UIImage *image){
    if(!image.CGImage)return nil;
    unsigned char pixels[32*32*4]={0};CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,32,32,8,32*4,colors,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(colors);
    if(!context)return nil;CGContextDrawImage(context,CGRectMake(0,0,32,32),image.CGImage);CGContextRelease(context);
    NSUInteger low=255,high=0;
    for(NSUInteger i=0;i<sizeof(pixels);i+=4)for(NSUInteger channel=0;channel<3;channel++){low=MIN(low,pixels[i+channel]);high=MAX(high,pixels[i+channel]);}
    return @{@"hash":ImageHash([NSData dataWithBytes:pixels length:sizeof(pixels)]),@"minimum":@(low),@"maximum":@(high),@"uniform":@(high-low<=2)};
}
static NSString *LoaderKey(const char *name){
    void *address=dlsym(RTLD_DEFAULT,name);if(!address)return nil;
    // Exact exported NSString constants, verified in the extracted binary.
    __unsafe_unretained id key=*(__unsafe_unretained id *)address;
    return [key isKindOfClass:NSString.class]?key:nil;
}
@interface PreviewController:UIViewController
@property(nonatomic,strong) UIView *stage;
@property(nonatomic,strong) UITextView *reportView;
@property(nonatomic,strong) UIButton *runButton;
@property(nonatomic,strong) NSMutableArray *messages;
@property(nonatomic,strong) NSMutableDictionary *state;
@property(nonatomic,strong) NSArray *cases;
@property(nonatomic,strong) UIView *nativeView;
@property(nonatomic,strong) id nativeWorld;
@property(nonatomic,strong) NSMutableArray *observers;
@property(nonatomic,strong) NSURL *stateURL;
@property(nonatomic,strong) NSURL *reportURL;
@property(nonatomic,strong) NSURL *snapshotFolder;
@property(nonatomic,assign) Class worldClass;
@property(nonatomic,assign) Class viewClass;
@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL stopRequested;
@property(nonatomic,assign) NSUInteger index;
@property(nonatomic,assign) NSUInteger snapshotsSaved;
@property(nonatomic,strong) dispatch_queue_t probeQueue;
@property(nonatomic,copy) dispatch_block_t pendingActive;
@end
@implementation PreviewController
- (void)save{
    self.state[@"messages"]=self.messages;
    NSData *json=[NSJSONSerialization dataWithJSONObject:self.state options:NSJSONWritingPrettyPrinted error:nil];
    if(json)[json writeToURL:self.stateURL options:NSDataWritingAtomic error:nil];
    [[self.messages componentsJoinedByString:@"\n\n"]writeToURL:self.reportURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
- (void)log:(NSString *)text{[self.messages addObject:text];self.reportView.text=[self.messages componentsJoinedByString:@"\n\n"];[self save];NSLog(@"WeatherProbe: %@",text);}
- (void)viewDidLoad{
    [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;
    NSURL *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    self.stateURL=[documents URLByAppendingPathComponent:@"preview4-state.json"];self.reportURL=[documents URLByAppendingPathComponent:@"Apple-Weather-Preview4-report.txt"];
    self.snapshotFolder=[documents URLByAppendingPathComponent:@"preview4-snapshots" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.snapshotFolder withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data=[NSData dataWithContentsOfURL:self.stateURL];id saved=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;
    self.state=[saved isKindOfClass:NSDictionary.class]?[saved mutableCopy]:[NSMutableDictionary dictionary];
    self.messages=[self.state[@"messages"]isKindOfClass:NSArray.class]?[self.state[@"messages"]mutableCopy]:[NSMutableArray array];
    self.snapshotsSaved=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.snapshotFolder includingPropertiesForKeys:nil options:0 error:nil].count;
    self.probeQueue=dispatch_queue_create("com.calibratedgolf.weatherprobe",DISPATCH_QUEUE_SERIAL);
    self.stage=[UIView new];self.stage.backgroundColor=UIColor.blackColor;
    self.reportView=[UITextView new];self.reportView.editable=NO;self.reportView.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    UILabel *title=[UILabel new];title.text=@"Apple Weather - comprehensive check";title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];title.adjustsFontSizeToFitWidth=YES;
    UILabel *subtitle=[UILabel new];subtitle.text=@"One run, saved results. Exact weather presets remain unverified.";subtitle.numberOfLines=2;subtitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.runButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.runButton setTitle:@"Run all checks" forState:UIControlStateNormal];[self.runButton addTarget:self action:@selector(runChecks) forControlEvents:UIControlEventTouchUpInside];
    UIButton *copy=[UIButton buttonWithType:UIButtonTypeSystem];[copy setTitle:@"Copy report" forState:UIControlStateNormal];[copy addTarget:self action:@selector(copyReport) forControlEvents:UIControlEventTouchUpInside];
    UIButton *share=[UIButton buttonWithType:UIButtonTypeSystem];[share setTitle:@"Share report" forState:UIControlStateNormal];[share addTarget:self action:@selector(shareReport) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons=[[UIStackView alloc]initWithArrangedSubviews:@[self.runButton,copy,share]];buttons.distribution=UIStackViewDistributionFillEqually;
    UIStackView *layout=[[UIStackView alloc]initWithArrangedSubviews:@[title,subtitle,self.stage,buttons,self.reportView]];layout.axis=UILayoutConstraintAxisVertical;layout.spacing=8;layout.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:layout];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[layout.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],[layout.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[layout.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[layout.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[self.stage.heightAnchor constraintGreaterThanOrEqualToConstant:120],[self.reportView.heightAnchor constraintEqualToAnchor:layout.heightAnchor multiplier:0.35],[buttons.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    self.reportView.text=[self.messages componentsJoinedByString:@"\n\n"];
    if([self.state[@"inProgress"]boolValue]){
        [self log:[NSString stringWithFormat:@"Previous run was interrupted during %@. That attempt will be skipped on resume; its checkpoint is preserved.",self.state[@"checkpoint"]?:@"unknown"]];
        self.state[@"nextIndex"]=@([self.state[@"currentIndex"]unsignedIntegerValue]+1);self.state[@"inProgress"]=@NO;[self save];[self.runButton setTitle:@"Resume checks" forState:UIControlStateNormal];
    }
    self.observers=[NSMutableArray array];__weak typeof(self) weakSelf=self;
    for(NSNotificationName name in @[UIApplicationWillResignActiveNotification,UIApplicationDidEnterBackgroundNotification,UIApplicationDidBecomeActiveNotification,UIAccessibilityReduceMotionStatusDidChangeNotification]){
        id token=[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){BOOL active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive && ![note.name isEqualToString:UIApplicationWillResignActiveNotification] && ![note.name isEqualToString:UIApplicationDidEnterBackgroundNotification];[weakSelf playback:active];if(active && weakSelf.pendingActive){dispatch_block_t action=weakSelf.pendingActive;weakSelf.pendingActive=nil;action();}}];[self.observers addObject:token];
    }
}
- (void)dealloc{for(id token in self.observers)[NSNotificationCenter.defaultCenter removeObserver:token];}
- (void)copyReport{[self save];UIPasteboard.generalPasteboard.string=[self.messages componentsJoinedByString:@"\n\n"];}
- (void)shareReport{
    [self save];NSMutableArray *items=[NSMutableArray arrayWithObject:self.reportURL];
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.snapshotFolder includingPropertiesForKeys:nil options:0 error:nil];[items addObjectsFromArray:files?:@[]];
    UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];share.popoverPresentationController.sourceView=self.runButton;[self presentViewController:share animated:YES completion:nil];
}
- (void)playback:(BOOL)active{
    @try{CGSetBool(self.nativeView,@"setRendersContinuously:",active&&!UIAccessibilityIsReduceMotionEnabled());}
    @catch(NSException *exception){[self log:[@"Playback exception: " stringByAppendingString:Describe(exception)]];}
}
- (void)whenActive:(dispatch_block_t)action{
    if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)action();
    else{self.pendingActive=action;[self log:@"Paused until the app returns to foreground."];}
}
- (void)inventory:(NSURL *)url{
    NSNumber *size=nil,*readable=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];[url getResourceValue:&readable forKey:NSURLIsReadableKey error:nil];
    [self log:[NSString stringWithFormat:@"FILE %@ | exists=%d readable=%@ bytes=%@",url.path,[NSFileManager.defaultManager fileExistsAtPath:url.path],readable?:@NO,size?:@0]];
}
- (BOOL)prepareCases{
    struct utsname hardware;uname(&hardware);NSBundle *app=NSBundle.mainBundle;
    [self log:[NSString stringWithFormat:@"Preview %@ | iOS %@ | hardware %s | source %@",[app objectForInfoDictionaryKey:@"CFBundleVersion"],UIDevice.currentDevice.systemVersion,hardware.machine,[app objectForInfoDictionaryKey:@"CGPreviewSourceSHA256"]?:@"unknown"]];
    [self log:@"iPhone-only. No network or golf app changes. A loaded world or changing snapshot is not proof of an exact Apple weather-condition match."];
    for(NSString *name in @[@"VFXBase",@"VFXAssets",@"VFX",@"WeatherUI"]){
        NSString *path=[NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@",name,name];[self log:[@"FRAMEWORK " stringByAppendingString:name]];
        if(!dlopen(path.UTF8String,RTLD_NOW|RTLD_GLOBAL)){const char *why=dlerror();[self log:[NSString stringWithFormat:@"FRAMEWORK FAILED: %s",why?:"unknown"]];return NO;}
    }
    self.worldClass=NSClassFromString(@"VFXWorld");self.viewClass=NSClassFromString(@"VFXView");
    if(!self.worldClass || ![self.viewClass isSubclassOfClass:UIView.class]){[self log:@"Required world/view classes unavailable."];return NO;}
    for(NSString *method in @[@"worldWithURL:options:error:",@"worldWithData:options:error:"]){
        NSMethodSignature *sig=[self.worldClass methodSignatureForSelector:NSSelectorFromString(method)];
        [self log:[NSString stringWithFormat:@"API %@ | return=%s args=%lu",method,sig?sig.methodReturnType:"missing",(unsigned long)(sig?sig.numberOfArguments:0)]];
    }
    NSArray *capabilities=@[
        @[@"VFXWorld",@"loadCoreEntityManagerFromURL:options:infoOut:error:"],
        @[@"VFXWorld",@"initializeCoreEntityManagerWithInfo:error:"],
        @[@"VFXWorldLoader",@"loadWorldFromURL:options:statusHandler:error:"],
        @[@"VFXView",@"setWorld:"],@[@"VFXView",@"snapshot"],@[@"VFXView",@"statistics"]];
    for(NSArray *entry in capabilities){
        Class cls=NSClassFromString(entry[0]);Method method=class_getInstanceMethod(cls,NSSelectorFromString(entry[1]));
        [self log:[NSString stringWithFormat:@"INSTANCE ABI %@ %@ = %s",entry[0],entry[1],method?method_getTypeEncoding(method):"unavailable"]];
    }
    for(NSString *name in @[@"WeatherUI.WeatherConditionConfigurationManager",@"WeatherUI.WeatherConditionBackgroundManager",@"WeatherUI.WeatherConditionBackgroundModelFactory"]){
        Class cls=NSClassFromString(name);NSMutableArray *methods=[NSMutableArray array];unsigned int count=0;Method *list=cls?class_copyMethodList(cls,&count):NULL;
        for(unsigned int i=0;i<MIN(count,30u);i++)[methods addObject:NSStringFromSelector(method_getName(list[i]))];free(list);
        [self log:[NSString stringWithFormat:@"PRESET FACTORY %@ available=%d exposedMethods=%@",name,cls!=Nil,methods]];
    }
    NSURL *framework=[NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks/WeatherUI.framework" isDirectory:YES];
    NSBundle *bundle=[NSBundle bundleWithURL:framework];[self log:[NSString stringWithFormat:@"WeatherUI build %@",[bundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"unknown"]];
    NSURL *vfx=[framework URLByAppendingPathComponent:@"VFX" isDirectory:YES];NSURL *metal=[bundle URLForResource:@"default" withExtension:@"metallib"];
    if(metal)[self inventory:metal];[self inventory:[framework URLByAppendingPathComponent:@"ForegroundEffectShaders.metallib"]];
    NSString *metalKey=LoaderKey("VFXWorldLoaderOptionMetalLibraryURL"),*assetKey=LoaderKey("VFXWorldLoaderAssetDirectoryURLsKey");
    [self log:[NSString stringWithFormat:@"EXPORTED OPTIONS metal=%@ assets=%@",metalKey?:@"unavailable",assetKey?:@"unavailable"]];
    NSMutableArray *cases=[NSMutableArray array];
    for(NSString *kind in @[@"Background",@"Collision"]){
        NSURL *project=[vfx URLByAppendingPathComponent:[NSString stringWithFormat:@"WeatherV136_Default_%@.vfx",kind] isDirectory:YES];
        NSURL *binary=[project URLByAppendingPathComponent:@"scene.vfxbin"];[self inventory:project];[self inventory:binary];[self inventory:[project URLByAppendingPathComponent:@"info.json"]];
        BOOL wrapper=[NSFileManager.defaultManager fileExistsAtPath:[[project URLByAppendingPathComponent:@"world.plist"]path]];
        [self log:[NSString stringWithFormat:@"%@ world.plist exists=%d. Folder-only load %@.",kind,wrapper,wrapper?@"available":@"skipped: missing wrapper, already observed failure"]];
        if(![NSFileManager.defaultManager isReadableFileAtPath:binary.path])continue;
        NSError *readError=nil;NSFileHandle *file=[NSFileHandle fileHandleForReadingFromURL:binary error:&readError];NSData *header=[file readDataUpToLength:8 error:&readError];[file closeAndReturnError:nil];
        [self log:[NSString stringWithFormat:@"%@ binary magic: %@ | readError=%@",kind,header?([[NSString alloc]initWithData:header encoding:NSASCIIStringEncoding]?:Describe(header)):@"unavailable",readError.localizedDescription?:@"none"]];
        NSMutableDictionary *options=[NSMutableDictionary dictionary];if(metalKey&&metal)options[metalKey]=metal;if(assetKey)options[assetKey]=@[vfx,project,framework];
        for(NSString *route in @[@"url-default",@"url-resolved",@"data-resolved",@"core-file",@"core-project",@"loader-file"]){
            [cases addObject:@{@"name":[NSString stringWithFormat:@"%@/%@",kind,route],@"kind":kind,@"route":route,@"file":binary,@"project":project,@"options":[options copy]}];
        }
    }
    self.cases=cases;[self log:[NSString stringWithFormat:@"Prepared %lu bounded loader checks, automatically run in this build.",(unsigned long)cases.count]];return cases.count>0;
}
- (void)runChecks{
    if(self.running){self.stopRequested=YES;[self log:@"Stop requested; the current native call must return before stopping."];return;}
    self.stopRequested=NO;
    if([self.state[@"complete"]boolValue]){[self.messages removeAllObjects];[self.state removeAllObjects];}
    if(![self prepareCases])return;
    self.index=[self.state[@"nextIndex"]unsignedIntegerValue];self.running=YES;[self.runButton setTitle:@"Stop" forState:UIControlStateNormal];[self nextCase];
}
- (void)nextCase{
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[self whenActive:^{[self nextCase];}];return;}
    [self playback:NO];
    if(self.stopRequested || self.index>=self.cases.count){
        self.running=NO;self.state[@"complete"]=@(!self.stopRequested);self.state[@"inProgress"]=@NO;
        [self.runButton setTitle:self.stopRequested?@"Resume checks":@"Run again" forState:UIControlStateNormal];
        [self playback:YES];[self log:self.stopRequested?@"STOPPED between attempts. Results saved.":@"COMPLETE. Checks finished. Exact condition presets remain UNVERIFIED. Copy or share this report."];return;
    }
    NSDictionary *test=self.cases[self.index];NSUInteger ticket=self.index;
    self.state[@"currentIndex"]=@(ticket);self.state[@"inProgress"]=@YES;self.state[@"checkpoint"]=test[@"name"];
    [self log:[NSString stringWithFormat:@"BEGIN %lu/%lu %@",(unsigned long)ticket+1,(unsigned long)self.cases.count,test[@"name"]]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.running && self.index==ticket && [self.state[@"inProgress"]boolValue])[self log:@"Native call still active. Report/UI remain available; no overlapping attempt will start."];});
    dispatch_async(self.probeQueue,^{@autoreleasepool{
        NSError *error=nil;id world=nil;NSString *route=test[@"route"];NSDictionary *result=nil,*options=test[@"options"];NSString *extra=@"";
        @try{
            if([route hasPrefix:@"url-"])result=CGInvoke(self.worldClass,@"worldWithURL:options:error:",@[test[@"file"],[route isEqualToString:@"url-default"]?@{}:options,NSNull.null],&error);
            else if([route isEqualToString:@"data-resolved"]){
                NSData *bytes=[NSData dataWithContentsOfURL:test[@"file"] options:NSDataReadingMappedIfSafe error:&error];
                if(bytes && bytes.length<=4*1024*1024)result=CGInvoke(self.worldClass,@"worldWithData:options:error:",@[bytes,options,NSNull.null],&error);
                else if(bytes)error=CGProbeError(21,@"Binary exceeds the 4 MB in-memory test limit.");
            }else if([route hasPrefix:@"core-"]){
                id candidate=[self.worldClass new];NSMutableDictionary *info=[NSMutableDictionary dictionary];
                result=CGInvoke(candidate,@"loadCoreEntityManagerFromURL:options:infoOut:error:",@[[route isEqualToString:@"core-file"]?test[@"file"]:test[@"project"],options,info,NSNull.null],&error);
                extra=[@" | info=" stringByAppendingString:Describe(info)];
                if(result && ([(NSString *)result[@"type"]isEqualToString:@"B"] || [(NSString *)result[@"type"]isEqualToString:@"c"]) && [result[@"value"]boolValue] && !error)world=candidate;
            }else if([route isEqualToString:@"loader-file"]){
                Class loaderClass=NSClassFromString(@"VFXWorldLoader");NSDictionary *factory=CGInvoke(loaderClass,@"loader",@[],&error);id loader=factory[@"value"];
                if(loader && loader!=NSNull.null)result=CGInvoke(loader,@"loadWorldFromURL:options:statusHandler:error:",@[test[@"file"],options,NSNull.null,NSNull.null],&error);
            }
            if(!world && [result[@"value"]isKindOfClass:self.worldClass])world=result[@"value"];
        }@catch(NSException *exception){error=CGProbeError(20,Describe(exception));}
        NSString *detail=error?[NSString stringWithFormat:@"%@ code=%ld %@ | userInfo=%@",error.domain,(long)error.code,error.localizedDescription,Describe(error.userInfo)]:@"none";
        dispatch_async(dispatch_get_main_queue(),^{
            [self log:[NSString stringWithFormat:@"RESULT %@ | world=%d return=%@ class=%@ value=%@ error=%@%@",test[@"name"],world!=nil,result[@"type"]?:@"unavailable",result?NSStringFromClass([result[@"value"]class]):@"none",world?@"VFXWorld":Describe(result[@"value"]),detail,extra]];
            if(world && [test[@"kind"]isEqualToString:@"Background"])[self whenActive:^{[self renderWorld:world test:test];}];
            else{if(world)[self log:@"Collision world loaded; this effect is not expected to render a standalone sky."];[self finishCase];}
        });
    }});
}
- (void)renderWorld:(id)world test:(NSDictionary *)test{
    self.state[@"checkpoint"]=[test[@"name"]stringByAppendingString:@"/renderer"];[self log:@"Attaching native world to Metal view."];
    @try{
        [self.nativeView removeFromSuperview];self.nativeView=nil;self.nativeWorld=nil;
        UIView *view=[[self.viewClass alloc]initWithFrame:self.stage.bounds];view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        if(!CGSetObject(view,@"setWorld:",world)){[self log:@"Renderer setter ABI unavailable."];[self finishCase];return;}
        self.nativeWorld=world;self.nativeView=view;[self.stage addSubview:view];[self playback:UIApplication.sharedApplication.applicationState==UIApplicationStateActive];
        NSError *ignored=nil;NSDictionary *camera=CGInvoke(world,@"defaultPointOfView",@[],&ignored);
        [self log:[NSString stringWithFormat:@"VIEW %.0fx%.0f layer=%@ camera=%@ ReduceMotion=%d",view.bounds.size.width,view.bounds.size.height,NSStringFromClass(view.layer.class),Describe(camera[@"value"]),UIAccessibilityIsReduceMotionEnabled()]];
        if([view.layer isKindOfClass:CAMetalLayer.class]){CAMetalLayer *metal=(CAMetalLayer *)view.layer;[self log:[NSString stringWithFormat:@"METAL drawable=%.0fx%.0f device=%@",metal.drawableSize.width,metal.drawableSize.height,metal.device.name?:@"none"]];}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{
            [self whenActive:^{
            NSString *first=[self snapshot:@"first"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [self whenActive:^{
                NSString *second=[self snapshot:@"second"];
                [self log:[NSString stringWithFormat:@"SNAPSHOTS first=%@ second=%@ changed=%d (not proof of exact appearance)",first,second,![first isEqualToString:second] && ![first isEqualToString:@"unavailable"] && ![second isEqualToString:@"unavailable"]]];
                NSError *ignored=nil;NSDictionary *stats=CGInvoke(self.nativeView,@"statistics",@[],&ignored);[self log:[@"RENDER STATS " stringByAppendingString:Describe(stats[@"value"])]];
                [self finishCase];
                }];
            });
            }];
        });
    }@catch(NSException *exception){[self log:[@"RENDER EXCEPTION " stringByAppendingString:Describe(exception)]];[self finishCase];}
}
- (NSString *)snapshot:(NSString *)phase{
    self.state[@"checkpoint"]=[NSString stringWithFormat:@"%@/snapshot-%@",self.cases[self.index][@"name"],phase];[self save];
    NSError *error=nil;NSDictionary *result=CGInvoke(self.nativeView,@"snapshot",@[],&error);id image=result[@"value"];
    if(![image isKindOfClass:UIImage.class]){[self log:[@"Snapshot unavailable: " stringByAppendingString:error.localizedDescription?:@"no image"]];return @"unavailable";}
    NSData *data=UIImagePNGRepresentation(image);if(!data || data.length>8*1024*1024){[self log:@"Snapshot absent or exceeds 8 MB limit."];return @"unavailable";}
    NSURL *path=[self.snapshotFolder URLByAppendingPathComponent:[NSString stringWithFormat:@"case-%lu-%@.png",(unsigned long)self.index+1,phase]];
    if([data writeToURL:path options:NSDataWritingAtomic error:nil]){
        NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.snapshotFolder includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil];
        files=[files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){NSDate *da=nil,*db=nil;[a getResourceValue:&da forKey:NSURLContentModificationDateKey error:nil];[b getResourceValue:&db forKey:NSURLContentModificationDateKey error:nil];return [(da?:NSDate.distantPast)compare:(db?:NSDate.distantPast)];}];
        while(files.count>4){[NSFileManager.defaultManager removeItemAtURL:files.firstObject error:nil];files=[files subarrayWithRange:NSMakeRange(1,files.count-1)];}
        self.snapshotsSaved=files.count;
    }
    NSDictionary *pixels=SamplePixels(image);[self log:[@"SAMPLED PIXELS " stringByAppendingString:Describe(pixels)]];
    return pixels[@"hash"]?:@"unavailable";
}
- (void)finishCase{
    self.state[@"inProgress"]=@NO;self.state[@"nextIndex"]=@(++self.index);[self save];dispatch_async(dispatch_get_main_queue(),^{[self nextCase];});
}
@end
@interface PreviewSceneDelegate:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation PreviewSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{
    if(![scene isKindOfClass:UIWindowScene.class])return;self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[PreviewController new];[self.window makeKeyAndVisible];
}
@end
@interface PreviewAppDelegate:UIResponder<UIApplicationDelegate>
@end
@implementation PreviewAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{
    UISceneConfiguration *config=[[UISceneConfiguration alloc]initWithName:@"Preview" sessionRole:session.role];config.delegateClass=PreviewSceneDelegate.class;return config;
}
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(PreviewAppDelegate.class));}}
