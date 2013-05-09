//
//  SceneGraph.m
//  App Stream
//
//  Created by de Lange Paul on 5/5/13.
//  Copyright (c) 2013 __MyCompanyName__. All rights reserved.
//

#import "SceneGraph.h"

@interface SceneGraph () {
    NSMutableSet* _nodes;
    CGRect _viewRect;
    Background* _background;
    
    dispatch_source_t _animationSource;
}

@property (nonatomic, assign) CGFloat minimumZoom;
@property (nonatomic, assign) CGFloat maximumZoom;

- (void) setOffset:(CGPoint)offset animated: (BOOL) animated;

@end

@implementation SceneGraph
@synthesize offset=_offset, zoom=_scale;
@synthesize minimumZoom, maximumZoom;

- (id) init 
{
    self = [super init];
    if( self ) {
        _nodes = [NSMutableSet new];
        _scale = 1.f;
        _offset = CGPointZero;
        
        self.minimumZoom = 0.5;
        self.maximumZoom = 2.0;
    }
    
    return self;
}

- (void) setZoom:(CGFloat) scale
{
    scale = MAX(scale, self.minimumZoom);
    scale = MIN(scale, self.maximumZoom);
    
    if( scale != _scale ) {
        _scale = scale;
        [_nodes enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            //TODO: Does not handle rotation
            GLKMatrix4 existing = GLKMatrix4MakeScale(_scale, _scale, 1.0);
            existing = GLKMatrix4Multiply(existing, GLKMatrix4MakeTranslation(-_offset.x, -_offset.y, 0));
            [obj setModelViewMatrix: existing];
        }];
    }
}

- (void) setOffset: (CGPoint)offset
{
    [self setOffset: offset animated: NO];
}

- (CGRect) visibleRect {
    CGRect rect = _viewRect;
    rect.origin.x -= _offset.x;
    rect.origin.y -= _offset.y;
    
    rect.origin.x /= _scale;
    rect.origin.y /= _scale;
    
    rect.size.width /= _scale;
    rect.size.height /= _scale;
    
    return rect;
}

#pragma mark - Animations
- (BOOL) isAnimating {
    return _animationSource != nil;
}

- (void) cancelAnimation {
    if( _animationSource ) {
        dispatch_source_cancel(_animationSource);
        _animationSource = nil;
    }
}
   
- (void) setCenter: (CGPoint) center animated: (BOOL) animated {
    NSParameterAssert(_background);
    
    [self cancelAnimation];
    
    GLKMatrix4 projection = _background.projectionMatrix;
    GLKMatrix4 modelView = _background.modelViewMatrix;
    GLKVector3 windowCenter = GLKVector3Make(center.x, center.y, 0.0);
    
    int vp[4] = {0, 0, (int)CGRectGetWidth(_viewRect), (int)CGRectGetHeight(_viewRect)};
    
    bool success;
        
    GLKVector3 worldCenter = GLKMathUnproject(windowCenter,
                                              modelView,
                                              projection, 
                                              vp, 
                                              &success);
    NSParameterAssert(success);
    [self setOffset: CGPointMake(worldCenter.x, worldCenter.y) animated: animated];
}

