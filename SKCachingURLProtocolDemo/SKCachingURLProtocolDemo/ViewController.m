//
//  ViewController.m
//  SKCachingURLProtocolDemo
//
//  Created by soonkong on 16/8/4.
//  Copyright © 2016年 SK. All rights reserved.
//

#import "ViewController.h"
#import <SDWebImage/UIImageView+WebCache.h>

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIWebView *webVw;
@property (weak, nonatomic) IBOutlet UIImageView *leftImgVw;
@property (weak, nonatomic) IBOutlet UIImageView *rightImgVw;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [_leftImgVw sd_setImageWithURL:[NSURL URLWithString:@"http://img.taopic.com/uploads/allimg/121209/234928-12120Z0543764.jpg"]];
    [_rightImgVw sd_setImageWithURL:[NSURL URLWithString:@"http://pic5.nipic.com/20100227/1792030_104216059332_2.jpg"]];
    
    NSURLRequest *req = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://m.toutiao.com/"]];
    [_webVw loadRequest:req];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
