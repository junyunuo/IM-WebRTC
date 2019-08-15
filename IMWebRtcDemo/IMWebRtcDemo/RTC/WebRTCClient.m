//
//  WebRTCClient.m

#import <AVFoundation/AVFoundation.h>
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>

#import "WebRTCClient.h"
#import "RTCContants.h"
#import "RTCICEServer.h"
#import "RTCICECandidate.h"
#import "RTCICEServer.h"
#import "RTCMediaConstraints.h"
#import "RTCMediaStream.h"
#import "RTCPair.h"
#import "RTCPeerConnection.h"
#import "RTCPeerConnectionDelegate.h"
#import "RTCPeerConnectionFactory.h"
#import "RTCSessionDescription.h"
#import "RTCVideoRenderer.h"
#import "RTCVideoCapturer.h"
#import "RTCVideoTrack.h"
#import "RTCAVFoundationVideoSource.h"
#import "RTCSessionDescriptionDelegate.h"
#import "RTCEAGLVideoView.h"
#import "SRWebSocket.h"

@interface WebRTCClient ()<RTCPeerConnectionDelegate,RTCSessionDescriptionDelegate,RTCEAGLVideoViewDelegate,SRWebSocketDelegate>

@property (strong, nonatomic)   RTCPeerConnectionFactory            *peerConnectionFactory;
@property (nonatomic, strong)   RTCMediaConstraints                 *pcConstraints;
@property (nonatomic, strong)   RTCMediaConstraints                 *sdpConstraints;
@property (nonatomic, strong)   RTCMediaConstraints                 *videoConstraints;
@property (nonatomic, strong)   RTCPeerConnection                   *peerConnection;

@property (nonatomic, strong)   RTCEAGLVideoView                    *localVideoView;
@property (nonatomic, strong)   RTCEAGLVideoView                    *remoteVideoView;
@property (nonatomic, strong)   RTCVideoTrack                       *localVideoTrack;
@property (nonatomic, strong)   RTCVideoTrack                       *remoteVideoTrack;

/**用于传送信令的websocket */
@property (strong, nonatomic)   SRWebSocket                 *webSocket;

@property (assign, nonatomic)   ARDSignalingChannelState             sinalingChannelState;  /**< 信令通道的状态 */

@property (strong, nonatomic)   AVAudioPlayer               *audioPlayer;  /**< 音频播放器 */

@property (strong, nonatomic)   NSMutableArray              *ICEServers;

@property (strong, nonatomic)   NSMutableArray              *messages;  /**< 信令消息队列 */

@property (assign, nonatomic)   BOOL                        initiator;  /**< 是否是发起方 */

@property (assign, nonatomic)   BOOL                        hasReceivedSdp;  /**< 已经收到SDP信息 */

@property(nonatomic,strong)NSString* conversationID;//会话对象


@property(nonatomic,assign)BOOL isSettingRemoteSdp;//是否设置了远程SDP

@property(nonatomic,assign)BOOL isSettingCandidate;//是否设置了候选

@property(nonatomic,strong)NSTimer* nsTimer;

@property(nonatomic,assign)int timerCount;

@end

@implementation WebRTCClient

static WebRTCClient *instance = nil;

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[[self class] alloc] init];
        instance.ICEServers = [NSMutableArray arrayWithObjects:[instance defaultSTUNServer],[instance defaultSTUNServer2],nil];
        instance.messages = [NSMutableArray array];
        
        [instance addNotifications];
    });
    return instance;
}
- (void)addNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hangupEvent) name:kHangUpNotification object:nil];
   // [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveSignalingMessage:) name:kReceivedSinalingMessageNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(acceptAction) name:kAcceptNotification object:nil];
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [super allocWithZone:zone];
    });
    return instance;
}

#pragma mark STURN 服务器
- (RTCICEServer *)defaultSTUNServer {
    NSURL *defaultSTUNServerURL = [NSURL URLWithString:RTCSTUNServerURL];
    return [[RTCICEServer alloc] initWithURI:defaultSTUNServerURL
                                    username:@""
                                    password:@""];
}

