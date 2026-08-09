#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>

#import "GlowLinkRouting.h"

static NSString *GlowLinkAttributedText(NSArray *items) {
    for (NSExtensionItem *item in items) {
        if (item.attributedContentText.string.length > 0) {
            return item.attributedContentText.string;
        }
    }
    return @"";
}

@interface GlowLinkShareViewController : UIViewController
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *openButton;
@property(nonatomic, strong, nullable) NSURL *pendingURL;
@property(nonatomic, assign) BOOL started;
@end

@implementation GlowLinkShareViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.text = @"Open in Facebook Glow";

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.text = @"Reading the shared Facebook link...";

    self.openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.openButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.openButton setTitle:@"Open Facebook Glow" forState:UIControlStateNormal];
    self.openButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.openButton.hidden = YES;
    [self.openButton addTarget:self action:@selector(openPendingURL) forControlEvents:UIControlEventTouchUpInside];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, self.statusLabel, self.openButton, cancelButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18.0;
    stack.alignment = UIStackViewAlignmentFill;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.started) {
        self.started = YES;
        [self resolveSharedURL];
    }
}

- (void)resolveSharedURL {
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *provider in item.attachments) {
            if ([provider hasItemConformingToTypeIdentifier:UTTypeURL.identifier]) {
                [provider loadItemForTypeIdentifier:UTTypeURL.identifier options:nil completionHandler:^(id<NSSecureCoding> value, NSError *error) {
                    (void)error;
                    id object = (id)value;
                    NSURL *url = [object isKindOfClass:NSURL.class] ? (NSURL *)object : nil;
                    [self handleRoutedURL:GlowLinkURLForFacebookURL(url)];
                }];
                return;
            }
            if ([provider hasItemConformingToTypeIdentifier:UTTypePlainText.identifier]) {
                [provider loadItemForTypeIdentifier:UTTypePlainText.identifier options:nil completionHandler:^(id<NSSecureCoding> value, NSError *error) {
                    (void)error;
                    id object = (id)value;
                    NSString *text = [object isKindOfClass:NSString.class] ? (NSString *)object : nil;
                    [self handleRoutedURL:GlowLinkURLFromText(text ?: @"")];
                }];
                return;
            }
        }
    }

    [self handleRoutedURL:GlowLinkURLFromText(GlowLinkAttributedText(self.extensionContext.inputItems))];
}

- (void)handleRoutedURL:(NSURL *)routedURL {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (routedURL == nil) {
            self.statusLabel.text = @"This item does not contain a supported Facebook link.";
            self.openButton.hidden = YES;
            return;
        }
        self.pendingURL = routedURL;
        self.statusLabel.text = @"Ready to open this link through Safari's Facebook Glow router.";
        self.openButton.hidden = NO;
        [self openPendingURL];
    });
}

- (void)openPendingURL {
    NSURL *url = self.pendingURL;
    if (url == nil) {
        return;
    }
    self.statusLabel.text = @"Opening the Facebook link...";
    self.openButton.enabled = NO;

    [self.extensionContext openURL:url completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self complete];
            } else {
                [self openThroughHostApplication:url];
            }
        });
    }];
}

- (void)openThroughHostApplication:(NSURL *)url {
    Class applicationClass = NSClassFromString(@"UIApplication");
    SEL sharedSelector = NSSelectorFromString(@"sharedApplication");
    SEL openSelector = NSSelectorFromString(@"openURL:options:completionHandler:");
    if (applicationClass == Nil || ![applicationClass respondsToSelector:sharedSelector]) {
        [self showOpenFailure];
        return;
    }

    id (*sendShared)(id, SEL) = (void *)objc_msgSend;
    id application = sendShared(applicationClass, sharedSelector);
    if (![application respondsToSelector:openSelector]) {
        [self showOpenFailure];
        return;
    }

    void (*sendOpen)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL)) = (void *)objc_msgSend;
    sendOpen(application, openSelector, url, @{}, ^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self complete];
            } else {
                [self showOpenFailure];
            }
        });
    });
}

- (void)showOpenFailure {
    self.statusLabel.text = @"iOS blocked the app handoff. Tap Open Facebook Glow to retry.";
    self.openButton.enabled = YES;
    self.openButton.hidden = NO;
}

- (void)complete {
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (void)cancel {
    NSError *error = [NSError errorWithDomain:@"com.facebook.GlowLinkShare"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cancelled by user"}];
    [self.extensionContext cancelRequestWithError:error];
}

@end
