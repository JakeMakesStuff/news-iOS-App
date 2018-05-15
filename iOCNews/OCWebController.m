//
//  WebController.m
//  iOCNews
//

/************************************************************************
 
 Copyright 2012-2013 Peter Hedlund peter.hedlund@me.com
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 *************************************************************************/

#import "OCWebController.h"
#import "readable.h"
#import "HTMLParser.h"
#import "TUSafariActivity.h"
#import "OCAPIClient.h"
#import "OCNewsHelper.h"
#import <QuartzCore/QuartzCore.h>
#import "OCSharingProvider.h"
#import "PHPrefViewController.h"
#import "UIColor+PHColor.h"

#define MIN_FONT_SIZE (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 11 : 9)
#define MAX_FONT_SIZE 30

#define MIN_LINE_HEIGHT 1.2f
#define MAX_LINE_HEIGHT 2.6f

#define MIN_WIDTH (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 380 : 150)
#define MAX_WIDTH (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 700 : 300)

const int SWIPE_NEXT = 0;
const int SWIPE_PREVIOUS = 1;

@interface OCWebController () <WKNavigationDelegate, WKUIDelegate, PHPrefViewControllerDelegate, UIPopoverPresentationControllerDelegate> {
    BOOL _menuIsOpen;
    int _swipeDirection;
    BOOL loadingComplete;
    BOOL loadingSummary;
}

@property (strong, nonatomic) IBOutlet WKWebView *webView;
@property (assign, nonatomic) BOOL isVisible;
@property (nonatomic, strong, readonly) PHPrefViewController *settingsViewController;
@property (nonatomic, strong, readonly) UIPopoverPresentationController *settingsPresentationController;

- (void)configureView;
- (void) writeAndLoadHtml:(NSString*)html;
- (NSString *)replaceYTIframe:(NSString *)html;
- (NSString *)extractYoutubeVideoID:(NSString *)urlYoutube;
- (UIColor*)myBackgroundColor;

@end

@implementation OCWebController

@synthesize menuBarButtonItem;
@synthesize backBarButtonItem, forwardBarButtonItem, refreshBarButtonItem, stopBarButtonItem, actionBarButtonItem, textBarButtonItem, starBarButtonItem, unstarBarButtonItem;
@synthesize item = _item;
@synthesize settingsViewController;
@synthesize settingsPresentationController;

#pragma mark - Managing the detail item

- (void)configureView
{
    @try {
        if (self.item) {
            self.automaticallyAdjustsScrollViewInsets = NO;
            
            [self updateNavigationItemTitle];
            
            Feed *feed = [[OCNewsHelper sharedHelper] feedWithId:self.item.feedId];
            
            if (feed.preferWebValue) {
                if (feed.useReaderValue) {
                    if (self.item.readable) {
                        [self writeAndLoadHtml:self.item.readable];
                    } else {
                        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
                        [[OCAPIClient sharedClient] GET:self.item.url parameters:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                            NSString *html;
                            if (responseObject) {
                                html = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
                                char *article;
                                article = readable([html cStringUsingEncoding:NSUTF8StringEncoding],
                                                   [[[task.response URL] absoluteString] cStringUsingEncoding:NSUTF8StringEncoding],
                                                   "UTF-8",
                                                   READABLE_OPTIONS_DEFAULT);
                                if (article == NULL) {
                                    html = @"<p style='color: #CC6600;'><i>(An article could not be extracted. Showing summary instead.)</i></p>";
                                    html = [html stringByAppendingString:self.item.body];
                                } else {
                                    html = [NSString stringWithCString:article encoding:NSUTF8StringEncoding];
                                    html = [self fixRelativeUrl:html
                                                  baseUrlString:[NSString stringWithFormat:@"%@://%@/%@", [[task.response URL] scheme], [[task.response URL] host], [[task.response URL] path]]];
                                }
                                self.item.readable = html;
                                [[OCNewsHelper sharedHelper] saveContext];
                            } else {
                                html = @"<p style='color: #CC6600;'><i>(An article could not be extracted. Showing summary instead.)</i></p>";
                                html = [html stringByAppendingString:self.item.body];
                            }
                            [self writeAndLoadHtml:html];
                            
                        } failure:^(NSURLSessionDataTask *task, NSError *error) {
                            NSString *html = @"<p style='color: #CC6600;'><i>(There was an error downloading the article. Showing summary instead.)</i></p>";
                            if (self.item.body != nil) {
                                html = [html stringByAppendingString:self.item.body];
                            }
                            [self writeAndLoadHtml:html];
                        }];
                    }
                } else {
                    loadingSummary = NO;
                    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.item.url]]];
                }
            } else {
                NSString *html = self.item.body;
                NSURL *itemURL = [NSURL URLWithString:self.item.url];
                NSString *baseString = [NSString stringWithFormat:@"%@://%@", [itemURL scheme], [itemURL host]];
                if ([baseString rangeOfString:@"youtu"].location != NSNotFound) {
                    if ([html rangeOfString:@"iframe"].location != NSNotFound) {
                        html = [self createYoutubeItem:self.item];
                    }
                }
                html = [self fixRelativeUrl:html baseUrlString:baseString];
                [self writeAndLoadHtml:html];
            }
        }
        
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        //
    }
}