#pragma mark TURN 服务器
- (RTCICEServer *)defaultSTUNServer2 {
    NSURL *defaultSTUNServerURL = [NSURL URLWithString:RTCTRUNServerURL];
    return [[RTCICEServer alloc] initWithURI:defaultSTUNServerURL
                                    username:@""
                                    password:@""];
}



#pragma mark 配置约束
- (void)startEngine
{
    [RTCPeerConnectionFactory initializeSSL];
    self.peerConnectionFactory = [[RTCPeerConnectionFactory alloc] init];
    NSArray *mandatoryConstraints = @[[[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"],
                                      [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"true"]
                                      ];
    NSArray *optionalConstraints = @[[[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"]];
    self.pcConstraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints optionalConstraints:optionalConstraints];
    
    NSArray *sdpMandatoryConstraints = @[[[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"],
                                         [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"true"]
                                         ];
    self.sdpConstraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:sdpMandatoryConstraints optionalConstraints:nil];
    self.videoConstraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil];
}

- (void)stopEngine
{
    [RTCPeerConnectionFactory deinitializeSSL];
    _peerConnectionFactory = nil;
}

- (void)showRTCViewByRemoteName:(NSString *)remoteName isVideo:(BOOL)isVideo isCaller:(BOOL)isCaller{
    
    
    // 1.显示视图
    self.rtcView = [[RTCView alloc] initWithIsVideo:isVideo isCallee:!isCaller];
    self.rtcView.nickName = @"";
    self.rtcView.connectText = @"等待对方接听";
    self.rtcView.netTipText = @"网络状况良好";
    [self.rtcView show];
    
    // 2.播放声音
    NSURL *audioURL;
    if (isCaller) {
        audioURL = [[NSBundle mainBundle] URLForResource:@"AVChat_waitingForAnswer.mp3" withExtension:nil];
    } else {
        audioURL = [[NSBundle mainBundle] URLForResource:@"AVChat_incoming.mp3" withExtension:nil];
    }
    _audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:audioURL error:nil];
    _audioPlayer.numberOfLoops = -1;
    [_audioPlayer prepareToPlay];
    [_audioPlayer play];
    
    self.timerCount = 1;
    self.isSettingCandidate = false;
    self.isSettingRemoteSdp = false;
    
    // 3.拨打时，禁止黑屏
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    // 4.监听系统电话
    [self listenSystemCall];
    
    //发送者对象
    self.conversationID = @"1";
    
    
    /** 连接webSocket **/
//    NSURL *webSocketURL = [NSURL URLWithString:RTCWebSockeServerURL];
//    _webSocket = [[SRWebSocket alloc] initWithURL:webSocketURL];
//    _webSocket.delegate = self;
//    [_webSocket open];
    
    
    //    // 5.做RTC必要设置
    if (isCaller) {
        //        // 如果是发起者
        self.initiator = YES;
        
        [self initRTCSetting];
        // 创建一个offer信令
        [self.peerConnection createOfferWithDelegate:self constraints:self.sdpConstraints];
    } else {
        self.initiator = NO;
        // 如果是接收者，就要处理信令信息，创建一个answer
        NSLog(@"如果是接收者，就要处理信令信息");
        self.rtcView.connectText = isVideo ? @"视频通话":@"语音通话";
    }
}

- (void)listenSystemCall
{
    self.callCenter = [[CTCallCenter alloc] init];
    self.callCenter.callEventHandler = ^(CTCall* call) {
        if ([call.callState isEqualToString:CTCallStateDisconnected])
        {
            NSLog(@"Call has been disconnected");
        }
        else if ([call.callState isEqualToString:CTCallStateConnected])
        {
            NSLog(@"Call has just been connected");
        }
        else if([call.callState isEqualToString:CTCallStateIncoming])
        {
            NSLog(@"Call is incoming");
        }
        else if ([call.callState isEqualToString:CTCallStateDialing])
        {
            NSLog(@"call is dialing");
        }
        else
        {
            NSLog(@"Nothing is done");
        }
    };
}

/**
 *  关于RTC 的设置
 */
- (void)initRTCSetting
{
    self.peerConnection = [self.peerConnectionFactory peerConnectionWithICEServers:_ICEServers constraints:self.pcConstraints delegate:self];
    
    //设置 local media stream
    RTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithLabel:@"ARDAMS"];
    // 添加 local video track
    RTCAVFoundationVideoSource *source = [[RTCAVFoundationVideoSource alloc] initWithFactory:self.peerConnectionFactory constraints:self.videoConstraints];
    RTCVideoTrack *localVideoTrack = [[RTCVideoTrack alloc] initWithFactory:self.peerConnectionFactory source:source trackId:@"AVAMSv0"];
    [mediaStream addVideoTrack:localVideoTrack];
    self.localVideoTrack = localVideoTrack;
    
    // 添加 local audio track
    RTCAudioTrack *localAudioTrack = [self.peerConnectionFactory audioTrackWithID:@"ARDAMSa0"];
    [mediaStream addAudioTrack:localAudioTrack];
    // 添加 mediaStream
    [self.peerConnection addStream:mediaStream];
    
    RTCEAGLVideoView *localVideoView = [[RTCEAGLVideoView alloc] initWithFrame:self.rtcView.ownImageView.bounds];
    localVideoView.transform = CGAffineTransformMakeScale(-1, 1);
    localVideoView.delegate = self;
    [self.rtcView.ownImageView addSubview:localVideoView];
    self.localVideoView = localVideoView;
    
    [self.localVideoTrack addRenderer:self.localVideoView];
    
    RTCEAGLVideoView *remoteVideoView = [[RTCEAGLVideoView alloc] initWithFrame:self.rtcView.adverseImageView.bounds];
    remoteVideoView.transform = CGAffineTransformMakeScale(-1, 1);
    remoteVideoView.delegate = self;
    [self.rtcView.adverseImageView addSubview:remoteVideoView];
    self.remoteVideoView = remoteVideoView;
}

- (void)cleanCache
{
    // 1.将试图置为nil
    self.rtcView = nil;
    
    // 2.将音乐停止
    if ([_audioPlayer isPlaying]) {
        [_audioPlayer stop];
    }
    _audioPlayer = nil;
    
    // 3.取消手机常亮
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    // 4.取消系统电话监听
    self.callCenter = nil;
    
    _peerConnection = nil;
    _localVideoTrack = nil;
    _remoteVideoTrack = nil;
    _localVideoView = nil;
    _remoteVideoView = nil;
    _hasReceivedSdp = NO;
    _webSocket = nil;
}

- (void)resizeViews
{
    [self videoView:self.localVideoView didChangeVideoSize:self.rtcView.ownImageView.bounds.size];
    [self videoView:self.remoteVideoView didChangeVideoSize:self.rtcView.adverseImageView.bounds.size];
}


#pragma mark 发送消息
- (void)webSocketSendMessage:(NSString *)message
{
    if (!_webSocket) {
        NSLog(@"webSocket还未创建");
        return;
    }
    NSDictionary *messageDict = @{@"cmd": @"send", @"msg": message};
    NSData *messageJSONObject = [NSJSONSerialization dataWithJSONObject:messageDict
                                                                options:NSJSONWritingPrettyPrinted
                                                                  error:nil];
    NSString *messageString = [[NSString alloc] initWithData:messageJSONObject
                                                    encoding:NSUTF8StringEncoding];
    
    [_webSocket send:messageString];
    NSLog(@"发送信令啦");
    
}

- (RTCSessionDescription *)descriptionWithDescription:(RTCSessionDescription *)description videoFormat:(NSString *)videoFormat
{
    NSString *sdpString = description.description;
    NSString *lineChar = @"\n";
    NSMutableArray *lines = [NSMutableArray arrayWithArray:[sdpString componentsSeparatedByString:lineChar]];
    NSInteger mLineIndex = -1;
    NSString *videoFormatRtpMap = nil;
    NSString *pattern = [NSString stringWithFormat:@"^a=rtpmap:(\\d+) %@(/\\d+)+[\r]?$", videoFormat];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    for (int i = 0; (i < lines.count) && (mLineIndex == -1 || !videoFormatRtpMap); ++i) {
        // mLineIndex 和 videoFromatRtpMap 都更新了之后跳出循环
        NSString *line = lines[i];
        if ([line hasPrefix:@"m=video"]) {
            mLineIndex = i;
            continue;
        }
        
        NSTextCheckingResult *result = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (result) {
            videoFormatRtpMap = [line substringWithRange:[result rangeAtIndex:1]];
            continue;
        }
    }
    
    if (mLineIndex == -1) {
        // 没有m = video line, 所以不能转格式,所以返回原来的description
        return description;
    }
    
    if (!videoFormatRtpMap) {
        // 没有videoFormat 类型的rtpmap。
        return description;
    }
    
    NSString *spaceChar = @" ";
    NSArray *origSpaceLineParts = [lines[mLineIndex] componentsSeparatedByString:spaceChar];
    if (origSpaceLineParts.count > 3) {
        NSMutableArray *newMLineParts = [NSMutableArray arrayWithCapacity:origSpaceLineParts.count];
        NSInteger origPartIndex = 0;
        
        [newMLineParts addObject:origSpaceLineParts[origPartIndex++]];
        [newMLineParts addObject:origSpaceLineParts[origPartIndex++]];
        [newMLineParts addObject:origSpaceLineParts[origPartIndex++]];
        [newMLineParts addObject:videoFormatRtpMap];
        for (; origPartIndex < origSpaceLineParts.count; ++origPartIndex) {
            if (![videoFormatRtpMap isEqualToString:origSpaceLineParts[origPartIndex]]) {
                [newMLineParts addObject:origSpaceLineParts[origPartIndex]];
            }
        }
        
        NSString *newMLine = [newMLineParts componentsJoinedByString:spaceChar];
        [lines replaceObjectAtIndex:mLineIndex withObject:newMLine];
    } else {
        NSLog(@"SDP Media description 格式 错误");
    }
    NSString *mangledSDPString = [lines componentsJoinedByString:lineChar];
    
    return [[RTCSessionDescription alloc] initWithType:description.type sdp:mangledSDPString];
}

#pragma mark 挂断
- (void)hangupEvent
{
    NSDictionary *dict = @{@"type":@"bye"};
    [self processMessageDict:dict];
}
- (void)handleSignalingMessage:(NSDictionary *)dict
{
    NSString *type = dict[@"type"];
    if ([type isEqualToString:@"offer"] || [type isEqualToString:@"answer"]) {
        [self.messages insertObject:dict atIndex:0];
        _hasReceivedSdp = YES;
    } else if ([type isEqualToString:@"candidate"]) {
        [self.messages addObject:dict];
    } else if ([type isEqualToString:@"bye"]) {
        [self processMessageDict:dict];
    }
}

- (void)drainMessages
{
    if (!_peerConnection || !_hasReceivedSdp) {
        return;
    }
    for (NSDictionary *dict in self.messages) {
        [self processMessageDict:dict];
    }
    [self.messages removeAllObjects];
}


#pragma mark 接听
- (void)acceptAction
{
    [self.audioPlayer stop];
    [self initRTCSetting];
    for (NSDictionary *dict in self.messages) {
        [self processMessageDict:dict];
    }
    [self.messages removeAllObjects];
}


#pragma mark 设置远程SDP 或者候选数据
- (void)processMessageDict:(NSDictionary *)dict
{
    if(self.peerConnection == nil){
        return;
    }
    
    NSString *type = dict[@"type"];
    if ([type isEqualToString:@"offer"]) {
        //得到远程sdp 并且创建offer
        self.isSettingRemoteSdp = true;
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:@"offer" sdp:dict[@"sdp"]];
        [self.peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSdp];
        [self.peerConnection createAnswerWithDelegate:self constraints:self.sdpConstraints];
    } else if ([type isEqualToString:@"answer"]){
        //对方同意应答之后  推送过来的sdp
        if(self.isSettingRemoteSdp){
            return;
        }
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:@"answer" sdp:dict[@"sdp"]];
        [self.peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSdp];
        self.isSettingRemoteSdp = true;
        if(!self.isSettingCandidate){
            for (NSDictionary *dict in self.messages) {
                [self processMessageDict:dict];
            }
        }
    } else if ([type isEqualToString:@"candidate"]){//设置候选数据
        if(!self.isSettingRemoteSdp){
            return;
        }
        self.isSettingCandidate = true;
        NSString *mid = [dict objectForKey:@"id"];
        NSNumber *sdpLineIndex = [dict objectForKey:@"label"];
        NSString *sdp = [dict objectForKey:@"candidate"];
        RTCICECandidate *candidates = [[RTCICECandidate alloc] initWithMid:mid index:sdpLineIndex.intValue sdp:sdp];
        [self.peerConnection addICECandidate:candidates];
        // [self.messages removeAllObjects];
    } else if([type isEqualToString:@"bye"]){
        [self.messages removeAllObjects];
        self.isSettingCandidate = false;
        self.isSettingRemoteSdp = false;
        [self.peerConnection close];
        [self.nsTimer invalidate];
        self.nsTimer = nil;
        self.timerCount = 1;
        [self.rtcView dismiss];
        [self cleanCache];
    }
    
}

