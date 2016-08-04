//
//  SDImageCache+SKCachingURLProtocol.m
//  kkShop
//
//  Created by soonkong on 16/8/3.
//  Copyright © 2016年 kk. All rights reserved.
//

#import "SDImageCache+SKCachingURLProtocol.h"

@implementation SDImageCache(SKCachingURLProtocol)

- (NSData *)imageDataWithSDImage:(UIImage *)image
{
    int alphaInfo = CGImageGetAlphaInfo(image.CGImage);
    BOOL hasAlpha = !(alphaInfo == kCGImageAlphaNone ||
                      alphaInfo == kCGImageAlphaNoneSkipFirst ||
                      alphaInfo == kCGImageAlphaNoneSkipLast);
    BOOL imageIsPng = hasAlpha;
    
    NSData *data = nil;
    
    if (imageIsPng) {
        data = UIImagePNGRepresentation(image);
    }
    else {
        data = UIImageJPEGRepresentation(image, (CGFloat)1.0);
    }
    
    return data;
}

@end
