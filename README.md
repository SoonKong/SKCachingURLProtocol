# SKCachingURLProtocol

  SKCachingURLProtocol use the SDWebImage to offline all the image datas.  So you can use
      the offline image in web or anywhere else.
  (We have avoiding confrontations between SDWebImage and the NSURLProtocol. So you needn't to handling the repeated image downloading)

  A quick rundown of how to use it:

  1. To build, you will need the Reachability code from Apple (included). That requires that you link with
    `SystemConfiguration.framework` and `SDWebImage`(https://github.com/rs/SDWebImage).

  2. At some point early in the program (application:didFinishLaunchingWithOptions:),
    call the following:

      `[NSURLProtocol registerClass:[SKCachingURLProtocol class]];`

  3. There is no step 3.


  # NOTE: It's make from RNCachingURLProtocol. For more details see
     https://github.com/rnapier/RNCachingURLProtocol