#pragma mark - RTCPeerConnectionDelegate
// Triggered when the SignalingState changed.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
 signalingStateChanged:(RTCSignalingState)stateChanged
{
    NSLog(@"信令状态改变");
    switch (stateChanged) {
        case RTCSignalingStable:
        {
            NSLog(@"stateChanged = RTCSignalingStable");
        }
            break;
        case RTCSignalingClosed:
        {
            NSLog(@"stateChanged = RTCSignalingClosed");
        }
            break;
        case RTCSignalingHaveLocalOffer:
        {
            NSLog(@"stateChanged = RTCSignalingHaveLocalOffer");
        }
            break;
        case RTCSignalingHaveRemoteOffer:
        {
            NSLog(@"stateChanged = RTCSignalingHaveRemoteOffer");
        }
            break;
        case RTCSignalingHaveRemotePrAnswer:
        {
            NSLog(@"stateChanged = RTCSignalingHaveRemotePrAnswer");
        }
            break;
        case RTCSignalingHaveLocalPrAnswer:
        {
            NSLog(@"stateChanged = RTCSignalingHaveLocalPrAnswer");
        }
            break;
    }

}

// Triggered when media is received on a new stream from remote peer.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream
{
    NSLog(@"已添加多媒体流");
    NSLog(@"Received %lu video tracks and %lu audio tracks",
          (unsigned long)stream.videoTracks.count,
          (unsigned long)stream.audioTracks.count);
    if ([stream.videoTracks count]) {
        self.remoteVideoTrack = nil;
        [self.remoteVideoView renderFrame:nil];
        self.remoteVideoTrack = stream.videoTracks[0];
        [self.remoteVideoTrack addRenderer:self.remoteVideoView];
    }
    
    [self videoView:self.remoteVideoView didChangeVideoSize:self.rtcView.adverseImageView.bounds.size];
    [self videoView:self.localVideoView didChangeVideoSize:self.rtcView.ownImageView.bounds.size];
}