- (void)writeAndLoadHtml:(NSString *)html {
    html = [self replaceYTIframe:html];
    NSURL *source = [[NSBundle mainBundle] URLForResource:@"rss" withExtension:@"html" subdirectory:nil];
    NSString *objectHtml = [NSString stringWithContentsOfURL:source encoding:NSUTF8StringEncoding error:nil];
    
    NSString *dateText = @"";
    NSNumber *dateNumber = self.item.pubDate;
    if (![dateNumber isKindOfClass:[NSNull class]]) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[dateNumber doubleValue]];
        if (date) {
            NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
            dateFormat.dateStyle = NSDateFormatterMediumStyle;
            dateFormat.timeStyle = NSDateFormatterShortStyle;
            dateText = [dateText stringByAppendingString:[dateFormat stringFromDate:date]];
        }
    }
    
    Feed *feed = [[OCNewsHelper sharedHelper] feedWithId:self.item.feedId];
    if (feed && feed.title) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$FeedTitle$" withString:feed.title];
    }
    if (dateText) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleDate$" withString:dateText];
    }
    if (self.item.title) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleTitle$" withString:self.item.title];
    }
    if (self.item.url) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleLink$" withString:self.item.url];
    }
    NSString *author = self.item.author;
    if (![author isKindOfClass:[NSNull class]]) {
        if (author.length > 0) {
            author = [NSString stringWithFormat:@"By %@", author];
        }
    } else {
        author = @"";
    }
    if (author) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleAuthor$" withString:author];
    }
    if (html) {
        objectHtml = [objectHtml stringByReplacingOccurrencesOfString:@"$ArticleSummary$" withString:html];
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *docDir = [paths objectAtIndex:0];
    NSURL *objectSaveURL = [docDir  URLByAppendingPathComponent:@"summary.html"];
    [objectHtml writeToURL:objectSaveURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    loadingComplete = NO;
    loadingSummary = YES;
    [self.webView loadFileURL:objectSaveURL allowingReadAccessToURL:docDir];
}

#pragma mark - View lifecycle

- (void)loadView {
    [super loadView];
    WKWebViewConfiguration *webConfig = [WKWebViewConfiguration new];
    webConfig.allowsInlineMediaPlayback = NO;
    
    _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:webConfig];
    _webView.navigationDelegate = self;
    _webView.UIDelegate = self;
    _webView.opaque = NO;
    _webView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_webView];
    
    _webView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:_webView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:_webView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:_webView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:_webView attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0]];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.isVisible = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationDidChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
    _menuIsOpen = NO;
    self.view.backgroundColor = [UIColor cellBackgroundColor];
    [self writeCss];
    [self configureView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.isVisible = YES;
    [self updateToolbar];
    [self updateNavigationItemTitle];
}

- (void)viewDidDisappear:(BOOL)animated {
    self.isVisible = NO;
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
}

- (void)dealloc
{
    [self.webView stopLoading];
 	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
	return YES;
}

