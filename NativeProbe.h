#import <Foundation/Foundation.h>
#include <string.h>
static const char *CGUnqualified(const char *s){while(*s && strchr("rnNoORV",*s))s++;return s;}
static NSError *CGProbeError(NSInteger code,NSString *message){return [NSError errorWithDomain:@"NativeProbe" code:code userInfo:@{NSLocalizedDescriptionKey:message}];}
// Only ordinary +0 methods. Never conceal init-family ownership in invocation.
static NSDictionary *CGInvoke(id target,NSString *method,NSArray *arguments,NSError **error){
    if(error)*error=nil;
    for(NSString *prefix in @[@"init",@"alloc",@"new",@"copy",@"mutableCopy"]){
        if([method hasPrefix:prefix]){if(error)*error=CGProbeError(1,@"Ownership-family method rejected");return nil;}
    }
    NSMethodSignature *sig=[target methodSignatureForSelector:NSSelectorFromString(method)];
    if(!sig || sig.numberOfArguments!=arguments.count+2){if(error)*error=CGProbeError(2,[@"Unavailable signature: " stringByAppendingString:method]);return nil;}
    const char *rt=CGUnqualified(sig.methodReturnType);
    if(!rt[0] || !strchr("@BcdqQ",rt[0])){if(error)*error=CGProbeError(3,[NSString stringWithFormat:@"Unsupported return ABI %s in %@; not called",rt,method]);return nil;}
    NSInvocation *call=[NSInvocation invocationWithMethodSignature:sig];call.target=target;call.selector=NSSelectorFromString(method);
    NSError *__autoreleasing nativeError=nil;NSError *__autoreleasing *address=&nativeError;
    for(NSUInteger i=0;i<arguments.count;i++){
        const char *type=CGUnqualified([sig getArgumentTypeAtIndex:i+2]);id input=arguments[i];
        if(type[0]=='@'){
            if(type[1]=='?' && input!=NSNull.null){if(error)*error=CGProbeError(4,@"Unknown callback ABI");return nil;}
            __unsafe_unretained id value=input==NSNull.null?nil:input;[call setArgument:&value atIndex:i+2];
        }else if(type[0]=='^' && type[1]=='@' && input==NSNull.null){[call setArgument:&address atIndex:i+2];}
        else{if(error)*error=CGProbeError(5,[NSString stringWithFormat:@"Unsupported argument %lu ABI %s in %@; not called",(unsigned long)i,type,method]);return nil;}
    }
    @try{
        [call retainArguments];[call invoke];id value=NSNull.null;
        switch(rt[0]){
            case '@':{__unsafe_unretained id result=nil;[call getReturnValue:&result];value=result?:NSNull.null;break;}
            case 'B':case 'c':{BOOL result=NO;[call getReturnValue:&result];value=@(result);break;}
            case 'd':{double result=0;[call getReturnValue:&result];value=@(result);break;}
            case 'q':{long long result=0;[call getReturnValue:&result];value=@(result);break;}
            case 'Q':{unsigned long long result=0;[call getReturnValue:&result];value=@(result);break;}
        }
        if(error)*error=nativeError;return @{@"type":[NSString stringWithUTF8String:rt],@"value":value};
    }@catch(NSException *exception){if(error)*error=CGProbeError(6,[NSString stringWithFormat:@"%@: %@",exception.name,exception.reason?:@""]);return nil;}
}
static BOOL CGSetObject(id target,NSString *method,id value){
    NSMethodSignature *sig=[target methodSignatureForSelector:NSSelectorFromString(method)];
    if(!sig || sig.numberOfArguments!=3 || CGUnqualified(sig.methodReturnType)[0]!='v' || CGUnqualified([sig getArgumentTypeAtIndex:2])[0]!='@')return NO;
    NSInvocation *call=[NSInvocation invocationWithMethodSignature:sig];call.target=target;call.selector=NSSelectorFromString(method);
    __unsafe_unretained id argument=value;[call setArgument:&argument atIndex:2];[call retainArguments];[call invoke];return YES;
}
static BOOL CGSetBool(id target,NSString *method,BOOL value){
    NSMethodSignature *sig=[target methodSignatureForSelector:NSSelectorFromString(method)];
    if(!sig || sig.numberOfArguments!=3 || CGUnqualified(sig.methodReturnType)[0]!='v')return NO;
    char type=CGUnqualified([sig getArgumentTypeAtIndex:2])[0];if(type!='B' && type!='c')return NO;
    NSInvocation *call=[NSInvocation invocationWithMethodSignature:sig];call.target=target;call.selector=NSSelectorFromString(method);[call setArgument:&value atIndex:2];[call invoke];return YES;
}
