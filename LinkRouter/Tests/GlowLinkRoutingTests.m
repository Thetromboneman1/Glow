#import <Foundation/Foundation.h>

#import "../Sources/GlowLinkRouting.h"

static void AssertEqual(NSString *name, NSString *actual, NSString *expected) {
    if ((actual == nil && expected != nil) || ![actual isEqualToString:expected]) {
        NSLog(@"FAIL %@ expected=%@ actual=%@", name, expected, actual);
        exit(1);
    }
}

static void AssertNil(NSString *name, id value) {
    if (value != nil) {
        NSLog(@"FAIL %@ expected nil actual=%@", name, value);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        AssertEqual(@"reel",
                    GlowLinkURLForFacebookURL([NSURL URLWithString:@"https://www.facebook.com/reel/123?mibextid=abc"]).absoluteString,
                    @"https://www.facebook.com/reel/123?mibextid=abc");
        AssertEqual(@"watch short link",
                    GlowLinkURLForFacebookURL([NSURL URLWithString:@"https://fb.watch/example/"]).absoluteString,
                    @"https://fb.watch/example/");
        AssertEqual(@"text extraction",
                    GlowLinkURLFromText(@"See https://facebook.com/groups/123/posts/456").absoluteString,
                    @"https://facebook.com/groups/123/posts/456");

        AssertNil(@"lookalike host", GlowLinkURLForFacebookURL([NSURL URLWithString:@"https://evilfacebook.com/reel/1"]));
        AssertNil(@"suffix attack", GlowLinkURLForFacebookURL([NSURL URLWithString:@"https://facebook.com.evil.example/reel/1"]));
        AssertNil(@"userinfo", GlowLinkURLForFacebookURL([NSURL URLWithString:@"https://user@facebook.com/reel/1"]));
        AssertNil(@"port", GlowLinkURLForFacebookURL([NSURL URLWithString:@"https://facebook.com:444/reel/1"]));
        AssertNil(@"custom scheme", GlowLinkURLForFacebookURL([NSURL URLWithString:@"javascript://facebook.com/alert(1)"]));
        AssertNil(@"no Facebook URL", GlowLinkURLFromText(@"https://example.com/not-facebook"));
        NSLog(@"PASS GlowLinkRoutingTests");
    }
    return 0;
}