- (void) setOffset: (CGPoint)offset animated: (BOOL) animated {
    GLKVector2 bgSize = _background.size;
    CGFloat maxZoom = 1./self.minimumZoom;
    
    CGFloat rangeX = bgSize.x /= maxZoom;
    CGFloat rangeY = bgSize.y /= maxZoom;
    
    CGFloat maxXOffset = (rangeX-CGRectGetWidth(_viewRect))/2.f;
    CGFloat maxYOffset = (rangeY-CGRectGetHeight(_viewRect))/2.f;
    
    NSParameterAssert(maxXOffset > 0);
    NSParameterAssert(maxYOffset > 0);
    
    if( offset.x < -maxXOffset ) {
        //NSLog(@"Moving off left");
        return;
    }
    else if( offset.x > maxXOffset ) {
        //NSLog(@"Moving off right");
        return;
    }
    else if(offset.y < -maxYOffset ) {
        //NSLog(@"Moving off top");
        return;
    }
    else if(offset.y > maxYOffset ) {
        //NSLog(@"Moving off bottom");
        return;
    }
    
    __block CGFloat progress = 0.f;
    __block CGPoint initial = _offset;
    
    void (^animation)(void) = ^{
        
        if( _animationSource ) {
            unsigned long timesFired = dispatch_source_get_data(_animationSource);
            progress += .1 * timesFired;
        }
        else {
            progress = 1.f;
        }
        
        CGFloat x = (offset.x - initial.x) * progress;
        CGFloat y = (offset.y - initial.y) * progress;
        
        CGPoint offset = CGPointMake(x, y);
        
        if( !CGPointEqualToPoint(offset, _offset) ) {
            _offset = offset;
            [_nodes enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                GLKMatrix4 existing = [obj modelViewMatrix];
                existing.m30 = -_offset.x;
                existing.m31 = _offset.y;
                [obj setModelViewMatrix: existing];
            }];
        }
        
        if( progress >= 1.f )
            [self cancelAnimation];
    };
    
    if( animated ) {
        _animationSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(_animationSource, DISPATCH_TIME_NOW, 1 / 30.f * NSEC_PER_SEC, 1 / 300. * NSEC_PER_SEC);
        dispatch_source_set_event_handler(_animationSource, animation);
        dispatch_resume(_animationSource);
    }
    else {
        animation();
    }
}

#pragma mark - Object Graph
- (void) addNode:(Node *)node 
{
    NSParameterAssert([node isKindOfClass: [Node class]]);
    [_nodes addObject: node];
}

- (void) setBackground: (Background*) background 
{
#if DEBUG
    CGRect screen = [UIScreen mainScreen].bounds;
    screen.size.width /= self.minimumZoom;
    screen.size.height /= self.minimumZoom;
    GLKVector2 size = background.size;
    
    NSAssert(size.x >= screen.size.width, @"Background is %dx%d and the minimum is %dx%d", 
             (int)size.x, (int)size.y, 
             (int)screen.size.width, (int)screen.size.height);
    NSAssert(size.y >= screen.size.height, @"Background is %dx%d and the minimum is %dx%d", 
             (int)size.x, (int)size.y, 
             (int)screen.size.width, (int)screen.size.height);
#endif
    
    if( background != _background ) {
        if(_background ) {
            NSParameterAssert([_nodes containsObject: _background]);
            [_nodes removeObject: _background];
        }
        _background = background;
        
        if( _background )
            [_nodes addObject: _background];
    }
}

- (NSSet*) nodesIntersectingRect: (CGRect) rect 
{
    NSPredicate* inRectPredicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        CGRect box = [evaluatedObject projectionInScreenRect: rect];
        return CGRectIntersectsRect([self visibleRect], box);
    }];
    
    return [_nodes filteredSetUsingPredicate: inRectPredicate];
}

#pragma mark - GLKViewControllerDelegate
- (void) glkViewControllerUpdate:(GLKViewController *)controller 
{
    NSParameterAssert([controller isViewLoaded]);
    CGRect viewRect = controller.view.bounds;
    if( !CGRectEqualToRect(viewRect, _viewRect) ) {
        _viewRect = viewRect;
        
        CGFloat halfWidth = CGRectGetWidth(viewRect) / 2.f;
        CGFloat halfHeight = CGRectGetHeight(viewRect) / 2.f;
        
        GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(-halfWidth, halfWidth,
                                                          -halfHeight, halfHeight,
                                                          0.1, 100);
        [_nodes enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            [obj setProjectionMatrix: projectionMatrix]; 
        }];
    }
}

- (void)glkViewController:(GLKViewController *)controller willPause:(BOOL)pause 
{
    
}

@end