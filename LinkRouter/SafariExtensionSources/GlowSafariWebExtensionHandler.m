#import <Foundation/Foundation.h>

@interface GlowSafariWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation GlowSafariWebExtensionHandler

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    [context completeRequestReturningItems:context.inputItems completionHandler:nil];
}

@end
