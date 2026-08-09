#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL GlowLinkHostIsAllowed(NSString *host);
FOUNDATION_EXPORT NSURL * _Nullable GlowLinkURLForFacebookURL(NSURL *inputURL);
FOUNDATION_EXPORT NSURL * _Nullable GlowLinkURLFromText(NSString *text);

NS_ASSUME_NONNULL_END
