#import <Foundation/Foundation.h>

@protocol CGNativeSceneInitializers <NSObject>
- (instancetype)initWithOptions:(id)options;
- (instancetype)initWithContentsOf:(NSURL *)url options:(id)options error:(NSError **)error;
@end

// Keep allocation and init together so ARC consumes the receiver exactly once,
// including when an initializer disposes of self and returns nil.
static id CGCreateSceneWithOptions(Class sceneClass, id options) {
    return [(id<CGNativeSceneInitializers>)[sceneClass alloc] initWithOptions:options];
}
static id CGCreateSceneAtURL(Class sceneClass, NSURL *url, id options, NSError **error) {
    return [(id<CGNativeSceneInitializers>)[sceneClass alloc] initWithContentsOf:url options:options error:error];
}
