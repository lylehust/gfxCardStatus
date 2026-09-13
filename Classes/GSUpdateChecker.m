//
//  GSUpdateChecker.m
//  gfxCardStatus
//
//  Checks https://github.com/lylehust/gfxCardStatus/releases for a newer
//  version using the public GitHub REST API. No account, key or Sparkle feed
//  is involved: the app just reads the latest release's tag/name, compares it
//  with its own CFBundleShortVersionString, and points the user at the
//  release's disk image.
//

#import "GSUpdateChecker.h"

#define kLatestReleaseURL   @"https://api.github.com/repos/lylehust/gfxCardStatus/releases/latest"
#define kReleasePageURL     @"https://github.com/lylehust/gfxCardStatus/releases"
#define kUserAgent          @"gfxCardStatus-UpdateChecker"
#define kRequestTimeout     (15.0)
#define kMaxNotesLength     (400)

@implementation GSUpdateChecker

#pragma mark - Public API

+ (void)checkInBackground
{
    [self _checkReportingResult:NO];
}

+ (void)checkWithUserInteraction
{
    [self _checkReportingResult:YES];
}

+ (void)fetchLatestVersionWithCompletion:(GSUpdateFetchCompletion)completion
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLatestReleaseURL]];
    request.timeoutInterval = kRequestTimeout;
    // GitHub rejects requests without a User-Agent, and asks for this Accept.
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:request
                                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;

        if (error || statusCode != 200 || data.length == 0) {
            NSError *failure = error ?: [NSError errorWithDomain:@"GSUpdateChecker"
                                                            code:statusCode
                                                        userInfo:@{NSLocalizedDescriptionKey:
                                                                       [NSString stringWithFormat:@"GitHub returned HTTP %ld", (long)statusCode]}];
            GSLogError(@"Update check failed: HTTP %ld, error: %@.", (long)statusCode, error.localizedDescription ?: @"none");
            completion(nil, nil, kReleasePageURL, nil, failure);
            return;
        }

        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
            GSLogError(@"Update check: unparseable response (%@).", jsonError.localizedDescription);
            completion(nil, nil, kReleasePageURL, nil, jsonError);
            return;
        }

        NSDictionary *release = json;
        NSString *tag = [release[@"tag_name"] isKindOfClass:[NSString class]] ? release[@"tag_name"] : nil;
        NSString *name = [release[@"name"] isKindOfClass:[NSString class]] ? release[@"name"] : nil;
        NSString *htmlURL = [release[@"html_url"] isKindOfClass:[NSString class]] ? release[@"html_url"] : kReleasePageURL;
        NSString *body = [release[@"body"] isKindOfClass:[NSString class]] ? release[@"body"] : nil;

        // Tags are hand-made ("ver._2.7.1"), so pull the first dotted number
        // out of the release name, falling back to the tag.
        NSString *latestVersion = [self _versionFromString:name];
        if (!latestVersion.length) latestVersion = [self _versionFromString:tag];

        NSString *downloadURL = nil;
        for (NSDictionary *asset in release[@"assets"]) {
            NSString *assetName = asset[@"name"];
            NSString *assetURL = asset[@"browser_download_url"];
            if ([assetName isKindOfClass:[NSString class]] && [assetURL isKindOfClass:[NSString class]] &&
                [assetName.lowercaseString hasSuffix:@".dmg"]) {
                downloadURL = assetURL;
                break;
            }
        }

        if (!latestVersion.length)
            GSLogError(@"Update check: could not parse a version from release name '%@' / tag '%@'.", name, tag);

        completion(latestVersion, downloadURL, htmlURL, body, nil);
    }];

    [task resume];
}