// Triggered when a remote peer close a stream.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
         removedStream:(RTCMediaStream *)stream
{
    NSLog(@"a remote peer close a stream");
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection
{
    NSLog(@"Triggered when renegotiation is needed");
}

// Called any time the ICEConnectionState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
  iceConnectionChanged:(RTCICEConnectionState)newState
{
    NSLog(@"%s",__func__);
    switch (newState) {
        case RTCICEConnectionNew:
        {
            NSLog(@"newState = RTCICEConnectionNew");
        }
            break;
        case RTCICEConnectionChecking:
        {
            NSLog(@"newState = RTCICEConnectionChecking");
        }
            break;
        case RTCICEConnectionConnected:
        {
            /** todo 这里为建立连接成功**/
            NSLog(@"newState = RTCICEConnectionConnected");//15:56:56.698 15:56:57.570
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"main");
                [self.messages removeAllObjects];
                //主线程执行
                [self.audioPlayer stop];
                self.rtcView.connectText = @"正在通话中...";
                NSLog(@"newState = RTCICEConnectionConnected");//15:56:56.698 15:56:57.570
                //开始通话之后 开始启动定时器及时
                self.nsTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timeAction) userInfo:nil repeats:true];
            });
        }
            break;
        case RTCICEConnectionCompleted:
        {
            NSLog(@"newState = RTCICEConnectionCompleted");//5:56:57.573
        }
            break;
        case RTCICEConnectionFailed:
        {
            NSLog(@"newState = RTCICEConnectionFailed");
        }
            break;
        case RTCICEConnectionDisconnected:
        {
            NSLog(@"newState = RTCICEConnectionDisconnected");
        }
            break;
        case RTCICEConnectionClosed:
        {
            NSLog(@"newState = RTCICEConnectionClosed");
        }
            break;
        case RTCICEConnectionMax:
        {
            NSLog(@"newState = RTCICEConnectionMax");
        }
            break;
    }
}
#pragma mark 计时器
- (void)timeAction{
    
    self.timerCount ++;
}

