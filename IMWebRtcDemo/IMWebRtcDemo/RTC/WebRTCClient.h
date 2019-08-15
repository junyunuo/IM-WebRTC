//
//  WebRTCClient.h


#import <Foundation/Foundation.h>

#import "RTCView.h"

typedef NS_ENUM(NSInteger, ARDSignalingChannelState) {
    // State when disconnected.
    kARDSignalingChannelStateClosed,
    // State when connection is established but not ready for use.
    kARDSignalingChannelStateOpen,
    // State when connection is established and registered.
    kARDSignalingChannelStateRegistered,
    // State when connection encounters a fatal error.
    kARDSignalingChannelStateError
};

@interface WebRTCClient : NSObject
@property (strong, nonatomic)   RTCView            *rtcView;

+ (instancetype)sharedInstance;

+ (NSString *)randomRoomId;

- (void)startEngine;

- (void)stopEngine;

- (void)showRTCViewByRemoteName:(NSString *)remoteName isVideo:(BOOL)isVideo isCaller:(BOOL)isCaller;

- (void)resizeViews;

@end
