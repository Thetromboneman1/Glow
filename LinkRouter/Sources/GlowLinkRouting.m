#import "GlowLinkRouting.h"

static NSArray<NSString *> *GlowLinkAllowedDomains(void) {
    static NSArray<NSString *> *domains;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        domains = @[
            @"facebook.com",
            @"fb.com",
            @"fb.me",
            @"fb.watch",
            @"fbwat.ch"
        ];
    });
    return domains;
}

BOOL GlowLinkHostIsAllowed(NSString *host) {
    NSString *normalized = host.lowercaseString;
    if (normalized.length == 0) {
        return NO;
    }

    for (NSString *domain in GlowLinkAllowedDomains()) {
        if ([normalized isEqualToString:domain] ||
            [normalized hasSuffix:[@"." stringByAppendingString:domain]]) {
            return YES;
        }
    }
    return NO;
}

NSURL *GlowLinkURLForFacebookURL(NSURL *inputURL) {
    if (inputURL == nil || inputURL.user.length > 0 || inputURL.password.length > 0 ||
        inputURL.port != nil || !GlowLinkHostIsAllowed(inputURL.host ?: @"")) {
        return nil;
    }

    NSString *scheme = inputURL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) {
        return nil;
    }
    return inputURL;
}

NSURL *GlowLinkURLFromText(NSString *text) {
    if (text.length == 0) {
        return nil;
    }

    NSError *error = nil;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
    if (detector == nil || error != nil) {
        return nil;
    }

    __block NSURL *result = nil;
    [detector enumerateMatchesInString:text
                               options:0
                                 range:NSMakeRange(0, text.length)
                            usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        (void)flags;
        NSURL *candidate = GlowLinkURLForFacebookURL(match.URL);
        if (candidate != nil) {
            result = candidate;
            *stop = YES;
        }
    }];
    return result;
}