- (IBAction)onMenu:(id)sender {
//    [self.mm_drawerController toggleDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (IBAction)doGoBack:(id)sender
{
    if ([[self webView] canGoBack]) {
        [[self webView] goBack];
    }
}

- (IBAction)doGoForward:(id)sender
{
    if ([[self webView] canGoForward]) {
        [[self webView] goForward];
    }
}


- (IBAction)doReload:(id)sender {
    [self.webView reload];
}

- (IBAction)doStop:(id)sender {
    [self.webView stopLoading];
	[self updateToolbar];
}

- (IBAction)doInfo:(id)sender {
    @try {
        NSURL *url = self.webView.URL;
        NSString *subject = self.webView.title;
        if ([[url absoluteString] hasSuffix:@"Documents/summary.html"]) {
            url = [NSURL URLWithString:self.item.url];
            subject = self.item.title;
        }
        if (!url) {
            return;
        }
        
        TUSafariActivity *sa = [[TUSafariActivity alloc] init];
        NSArray *activities = @[sa];
        
        OCSharingProvider *sharingProvider = [[OCSharingProvider alloc] initWithPlaceholderItem:url subject:subject];
        
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[sharingProvider] applicationActivities:activities];
        activityViewController.modalPresentationStyle = UIModalPresentationPopover;
        [self presentViewController:activityViewController animated:YES completion:nil];
        // Get the popover presentation controller and configure it.
        UIPopoverPresentationController *presentationController = [activityViewController popoverPresentationController];
        presentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        presentationController.barButtonItem = self.actionBarButtonItem;
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        //
    }
}

- (IBAction)doPreferences:(id)sender {
    settingsPresentationController = self.settingsViewController.popoverPresentationController;
    settingsPresentationController.delegate = self;
    settingsPresentationController.barButtonItem = self.textBarButtonItem;
    settingsPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    settingsPresentationController.backgroundColor = [UIColor popoverBackgroundColor];
    [self presentViewController:self.settingsViewController animated:YES completion:nil];
}

- (IBAction)doStar:(id)sender {
    if ([sender isEqual:self.starBarButtonItem]) {
        self.item.starredValue = YES;
        [[OCNewsHelper sharedHelper] starItemOffline:self.item.myId];
    }
    if ([sender isEqual:self.unstarBarButtonItem]) {
        self.item.starredValue = NO;
        [[OCNewsHelper sharedHelper] unstarItemOffline:self.item.myId];
    }
    [self updateToolbar];
}

#pragma mark - WKWbView delegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if ([self.webView.URL.scheme isEqualToString:@"file"] || [self.webView.URL.scheme hasPrefix:@"itms"]) {
        if ([navigationAction.request.URL.absoluteString rangeOfString:@"itunes.apple.com"].location != NSNotFound) {
            [[UIApplication sharedApplication] openURL:navigationAction.request.URL];
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }

    if (navigationAction.navigationType != WKNavigationTypeOther) {
        loadingSummary = [navigationAction.request.URL.scheme isEqualToString:@"file"] || [navigationAction.request.URL.scheme isEqualToString:@"about"];
    }
    decisionHandler(WKNavigationActionPolicyAllow);
    loadingComplete = NO;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    [self updateToolbar];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [self updateToolbar];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [self updateToolbar];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [webView evaluateJavaScript:@"document.readyState" completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
        if (response != nil) {
            if ([response isEqualToString:@"complete"]) {
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                loadingComplete = YES;
                [self updateNavigationItemTitle];
            }
        }
        [self updateToolbar];
    }];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    
    return nil;
}

- (BOOL)isShowingASummary {
    BOOL result = NO;
    if (self.webView) {
        result = [self.webView.URL.scheme isEqualToString:@"file"] || [self.webView.URL.scheme isEqualToString:@"about"];
    }
    return result;
}

#pragma mark - Toolbar buttons

- (UIBarButtonItem *)menuBarButtonItem {
    if (!menuBarButtonItem) {
        menuBarButtonItem = [[UIBarButtonItem alloc] initWithImage:nil style:UIBarButtonItemStyleDone target:nil action:nil];
        menuBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return menuBarButtonItem;
}

- (UIBarButtonItem *)backBarButtonItem {
    
    if (!backBarButtonItem) {
        backBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"back"] style:UIBarButtonItemStylePlain target:self action:@selector(doGoBack:)];
        backBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return backBarButtonItem;
}

- (UIBarButtonItem *)forwardBarButtonItem {
    
    if (!forwardBarButtonItem) {
        forwardBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"forward"] style:UIBarButtonItemStylePlain target:self action:@selector(doGoForward:)];
        forwardBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return forwardBarButtonItem;
}

