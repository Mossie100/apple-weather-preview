#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#include <string.h>
#import "NativeSceneInitializers.h"

static const char *Unqualified(const char *type) {
    while(*type && strchr("rnNoORV",*type))type++;
    return type;
}

// Calling initializers directly lets ARC consume the allocated receiver once.
// NSInvocation cannot communicate init-family ownership to the calling code.
static BOOL InitializerAvailable(Class cls, NSString *name, NSUInteger count, BOOL hasError) {
    NSMethodSignature *signature=[cls instanceMethodSignatureForSelector:NSSelectorFromString(name)];
    if(!signature || signature.numberOfArguments!=count+2 || Unqualified(signature.methodReturnType)[0]!='@')return NO;
    for(NSUInteger index=0;index<count;index++) {
        const char *type=Unqualified([signature getArgumentTypeAtIndex:index+2]);
        if(hasError && index==count-1) {if(type[0]!='^' || type[1]!='@')return NO;}
        else if(type[0]!='@')return NO;
    }
    return YES;
}

// Diagnostic only. Loads the installed Apple renderer, never the golf app.
static id SendObject(id target, NSString *name, NSArray *arguments, NSError **error) {
    // This helper is only for ordinary +0 object-returning methods.
    NSCAssert(![name hasPrefix:@"init"],@"Initializers must use typed ARC calls");
    SEL selector=NSSelectorFromString(name);
    NSMethodSignature *signature=[target methodSignatureForSelector:selector];
    if(!signature || signature.numberOfArguments!=arguments.count+2 || Unqualified(signature.methodReturnType)[0]!='@') {
        if(error)*error=[NSError errorWithDomain:@"WeatherPreview" code:1 userInfo:@{NSLocalizedDescriptionKey:[@"Unsupported native method: " stringByAppendingString:name]}];
        return nil;
    }
    NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
    call.target=target;call.selector=selector;
    NSError *__autoreleasing nativeError=nil;NSError *__autoreleasing *errorAddress=&nativeError;
    for(NSUInteger i=0;i<arguments.count;i++) {
        const char *type=Unqualified([signature getArgumentTypeAtIndex:i+2]);
        if(type[0]=='@') {id argument=arguments[i]==NSNull.null?nil:arguments[i];[call setArgument:&argument atIndex:i+2];}
        else if(type[0]=='^' && type[1]=='@') {[call setArgument:&errorAddress atIndex:i+2];}
        else {if(error)*error=[NSError errorWithDomain:@"WeatherPreview" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Native method argument layout differs"}];return nil;}
    }
    @try {
        [call retainArguments];[call invoke];
        __unsafe_unretained id result=nil;[call getReturnValue:&result];
        if(error)*error=nativeError;return result;
    } @catch(NSException *exception) {
        if(error)*error=[NSError errorWithDomain:@"WeatherPreview" code:3 userInfo:@{NSLocalizedDescriptionKey:exception.reason?:exception.name}];
        return nil;
    }
}
static BOOL SetObject(id target, NSString *name, id argument) {
    NSMethodSignature *signature=[target methodSignatureForSelector:NSSelectorFromString(name)];
    if(!signature || signature.numberOfArguments!=3 || Unqualified([signature getArgumentTypeAtIndex:2])[0]!='@')return NO;
    NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=target;call.selector=NSSelectorFromString(name);
    [call setArgument:&argument atIndex:2];[call retainArguments];[call invoke];return YES;
}
static void SetBool(id target, NSString *name, BOOL value) {
    NSMethodSignature *signature=[target methodSignatureForSelector:NSSelectorFromString(name)];
    if(!signature || signature.numberOfArguments!=3)return;
    char type=Unqualified([signature getArgumentTypeAtIndex:2])[0];if(type!='B' && type!='c')return;
    NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=target;call.selector=NSSelectorFromString(name);
    [call setArgument:&value atIndex:2];[call invoke];
}

@interface PreviewController : UIViewController
@property(nonatomic,strong) UIView *stage;
@property(nonatomic,strong) UITextView *report;
@property(nonatomic,strong) NSMutableArray<NSString *> *messages;
@property(nonatomic,strong) UIView *nativeView;
@property(nonatomic,strong) id nativeScene;
@property(nonatomic,strong) id nativeEffect;
@property(nonatomic,strong) NSMutableArray *observers;
@end
@implementation PreviewController
- (void)log:(NSString *)text {
    [self.messages addObject:text];self.report.text=[self.messages componentsJoinedByString:@"\n\n"];
    NSLog(@"WeatherPreview: %@",text);
}
- (void)viewDidLoad {
    [super viewDidLoad];self.messages=[NSMutableArray array];self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.stage=[UIView new];self.stage.backgroundColor=UIColor.blackColor;
    self.report=[UITextView new];self.report.editable=NO;self.report.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    UILabel *title=[UILabel new];title.text=@"Apple Weather native preview";title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];title.adjustsFontSizeToFitWidth=YES;
    UILabel *subtitle=[UILabel new];subtitle.text=@"Engine test â€” exact weather presets not connected";subtitle.numberOfLines=2;subtitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    UIButton *load=[UIButton buttonWithType:UIButtonTypeSystem];[load setTitle:@"Load native scene" forState:UIControlStateNormal];[load addTarget:self action:@selector(loadScene) forControlEvents:UIControlEventTouchUpInside];
    UIButton *copy=[UIButton buttonWithType:UIButtonTypeSystem];[copy setTitle:@"Copy test report" forState:UIControlStateNormal];[copy addTarget:self action:@selector(copyReport) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons=[[UIStackView alloc]initWithArrangedSubviews:@[load,copy]];buttons.distribution=UIStackViewDistributionFillEqually;
    UIStackView *layout=[[UIStackView alloc]initWithArrangedSubviews:@[title,subtitle,self.stage,buttons,self.report]];layout.axis=UILayoutConstraintAxisVertical;layout.spacing=8;layout.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:layout];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[layout.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],[layout.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[layout.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[layout.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[self.stage.heightAnchor constraintGreaterThanOrEqualToConstant:120],[self.report.heightAnchor constraintEqualToAnchor:layout.heightAnchor multiplier:0.28],[buttons.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    [self log:[NSString stringWithFormat:@"Preview 2 â€¢ iOS %@ â€¢ %@",UIDevice.currentDevice.systemVersion,UIDevice.currentDevice.model]];
    [self log:@"This test does not use OpenWeather, WeatherAPI or WeatherKit. No golf app files or settings are accessed."];
    self.observers=[NSMutableArray array];__weak typeof(self) weakSelf=self;
    for(NSNotificationName name in @[UIApplicationDidEnterBackgroundNotification,UIApplicationWillResignActiveNotification,UIApplicationDidBecomeActiveNotification,UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        id token=[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            BOOL active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive && ![note.name isEqualToString:UIApplicationWillResignActiveNotification] && ![note.name isEqualToString:UIApplicationDidEnterBackgroundNotification];
            [weakSelf updatePlayback:active];
        }];[self.observers addObject:token];
    }
}
- (void)dealloc {for(id token in self.observers)[NSNotificationCenter.defaultCenter removeObserver:token];}
- (void)copyReport {UIPasteboard.generalPasteboard.string=[self.messages componentsJoinedByString:@"\n\n"];}
- (void)updatePlayback:(BOOL)active {
    BOOL play=active&&!UIAccessibilityIsReduceMotionEnabled();
    @try {SetBool(self.nativeView,@"setRendersContinuously:",play);SetBool(self.nativeScene,@"setPaused:",!play);SetBool(self.nativeScene,@"setIsPlaying:",play);}
    @catch(NSException *exception){[self log:[@"Playback state: " stringByAppendingString:exception.reason?:exception.name]];}
}
- (void)loadScene {
    [self.nativeView removeFromSuperview];self.nativeView=nil;self.nativeEffect=nil;self.nativeScene=nil;
    [self log:@"Starting installed-framework test."];
    for(NSString *name in @[@"VFXBase",@"VFXAssets",@"VFX",@"WeatherUI"]) {
        NSString *path=[NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@",name,name];
        if(!dlopen(path.UTF8String,RTLD_NOW|RTLD_GLOBAL)) {const char *why=dlerror();[self log:[NSString stringWithFormat:@"Cannot load %@: %s",name,why?:"unknown error"]];return;}
    }
    Class viewClass=NSClassFromString(@"VFXView"),worldClass=NSClassFromString(@"VFXWorld");
    if(!viewClass || ![viewClass isSubclassOfClass:UIView.class] || !worldClass){[self log:@"Required native VFX classes are unavailable on this iOS build."];return;}
    NSString *framework=@"/System/Library/PrivateFrameworks/WeatherUI.framework";
    NSBundle *bundle=[NSBundle bundleWithPath:framework];[self log:[NSString stringWithFormat:@"WeatherUI build: %@",[bundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"unknown"]];
    NSURL *project=[NSURL fileURLWithPath:[framework stringByAppendingPathComponent:@"VFX/WeatherV136_Default_Background.vfx"] isDirectory:YES];
    if(![NSFileManager.defaultManager fileExistsAtPath:project.path]){[self log:@"The expected native scene is not present in this iOS build. No substitute scene was loaded."];return;}
    NSError *error=nil;
    @try {
        [self log:@"Loading VFX2 project with VFXWorld API."];
        id world=SendObject(worldClass,@"worldWithURL:options:error:",@[project,@{},NSNull.null],&error);
        if(!world){[self log:[NSString stringWithFormat:@"World load failed: %@",error.localizedDescription?:@"no world returned"]];return;}
        UIView *native=[[viewClass alloc]initWithFrame:self.stage.bounds];
        native.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        if(!SetObject(native,@"setWorld:",world)){[self log:@"Native renderer does not expose setWorld:."];return;}
        self.nativeView=native;self.nativeScene=world;self.nativeEffect=nil;[self.stage addSubview:native];
        [self updatePlayback:UIApplication.sharedApplication.applicationState==UIApplicationStateActive];
        [self log:[NSString stringWithFormat:@"Native world attached at %.0f × %.0f points.",self.stage.bounds.size.width,self.stage.bounds.size.height]];
        [self log:@"Appearance is UNVERIFIED. Apple’s per-condition configuration factory is not yet connected. A black/default scene is a diagnostic result, not a successful animation match."];
        if(UIAccessibilityIsReduceMotionEnabled())[self log:@"Reduce Motion is enabled; continuous playback remains paused."];
    } @catch(NSException *exception) {[self log:[NSString stringWithFormat:@"Native load exception: %@",exception.reason?:exception.name]];}
}
@end

@interface PreviewSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation PreviewSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if(![scene isKindOfClass:UIWindowScene.class])return;
    self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[PreviewController new];[self.window makeKeyAndVisible];
}
@end
@interface PreviewAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation PreviewAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc]initWithName:@"Preview" sessionRole:session.role];configuration.delegateClass=PreviewSceneDelegate.class;return configuration;
}
@end
int main(int argc,char *argv[]) {@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(PreviewAppDelegate.class));}}
