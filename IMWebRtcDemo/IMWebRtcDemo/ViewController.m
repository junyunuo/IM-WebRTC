//
//  ViewController.m
//  IMWebRtcDemo
//
//  Created by guoqiang on 2019/8/15.
//  Copyright © 2019 guoqiang. All rights reserved.
//

#import "ViewController.h"
#import "WebRTCClient.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [[WebRTCClient sharedInstance] startEngine];
    UIButton* btn = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 100, 44)];
    [btn setTitle:@"点击" forState:0];
    [btn setTitleColor:[UIColor redColor] forState:0];
    [btn addTarget:self action:@selector(videoActon) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];

}

- (void)videoActon{
    
    WebRTCClient *client = [WebRTCClient sharedInstance];
    [client showRTCViewByRemoteName:@"测试" isVideo:false isCaller:true];
}


@end
