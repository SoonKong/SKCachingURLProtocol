//
//  SDImageCache+SKCachingURLProtocol.h
//  kkShop
//
//  Created by soonkong on 16/8/3.
//  Copyright © 2016年 kk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SDWebImage/SDImageCache.h>

@interface SDImageCache(SKCachingURLProtocol)

//This private method exist in SDImageCache.m, addition out to use
- (NSData *)diskImageDataBySearchingAllPathsForKey:(NSString *)key;

- (NSData *)imageDataWithSDImage:(UIImage *)image;

@end