- (UIBarButtonItem *)refreshBarButtonItem {
    
    if (!refreshBarButtonItem) {
        refreshBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(doReload:)];
    }
    
    return refreshBarButtonItem;
}

- (UIBarButtonItem *)stopBarButtonItem {
    
    if (!stopBarButtonItem) {
        stopBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(doStop:)];
    }
    return stopBarButtonItem;
}

- (UIBarButtonItem *)actionBarButtonItem {
    if (!actionBarButtonItem) {
        actionBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(doInfo:)];
    }
    return actionBarButtonItem;
}

- (UIBarButtonItem *)textBarButtonItem {
    
    if (!textBarButtonItem) {
        textBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"menu"] style:UIBarButtonItemStylePlain target:self action:@selector(doPreferences:)];
        textBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return textBarButtonItem;
}

- (UIBarButtonItem *)starBarButtonItem {
    if (!starBarButtonItem) {
        starBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"star_open"] style:UIBarButtonItemStylePlain target:self action:@selector(doStar:)];
        starBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return starBarButtonItem;
}

- (UIBarButtonItem *)unstarBarButtonItem {
    if (!unstarBarButtonItem) {
        unstarBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"star_filled"] style:UIBarButtonItemStylePlain target:self action:@selector(doStar:)];
        unstarBarButtonItem.imageInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    }
    return unstarBarButtonItem;
}

- (PHPrefViewController *)settingsViewController {
    if (!settingsViewController) {
        settingsViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"preferences"];
        settingsViewController.preferredContentSize = CGSizeMake(220, 245);
        settingsViewController.modalPresentationStyle = UIModalPresentationPopover;
        settingsViewController.delegate = self;
    }
    return settingsViewController;
}

#pragma mark - Toolbar

- (void)updateToolbar {
    if (self.isVisible) {
        self.backBarButtonItem.enabled = self.webView.canGoBack;
        self.forwardBarButtonItem.enabled = self.webView.canGoForward;
        UIBarButtonItem *refreshStopBarButtonItem = loadingComplete ? self.refreshBarButtonItem : self.stopBarButtonItem;
        if ((self.item != nil)) {
            self.actionBarButtonItem.enabled = loadingComplete;
            self.textBarButtonItem.enabled = loadingComplete;
            self.starBarButtonItem.enabled = loadingComplete;
            self.unstarBarButtonItem.enabled = loadingComplete;
            refreshStopBarButtonItem.enabled = YES;
        } else {
            self.actionBarButtonItem.enabled = NO;
            self.textBarButtonItem.enabled = NO;
            self.starBarButtonItem.enabled = NO;
            self.unstarBarButtonItem.enabled = NO;
            refreshStopBarButtonItem.enabled = NO;
        }
        UIBarButtonItem *modeButton = self.parentViewController.parentViewController.splitViewController.displayModeButtonItem;
        self.parentViewController.parentViewController.navigationItem.leftBarButtonItems = @[modeButton, self.backBarButtonItem, self.forwardBarButtonItem, refreshStopBarButtonItem];
        self.parentViewController.parentViewController.navigationItem.leftItemsSupplementBackButton = YES;
        self.parentViewController.parentViewController.navigationItem.rightBarButtonItems = @[self.textBarButtonItem, self.actionBarButtonItem];
    }
}

- (NSString *) fixRelativeUrl:(NSString *)htmlString baseUrlString:(NSString*)base {
    __block NSString *result = [htmlString copy];
    NSError *error = nil;
    HTMLParser *parser = [[HTMLParser alloc] initWithString:htmlString error:&error];
    
    if (error) {
        //NSLog(@"Error: %@", error);
        return result;
    }

    //parse body
    HTMLNode *bodyNode = [parser body];

    NSArray *inputNodes = [bodyNode findChildTags:@"img"];
    [inputNodes enumerateObjectsUsingBlock:^(HTMLNode *inputNode, NSUInteger idx, BOOL *stop) {
        if (inputNode) {
            NSString *src = [inputNode getAttributeNamed:@"src"];
            if (src != nil) {
                NSURL *url = [NSURL URLWithString:src relativeToURL:[NSURL URLWithString:base]];
                if (url != nil) {
                    NSString *newSrc = [url absoluteString];
                    result = [result stringByReplacingOccurrencesOfString:src withString:newSrc];
                }
            }
        }
    }];
    
    inputNodes = [bodyNode findChildTags:@"a"];
    [inputNodes enumerateObjectsUsingBlock:^(HTMLNode *inputNode, NSUInteger idx, BOOL *stop) {
        if (inputNode) {
            NSString *src = [inputNode getAttributeNamed:@"href"];
            if (src != nil) {
                NSURL *url = [NSURL URLWithString:src relativeToURL:[NSURL URLWithString:base]];
                if (url != nil) {
                    NSString *newSrc = [url absoluteString];
                    result = [result stringByReplacingOccurrencesOfString:src withString:newSrc];
                }
                
            }
        }
    }];
    
    return result;
}

