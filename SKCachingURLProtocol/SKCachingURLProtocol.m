//
//  SKCachingURLProtocol.m
//
//  Created by soonkong on 16/8/1.
//  Copyright © 2016年 S.K. All rights reserved.
//

#import "SKCachingURLProtocol.h"
#import "Reachability.h"
#import "NSString+Sha1.h"
#import <SDWebImage/SDWebImageManager.h>
#import <SDWebImage/SDWebImageDownloader.h>
#import "SDImageCache+SKCachingURLProtocol.h"

//only handle the image request
#define CACHING_ONLY_IMAGE  0

#define WORKAROUND_MUTABLE_COPY_LEAK 1

#if WORKAROUND_MUTABLE_COPY_LEAK
// required to workaround http://openradar.appspot.com/11596316
@interface NSURLRequest(MutableCopyWorkaround)

- (id) mutableCopyWorkaround;

@end
#endif


@interface SKCachedData : NSObject <NSCoding>
@property (nonatomic, readwrite, strong) NSData *data;
@property (nonatomic, readwrite, strong) NSURLResponse *response;
@property (nonatomic, readwrite, strong) NSURLRequest *redirectRequest;
@end

static NSString *SKCachingURLHeader = @"X-SKCache";

@interface SKCachingURLProtocol () // <NSURLConnectionDelegate, NSURLConnectionDataDelegate> iOS5-only
@property (nonatomic, readwrite, strong) NSURLConnection *connection;
@property (nonatomic, readwrite, strong) NSMutableData *data;
@property (nonatomic, readwrite, strong) NSURLResponse *response;
- (void)appendData:(NSData *)newData;
@end

static NSObject *SKCachingSupportedSchemesMonitor;
static NSSet *SKCachingSupportedSchemes;

@implementation SKCachingURLProtocol
@synthesize connection = connection_;
@synthesize data = data_;
@synthesize response = response_;

+ (void)initialize
{
    if (self == [SKCachingURLProtocol class])
    {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            SKCachingSupportedSchemesMonitor = [NSObject new];
        });
        
        //Setting RNCachingURLHeader, avoiding confrontations between SDWebImage and the NSURLProtocol
        //The image downloading from using the SDWebImage, Skip the handling in +[NSURLProtocol canInitWithRequest:].
        [[SDWebImageDownloader sharedDownloader] setValue:SKCachingURLHeader forHTTPHeaderField:SKCachingURLHeader];
        [self setSupportedSchemes:[NSSet setWithObject:@"http"]];
    }
}

//is a picture request
+ (BOOL)isPictureExtension:(NSString *)extension
{
    if (extension && ![extension isEqualToString:@""]) {
        if ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"] || [extension isEqualToString:@"png"] || [extension isEqualToString:@"gif"] || [extension isEqualToString:@"bmp"]) {
            return YES;
        }
    }
    
    return NO;
}