+ (NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB
{
    NSArray *a = [self _componentsForVersion:versionA];
    NSArray *b = [self _componentsForVersion:versionB];
    NSUInteger count = MAX(a.count, b.count);

    for (NSUInteger i = 0; i < count; i++) {
        NSInteger left = (i < a.count) ? [a[i] integerValue] : 0;
        NSInteger right = (i < b.count) ? [b[i] integerValue] : 0;

        if (left < right) return NSOrderedAscending;
        if (left > right) return NSOrderedDescending;
    }

    return NSOrderedSame;
}

#pragma mark - Private helpers

+ (void)_checkReportingResult:(BOOL)reportResult
{
    [self fetchLatestVersionWithCompletion:^(NSString *latestVersion, NSString *downloadURL,
                                             NSString *releaseURL, NSString *notes, NSError *error) {
        GSUpdateCheckOutcome outcome = GSUpdateCheckOutcomeFailed;

        if (!error && latestVersion.length) {
            NSString *currentVersion = [self _currentVersion];
            GSLogInfo(@"Update check: latest release is %@, running %@.", latestVersion, currentVersion);
            outcome = ([self compareVersion:latestVersion toVersion:currentVersion] == NSOrderedDescending)
                      ? GSUpdateCheckOutcomeUpdateAvailable
                      : GSUpdateCheckOutcomeUpToDate;
        }

        // NSURLSession calls back on a background queue; all UI must be on main.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _reportOutcome:outcome
                       reporting:reportResult
                   latestVersion:latestVersion
                      downloadURL:downloadURL
                      releaseURL:releaseURL
                            notes:notes];
        });
    }];
}

+ (NSString *)_currentVersion
{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"0";
}

// Pulls the first dotted numeric version ("2.7.1") out of an arbitrary string.
// Requiring at least one dot keeps stray names like "macOS_15" from matching.
+ (NSString *)_versionFromString:(NSString *)string
{
    if (!string.length) return nil;

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+(?:\\.[0-9]+)+"
                                                                          options:0
                                                                            error:&error];
    if (error) return nil;

    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    return match ? [string substringWithRange:match.range] : nil;
}

+ (NSArray *)_componentsForVersion:(NSString *)version
{
    NSString *numeric = [self _versionFromString:version];
    if (!numeric.length) return @[];
    return [numeric componentsSeparatedByString:@"."];
}

+ (void)_reportOutcome:(GSUpdateCheckOutcome)outcome
             reporting:(BOOL)reporting
         latestVersion:(NSString *)latestVersion
            downloadURL:(NSString *)downloadURL
            releaseURL:(NSString *)releaseURL
                  notes:(NSString *)notes
{
    NSString *currentVersion = [self _currentVersion];

    // A silent check only speaks up when there is something to install.
    if (!reporting && outcome != GSUpdateCheckOutcomeUpdateAvailable)
        return;

    NSAlert *alert = [[NSAlert alloc] init];

    switch (outcome) {
        case GSUpdateCheckOutcomeUpdateAvailable: {
            alert.messageText = [NSString stringWithFormat:Str(@"UpdateAvailable"), latestVersion];
            NSMutableString *info = [NSMutableString stringWithFormat:Str(@"UpdateAvailableMessage"), latestVersion, currentVersion];
            if (notes.length) {
                NSString *trimmed = [notes stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length > kMaxNotesLength)
                    trimmed = [[trimmed substringToIndex:kMaxNotesLength] stringByAppendingString:@"…"];
                if (trimmed.length)
                    [info appendFormat:@"\n\n%@", trimmed];
            }
            alert.informativeText = info;
            [alert addButtonWithTitle:Str(@"Download")];
            [alert addButtonWithTitle:Str(@"Later")];

            if ([alert runModal] == NSAlertFirstButtonReturn) {
                NSURL *url = [NSURL URLWithString:downloadURL.length ? downloadURL : releaseURL];
                if (url) [[NSWorkspace sharedWorkspace] openURL:url];
            }
            return;
        }
        case GSUpdateCheckOutcomeUpToDate:
            alert.messageText = Str(@"UpToDate");
            alert.informativeText = [NSString stringWithFormat:Str(@"UpToDateMessage"), currentVersion];
            [alert addButtonWithTitle:Str(@"OK")];
            break;
        case GSUpdateCheckOutcomeFailed:
            alert.messageText = Str(@"UpdateCheckFailed");
            alert.informativeText = Str(@"UpdateCheckFailedMessage");
            [alert addButtonWithTitle:Str(@"OK")];
            break;
    }

    [alert runModal];
}

@end