#pragma mark - Reader settings

- (void) writeCss
{
    NSBundle *appBundle = [NSBundle mainBundle];
    NSURL *cssTemplateURL = [appBundle URLForResource:@"rss" withExtension:@"css" subdirectory:nil];
    NSString *cssTemplate = [NSString stringWithContentsOfURL:cssTemplateURL encoding:NSUTF8StringEncoding error:nil];
    
    long fontSize =[[NSUserDefaults standardUserDefaults] integerForKey:@"FontSize"];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$FONTSIZE$" withString:[NSString stringWithFormat:@"%ldpx", fontSize]];

    CGSize screenSize = [UIScreen mainScreen].nativeBounds.size;
    NSInteger margin =[[NSUserDefaults standardUserDefaults] integerForKey:@"MarginPortrait"];
    double currentWidth = (screenSize.width / [UIScreen mainScreen].scale) * ((double)margin / 100);
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$MARGIN$" withString:[NSString stringWithFormat:@"%ldpx", (long)currentWidth]];
    
    NSInteger marginLandscape = [[NSUserDefaults standardUserDefaults] integerForKey:@"MarginLandscape"];
    double currentWidthLandscape = (screenSize.height / [UIScreen mainScreen].scale) * ((double)marginLandscape / 100);
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$MARGIN_LANDSCAPE$" withString:[NSString stringWithFormat:@"%ldpx", (long)currentWidthLandscape]];

    double lineHeight =[[NSUserDefaults standardUserDefaults] doubleForKey:@"LineHeight"];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$LINEHEIGHT$" withString:[NSString stringWithFormat:@"%fem", lineHeight]];
    
    NSArray *backgrounds = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Backgrounds"];
    long backgroundIndex =[[NSUserDefaults standardUserDefaults] integerForKey:@"CurrentTheme"];
    NSString *background = [backgrounds objectAtIndex:backgroundIndex];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$BACKGROUND$" withString:background];
    
    NSArray *colors = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Colors"];
    NSString *color = [colors objectAtIndex:backgroundIndex];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$COLOR$" withString:color];
    
    NSArray *colorsLink = [[NSUserDefaults standardUserDefaults] arrayForKey:@"ColorsLink"];
    NSString *colorLink = [colorsLink objectAtIndex:backgroundIndex];
    cssTemplate = [cssTemplate stringByReplacingOccurrencesOfString:@"$COLORLINK$" withString:colorLink];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *docDir = [paths objectAtIndex:0];
    
    [cssTemplate writeToURL:[docDir URLByAppendingPathComponent:@"rss.css"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (UIColor*)myBackgroundColor {
    NSArray *backgrounds = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Backgrounds"];
    long backgroundIndex =[[NSUserDefaults standardUserDefaults] integerForKey:@"CurrentTheme"];
    NSString *background = [backgrounds objectAtIndex:backgroundIndex];
    UIColor *backColor = [UIColor blackColor];
    if ([background isEqualToString:@"#FFFFFF"]) {
        backColor = [UIColor whiteColor];
    } else if ([background isEqualToString:@"#F5EFDC"]) {
        backColor = [UIColor colorWithRed:0.96 green:0.94 blue:0.86 alpha:1];
    }
    return backColor;
}

-(void) settingsChanged:(NSString *)setting newValue:(NSUInteger)value {
    BOOL starred = [[NSUserDefaults standardUserDefaults] boolForKey:@"Starred"];
    if (starred != self.item.starredValue) {
        self.item.starredValue = starred;
        if (starred) {
            [[OCNewsHelper sharedHelper] starItemOffline:self.item.myId];
        } else {
            [[OCNewsHelper sharedHelper] unstarItemOffline:self.item.myId];
        }
    }
    
    BOOL unread = [[NSUserDefaults standardUserDefaults] boolForKey:@"Unread"];
    if (unread != self.item.unreadValue) {
        self.item.unreadValue = unread;
        if (unread) {
            [[OCNewsHelper sharedHelper] markItemUnreadOffline:self.item.myId];
        } else {
            [[OCNewsHelper sharedHelper] markItemsReadOffline:[NSMutableSet setWithObject:self.item.myId]];
        }
    }

    [self writeCss];
    if ([self webView] != nil) {
        self.webView.scrollView.backgroundColor = [self myBackgroundColor];
        [self.webView reload];
    }
}

- (BOOL)starred {
    return self.item.starredValue;
}


- (BOOL)unread {
    return self.item.unreadValue;
}


- (void)updateNavigationItemTitle
{
    if (self.isVisible) {
        if ([UIScreen mainScreen].bounds.size.width > 414) { //should cover any phone in landscape and iPad
            if (self.item != nil) {
                if (!loadingComplete && loadingSummary) {
                    self.parentViewController.parentViewController.navigationItem.title = self.item.title;
                } else {
                    self.parentViewController.parentViewController.navigationItem.title = self.webView.title;
                }
            }
        } else {
            self.parentViewController.parentViewController.navigationItem.title = @"";
        }
    }
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
    [self updateNavigationItemTitle];
}


- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    return UIModalPresentationNone;
}

- (NSString *)createYoutubeItem:(Item *)item {
    __block NSString *result = item.body;
    NSError *error = nil;
    HTMLParser *parser = [[HTMLParser alloc] initWithString:item.body error:&error];
    
    if (error) {
        //        NSLog(@"Error: %@", error);
        return item.body;
    }
    
    //parse body
    HTMLNode *bodyNode = [parser body];
    
    NSArray *inputNodes = [bodyNode findChildTags:@"iframe"];
    [inputNodes enumerateObjectsUsingBlock:^(HTMLNode *inputNode, NSUInteger idx, BOOL *stop) {
        if (inputNode) {
            NSString *videoID = [self extractYoutubeVideoID:item.url];
            if (videoID) {
                //                    NSLog(@"Raw: %@", [inputNode rawContents]);
                
                NSString *height = [inputNode getAttributeNamed:@"height"];
                NSString *width = [inputNode getAttributeNamed:@"width"];
                NSString *heightString = @"";
                NSString *widthString = @"";
                if (height.length > 0) {
                    heightString = [NSString stringWithFormat:@"height=\"%@\"", height];
                }
                if (width.length > 0) {
                    widthString = [NSString stringWithFormat:@"width=\"%@\"", width];
                }
                NSString *embed = [NSString stringWithFormat:@"<embed class=\"yt\" wmode=\"transparent\" style=\"background-color: transparent;\" src=\"http://www.youtube.com/embed/%@\" type=\"text/html\" frameborder=\"0\" %@ %@></embed>", videoID, heightString, widthString];
                result = [result stringByReplacingOccurrencesOfString:[inputNode rawContents] withString:embed];
            }

        }
    }];
    return result;
}

- (NSString*)replaceYTIframe:(NSString *)html {
    __block NSString *result = html;
    NSError *error = nil;
    HTMLParser *parser = [[HTMLParser alloc] initWithString:html error:&error];
    
    if (error) {
        //        NSLog(@"Error: %@", error);
        return html;
    }
    
    //parse body
    HTMLNode *bodyNode = [parser body];
    
    NSArray *inputNodes = [bodyNode findChildTags:@"iframe"];
    [inputNodes enumerateObjectsUsingBlock:^(HTMLNode *inputNode, NSUInteger idx, BOOL *stop) {
        if (inputNode) {
            NSString *src = [inputNode getAttributeNamed:@"src"];
            if (src && [src rangeOfString:@"youtu"].location != NSNotFound) {
                NSString *videoID = [self extractYoutubeVideoID:src];
                if (videoID) {
                    //                    NSLog(@"Raw: %@", [inputNode rawContents]);
                    
                    NSString *height = [inputNode getAttributeNamed:@"height"];
                    NSString *width = [inputNode getAttributeNamed:@"width"];
                    NSString *heightString = @"";
                    NSString *widthString = @"";
                    if (height.length > 0) {
                        heightString = [NSString stringWithFormat:@"height=\"%@\"", height];
                    }
                    if (width.length > 0) {
                        widthString = [NSString stringWithFormat:@"width=\"%@\"", width];
                    }
                    NSString *embed = [NSString stringWithFormat:@"<embed id=\"yt\" src=\"http://www.youtube.com/embed/%@\" type=\"text/html\" frameborder=\"0\" %@ %@></embed>", videoID, heightString, widthString];
                    result = [result stringByReplacingOccurrencesOfString:[inputNode rawContents] withString:embed];
                }
            }
            if (src && [src rangeOfString:@"vimeo"].location != NSNotFound) {
                NSString *videoID = [self extractVimeoVideoID:src];
                if (videoID) {
                    NSString *height = [inputNode getAttributeNamed:@"height"];
                    NSString *width = [inputNode getAttributeNamed:@"width"];
                    NSString *heightString = @"";
                    NSString *widthString = @"";
                    if (height.length > 0) {
                        heightString = [NSString stringWithFormat:@"height=\"%@\"", height];
                    }
                    if (width.length > 0) {
                        widthString = [NSString stringWithFormat:@"width=\"%@\"", width];
                    }
                    NSString *embed = [NSString stringWithFormat:@"<iframe id=\"vimeo\" src=\"http://player.vimeo.com/video/%@\" type=\"text/html\" frameborder=\"0\" %@ %@></iframe>", videoID, heightString, widthString];
                    result = [result stringByReplacingOccurrencesOfString:[inputNode rawContents] withString:embed];
                }
            }
        }
    }];
    
    return result;
}


//based on https://gist.github.com/rais38/4683817
/**
 @see https://devforums.apple.com/message/705665#705665
 extractYoutubeVideoID: works for the following URL formats:
 www.youtube.com/v/VIDEOID
 www.youtube.com?v=VIDEOID
 www.youtube.com/watch?v=WHsHKzYOV2E&feature=youtu.be
 www.youtube.com/watch?v=WHsHKzYOV2E
 youtu.be/KFPtWedl7wg_U923
 www.youtube.com/watch?feature=player_detailpage&v=WHsHKzYOV2E#t=31s
 youtube.googleapis.com/v/WHsHKzYOV2E
 www.youtube.com/embed/VIDEOID
 */

- (NSString *)extractYoutubeVideoID:(NSString *)urlYoutube {
    NSString *regexString = @"(?<=v(=|/))([-a-zA-Z0-9_]+)|(?<=youtu.be/)([-a-zA-Z0-9_]+)|(?<=embed/)([-a-zA-Z0-9_]+)";
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:NSRegularExpressionCaseInsensitive error:&error];
    NSRange rangeOfFirstMatch = [regex rangeOfFirstMatchInString:urlYoutube options:0 range:NSMakeRange(0, [urlYoutube length])];
    if(!NSEqualRanges(rangeOfFirstMatch, NSMakeRange(NSNotFound, 0))) {
        NSString *substringForFirstMatch = [urlYoutube substringWithRange:rangeOfFirstMatch];
        return substringForFirstMatch;
    }
    
    return nil;
}

//based on http://stackoverflow.com/a/16841070/2036378
- (NSString *)extractVimeoVideoID:(NSString *)urlVimeo {
    NSString *regexString = @"([0-9]{2,11})"; // @"(https?://)?(www.)?(player.)?vimeo.com/([a-z]*/)*([0-9]{6,11})[?]?.*";
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:NSRegularExpressionCaseInsensitive error:&error];
    NSRange rangeOfFirstMatch = [regex rangeOfFirstMatchInString:urlVimeo options:0 range:NSMakeRange(0, [urlVimeo length])];
    if(!NSEqualRanges(rangeOfFirstMatch, NSMakeRange(NSNotFound, 0))) {
        NSString *substringForFirstMatch = [urlVimeo substringWithRange:rangeOfFirstMatch];
        return substringForFirstMatch;
    }
    
    return nil;
}

@end