+ (BOOL)networkReachability
{
    BOOL reachable = (BOOL) [[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable;
    return reachable;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    // only handle http requests we haven't marked with our header.
    if ([[self supportedSchemes] containsObject:[[request URL] scheme]] &&
        ([request valueForHTTPHeaderField:SKCachingURLHeader] == nil))
    {
#if CACHING_ONLY_IMAGE
        //only caching the picture
        if ([SKCachingURLProtocol isPictureExtension:[[request URL] pathExtension]]) {
            return YES;
        }
#else
        return YES;
#endif
    }
    
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (NSString *)cachePathForRequest:(NSURLRequest *)aRequest
{
    // This stores in the Caches directory, which can be deleted when space is low, but we only use it for offline access
    NSString *cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    NSString *fileName = [[[aRequest URL] absoluteString] sha1];
    
    return [cachesPath stringByAppendingPathComponent:fileName];
}

- (void)startLoading
{
    if (![self useCache]) {
        if ([SKCachingURLProtocol isPictureExtension:[[[self request] URL] pathExtension]]) {
            
            //use SDWebImage to download the image
            [[SDWebImageManager sharedManager] downloadImageWithURL:[[self request] URL]
                                                            options:0
                                                           progress:nil
                                                          completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                              
                                                              if (image) {
                                                                  NSData *data = [[SDImageCache sharedImageCache] imageDataWithSDImage:image];
                                                                  
                                                                  if (!data) {
                                                                      data = UIImageJPEGRepresentation(image, (CGFloat)1.0);
                                                                  }
                                                                  
                                                                  if (data) {
                                                                      NSURLResponse *newResponse = [[NSURLResponse alloc] initWithURL:[self.request URL]
                                                                                                                             MIMEType:nil
                                                                                                                expectedContentLength:data.length
                                                                                                                     textEncodingName:nil];
                                                                      [[self client] URLProtocol:self didReceiveResponse:newResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed]; // we handle caching ourselves.
                                                                      [[self client] URLProtocol:self didLoadData:data];
                                                                      [[self client] URLProtocolDidFinishLoading:self];
                                                                  }
                                                              }
                                                              else {
                                                                  //if the network reachability,reload; or lost the request
                                                                  if ([SKCachingURLProtocol networkReachability]) {
                                                                      [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]];
                                                                      
                                                                  }
                                                              }
                                                              
                                                          }];
        }
        else {
            NSMutableURLRequest *connectionRequest =
#if WORKAROUND_MUTABLE_COPY_LEAK
            [[self request] mutableCopyWorkaround];
#else
            [[self request] mutableCopy];
#endif
            // we need to mark this request with our header so we know not to handle it in +[NSURLProtocol canInitWithRequest:].
            [connectionRequest setValue:SKCachingURLHeader forHTTPHeaderField:SKCachingURLHeader];
            NSURLConnection *connection = [NSURLConnection connectionWithRequest:connectionRequest
                                                                        delegate:self];
            [self setConnection:connection];
        }
    }
    else {
        SKCachedData *cache = [NSKeyedUnarchiver unarchiveObjectWithFile:[self cachePathForRequest:[self request]]];
        if (cache) {
            NSData *data = [cache data];
            NSURLResponse *response = [cache response];
            NSURLRequest *redirectRequest = [cache redirectRequest];
            if (redirectRequest) {
                [[self client] URLProtocol:self wasRedirectedToRequest:redirectRequest redirectResponse:response];
            } else {
                [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed]; // we handle caching ourselves.
                [[self client] URLProtocol:self didLoadData:data];
                [[self client] URLProtocolDidFinishLoading:self];
            }
        }
        else {
            NSString *cacheKey = [[SDWebImageManager sharedManager] cacheKeyForURL:[[self request] URL]];
            NSData *data = [[SDImageCache sharedImageCache] diskImageDataBySearchingAllPathsForKey:cacheKey];
            
            if (data) {
                NSURLResponse *newResponse = [[NSURLResponse alloc] initWithURL:[self.request URL]
                                                                       MIMEType:nil
                                                          expectedContentLength:data.length
                                                               textEncodingName:nil];
                [[self client] URLProtocol:self didReceiveResponse:newResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed]; // we handle caching ourselves.
                [[self client] URLProtocol:self didLoadData:data];
                [[self client] URLProtocolDidFinishLoading:self];
            }
            else {
                [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]];
            }
        }
    }
}

- (void)stopLoading
{
    [[self connection] cancel];
}