#pragma mark 候选回调
- (void)peerConnection:(RTCPeerConnection *)peerConnection
       gotICECandidate:(RTCICECandidate *)candidate
{
    
    NSDictionary *jsonDict = @{@"type":@"candidate",
                               @"label":[NSNumber numberWithInteger:candidate.sdpMLineIndex],
                               @"id":candidate.sdpMid,
                               @"sdp":candidate.sdp
                               };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
    if (jsonData.length > 0) {
        //推送候选
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self webSocketSendMessage:jsonStr];
    }
}

// New data channel has been opened.
- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel
{
    NSLog(@"New data channel has been opened.");
}

#pragma mark - RTCSessionDescriptionDelegate
// Called when creating a session.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didCreateSessionDescription:(RTCSessionDescription *)sdp
                 error:(NSError *)error
{
    if (error) {
        NSLog(@"创建SessionDescription 失败");

    } else {
        NSLog(@"创建SessionDescription 成功");
        RTCSessionDescription *sdpH264 = [self descriptionWithDescription:sdp videoFormat:@"H264"];
        [self.peerConnection setLocalDescriptionWithDelegate:self sessionDescription:sdpH264];

        //推送SDP
        NSDictionary *jsonDict = @{ @"type" : sdp.type, @"sdp" : sdp.description,@"to_user":self.conversationID};
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self webSocketSendMessage:jsonStr];
    }
}

