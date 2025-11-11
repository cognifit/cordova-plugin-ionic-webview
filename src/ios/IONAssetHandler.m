#import "IONAssetHandler.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "CDVWKWebViewEngine.h"

@implementation IONAssetHandler

-(void)setAssetPath:(NSString *)assetPath {
    self.basePath = assetPath;
}

- (instancetype)initWithBasePath:(NSString *)basePath andScheme:(NSString *)scheme {
    self = [super init];
    if (self) {
        _basePath = basePath;
        _scheme = scheme;
    }
    return self;
}

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask
{
    NSString * startPath = @"";
    NSURL * url = urlSchemeTask.request.URL;
    NSString * stringToLoad = url.path;
    NSString * scheme = url.scheme;
    
    if ([scheme isEqualToString:self.scheme]) {
        if ([stringToLoad hasPrefix:@"/_app_file_"]) {
            startPath = [stringToLoad stringByReplacingOccurrencesOfString:@"/_app_file_" withString:@""];
        } else {
            // Base path like ".../www" or ".../www_kids"
            NSString *base = self.basePath ? self.basePath : @"";

            // --- Apply traversal normalization (mirrors Android rules) ---
            NSString *mutableBase = [base copy];
            NSString *mutableReq  = [stringToLoad copy];
            AdjustBaseAndPathForTraversal(&mutableBase, &mutableReq);
            startPath = mutableBase;
            stringToLoad = mutableReq;
          
            if ([stringToLoad isEqualToString:@""] || [url.pathExtension isEqualToString:@""]) {
                startPath = [startPath stringByAppendingString:@"/index.html"];
            } else {
                startPath = [startPath stringByAppendingString:stringToLoad];
            }
        }
    }
    NSError * fileError = nil;
    NSData * data = nil;
    if ([self isMediaExtension:url.pathExtension]) {
        data = [NSData dataWithContentsOfFile:startPath options:NSDataReadingMappedIfSafe error:&fileError];
    }
    if (!data || fileError) {
        data =  [[NSData alloc] initWithContentsOfFile:startPath];
    }
    NSInteger statusCode = 200;
    if (!data) {
        statusCode = 404;
    }
    NSURL * localUrl = [NSURL URLWithString:url.absoluteString];
    NSString * mimeType = [self getMimeType:url.pathExtension];
    id response = nil;
    if (data && [self isMediaExtension:url.pathExtension]) {
        response = [[NSURLResponse alloc] initWithURL:localUrl MIMEType:mimeType expectedContentLength:data.length textEncodingName:nil];
    } else {
        NSDictionary * headers = @{ @"Content-Type" : mimeType, @"Cache-Control": @"no-cache"};
        response = [[NSHTTPURLResponse alloc] initWithURL:localUrl statusCode:statusCode HTTPVersion:nil headerFields:headers];
    }
    
    [urlSchemeTask didReceiveResponse:response];
    [urlSchemeTask didReceiveData:data];
    [urlSchemeTask didFinish];
}

- (void)webView:(nonnull WKWebView *)webView stopURLSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask
{
    NSLog(@"stop");
}

-(NSString *) getMimeType:(NSString *)fileExtension {
    if (fileExtension && ![fileExtension isEqualToString:@""]) {
        NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileExtension, NULL);
        NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);
        return contentType ? contentType : @"application/octet-stream";
    } else {
        return @"text/html";
    }
}

-(BOOL) isMediaExtension:(NSString *) pathExtension {
    NSArray * mediaExtensions = @[@"m4v", @"mov", @"mp4",
                           @"aac", @"ac3", @"aiff", @"au", @"flac", @"m4a", @"mp3", @"wav"];
    if ([mediaExtensions containsObject:pathExtension.lowercaseString]) {
        return YES;
    }
    return NO;
}

/// Rewrites base directory and request path to mirror Android rules.
/// If basePath ends with .../www_something and path starts with /PATH_TRAVERSAL/ -> switch to .../www
/// If basePath ends with .../www and path starts with /PATH_TRAVERSAL_{suffix}/ -> switch to .../www_{suffix}
static void AdjustBaseAndPathForTraversal(NSString **basePathRef, NSString **stringToLoadRef) {
    if (basePathRef == nil || *basePathRef == nil || stringToLoadRef == nil || *stringToLoadRef == nil) return;

    NSString *basePath = *basePathRef;
    NSString *reqPath  = *stringToLoadRef;  // begins with "/..."

    // Extract the current top dir ("www" or "www_kids", etc.)
    NSString *baseDirParent = [basePath stringByDeletingLastPathComponent];
    NSString *top = [basePath lastPathComponent]; // e.g. "www" or "www_kids"

    // Rule A (Android #1 analogue):
    // www_{something}/PATH_TRAVERSAL/{somePath} -> www/{somePath}
    // iOS analogue: if basePath ends with www_{something} AND request starts with /PATH_TRAVERSAL/...
    if ([top hasPrefix:@"www_"] && [reqPath hasPrefix:@"/PATH_TRAVERSAL/"]) {
        // switch to ".../www"
        NSString *newTop = @"www";
        NSString *newBase = [baseDirParent stringByAppendingPathComponent:newTop];

        // strip the "/PATH_TRAVERSAL/" prefix from the request path
        NSString *stripped = [reqPath stringByReplacingOccurrencesOfString:@"/PATH_TRAVERSAL/" withString:@"/"];

        *basePathRef = newBase;
        *stringToLoadRef = stripped;
        return;
    }

    // Rule B (Android #2 analogue):
    // www/PATH_TRAVERSAL_{suffix}/{somePath} -> www_{suffix}/{somePath}
    // iOS analogue: if basePath ends with www AND request matches ^/PATH_TRAVERSAL_([^/]+)/(.+)$
    if ([top isEqualToString:@"www"]) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^/PATH_TRAVERSAL_([^/]+)/(.*)$"
                                                                            options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:reqPath options:0 range:NSMakeRange(0, reqPath.length)];
        if (m) {
            NSRange suffixR = [m rangeAtIndex:1];
            NSRange restR   = [m rangeAtIndex:2];
            NSString *suffix = [reqPath substringWithRange:suffixR];   // e.g. "kids", "clowns"
            NSString *rest   = [reqPath substringWithRange:restR];     // remaining path

            NSString *newTop  = [NSString stringWithFormat:@"www_%@", suffix]; // www_kids, www_clowns, etc.
            NSString *newBase = [baseDirParent stringByAppendingPathComponent:newTop];

            *basePathRef = newBase;
            *stringToLoadRef = [@"/" stringByAppendingString:rest];
            return;
        }
    }

    // Otherwise, no rewrite.
}

@end