// NSURLConnection delegates (generally we pass these on to our client)

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
{
    // Thanks to Nick Dowell https://gist.github.com/1885821
    if (response != nil) {
        NSMutableURLRequest *redirectableRequest =
#if WORKAROUND_MUTABLE_COPY_LEAK
        [request mutableCopyWorkaround];
#else
        [request mutableCopy];
#endif
        // We need to remove our header so we know to handle this request and cache it.
        // There are 3 requests in flight: the outside request, which we handled, the internal request,
        // which we marked with our header, and the redirectableRequest, which we're modifying here.
        // The redirectable request will cause a new outside request from the NSURLProtocolClient, which
        // must not be marked with our header.
        [redirectableRequest setValue:nil forHTTPHeaderField:SKCachingURLHeader];
        
        NSString *cachePath = [self cachePathForRequest:[self request]];
        SKCachedData *cache = [SKCachedData new];
        [cache setResponse:response];
        [cache setData:[self data]];
        [cache setRedirectRequest:redirectableRequest];
        [NSKeyedArchiver archiveRootObject:cache toFile:cachePath];
        [[self client] URLProtocol:self wasRedirectedToRequest:redirectableRequest redirectResponse:response];
        return redirectableRequest;
    } else {
        return request;
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [[self client] URLProtocol:self didLoadData:data];
    [self appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [[self client] URLProtocol:self didFailWithError:error];
    [self setConnection:nil];
    [self setData:nil];
    [self setResponse:nil];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [self setResponse:response];
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];  // We cache ourselves.
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [[self client] URLProtocolDidFinishLoading:self];
    
    NSString *cachePath = [self cachePathForRequest:[self request]];
    SKCachedData *cache = [SKCachedData new];
    [cache setResponse:[self response]];
    [cache setData:[self data]];
    [NSKeyedArchiver archiveRootObject:cache toFile:cachePath];
    
    [self setConnection:nil];
    [self setData:nil];
    [self setResponse:nil];
}

- (BOOL) useCache
{
    if ([SKCachingURLProtocol isPictureExtension:[[[self request] URL] pathExtension]]) {
        BOOL cacheInSDWebSys = [[SDWebImageManager sharedManager] cachedImageExistsForURL:[[self request] URL]];
        
        if (cacheInSDWebSys) {
            return YES;
        }
    }
    else {
        
#if CACHING_ONLY_IMAGE
        return NO;
#else

        //if network is't reachability, use the cache
        if (![SKCachingURLProtocol networkReachability]) {
            SKCachedData *cache = [NSKeyedUnarchiver unarchiveObjectWithFile:[self cachePathForRequest:[self request]]];
            if (cache) {
                return YES;
            }
        }
        
#endif
    }
    
    return NO;
}

- (void)appendData:(NSData *)newData
{
    if ([self data] == nil) {
        [self setData:[newData mutableCopy]];
    }
    else {
        [[self data] appendData:newData];
    }
}

+ (NSSet *)supportedSchemes {
    NSSet *supportedSchemes;
    @synchronized(SKCachingSupportedSchemesMonitor)
    {
        supportedSchemes = SKCachingSupportedSchemes;
    }
    return supportedSchemes;
}

+ (void)setSupportedSchemes:(NSSet *)supportedSchemes
{
    @synchronized(SKCachingSupportedSchemesMonitor)
    {
        SKCachingSupportedSchemes = supportedSchemes;
    }
}

@end

static NSString *const kDataKey = @"data";
static NSString *const kResponseKey = @"response";
static NSString *const kRedirectRequestKey = @"redirectRequest";

@implementation SKCachedData
@synthesize data = data_;
@synthesize response = response_;
@synthesize redirectRequest = redirectRequest_;

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self data] forKey:kDataKey];
    [aCoder encodeObject:[self response] forKey:kResponseKey];
    [aCoder encodeObject:[self redirectRequest] forKey:kRedirectRequestKey];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self != nil) {
        [self setData:[aDecoder decodeObjectForKey:kDataKey]];
        [self setResponse:[aDecoder decodeObjectForKey:kResponseKey]];
        [self setRedirectRequest:[aDecoder decodeObjectForKey:kRedirectRequestKey]];
    }
    
    return self;
}

@end

#if WORKAROUND_MUTABLE_COPY_LEAK
@implementation NSURLRequest(MutableCopyWorkaround)

- (id) mutableCopyWorkaround {
    NSMutableURLRequest *mutableURLRequest = [[NSMutableURLRequest alloc] initWithURL:[self URL]
                                                                          cachePolicy:[self cachePolicy]
                                                                      timeoutInterval:[self timeoutInterval]];
    [mutableURLRequest setAllHTTPHeaderFields:[self allHTTPHeaderFields]];
    if ([self HTTPBodyStream]) {
        [mutableURLRequest setHTTPBodyStream:[self HTTPBodyStream]];
    } else {
        [mutableURLRequest setHTTPBody:[self HTTPBody]];
    }
    [mutableURLRequest setHTTPMethod:[self HTTPMethod]];
    
    return mutableURLRequest;
}

@end
#endif