// Called when setting a local or remote description.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didSetSessionDescriptionWithError:(NSError *)error
{
    NSLog(@"%s",__func__);
    
    if (error) {
        NSLog(@"设置SessionDescription失败");
        return;
    }
    
}

#pragma mark - RTCEAGLVideoViewDelegate
- (void)videoView:(RTCEAGLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
    if (videoView == self.localVideoView) {
        
        NSLog(@"local size === %@",NSStringFromCGSize(size));
    }else if (videoView == self.remoteVideoView){
        NSLog(@"remote size === %@",NSStringFromCGSize(size));
    }
}

#pragma mark - SRWebSocketDelegate
- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSLog(@"WebSocket connection opened.");
    self.sinalingChannelState = kARDSignalingChannelStateOpen;

}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    NSString *messageString = message;
    NSData *messageData = [messageString dataUsingEncoding:NSUTF8StringEncoding];
    id jsonObject = [NSJSONSerialization JSONObjectWithData:messageData
                                                    options:0
                                                      error:nil];
    if (![jsonObject isKindOfClass:[NSDictionary class]]) {
        NSLog(@"Unexpected message: %@", jsonObject);
        return;
    }
    NSDictionary *wssMessage = jsonObject;
    NSLog(@"WebSocket 接收到信息:%@",wssMessage);
    NSString *errorString = wssMessage[@"error"];
    if (errorString.length) {
        NSLog(@"WebSocket收到错误信息");
        return;
    }
    
    NSString *msg = wssMessage[@"msg"];
    NSData *data = [msg dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *sinalingMsg = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    [self handleSignalingMessage:sinalingMsg];
    [self drainMessages];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"WebSocket error: %@", error);
    self.sinalingChannelState = kARDSignalingChannelStateError;
}

- (void)webSocket:(SRWebSocket *)webSocket
 didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason
         wasClean:(BOOL)wasClean {
    NSLog(@"WebSocket closed with code: %ld reason:%@ wasClean:%d",
          (long)code, reason, wasClean);
    self.sinalingChannelState = kARDSignalingChannelStateClosed;
}

@end
