//
//  GSUpdateChecker.h
//  gfxCardStatus
//
//  Checks the project's GitHub releases for a newer version.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GSUpdateCheckOutcome) {
    GSUpdateCheckOutcomeFailed = 0,
    GSUpdateCheckOutcomeUpToDate,
    GSUpdateCheckOutcomeUpdateAvailable,
};

// latestVersion is a normalised "2.7.1"; any of the other values may be nil.
typedef void (^GSUpdateFetchCompletion)(NSString *latestVersion,
                                        NSString *downloadURL,
                                        NSString *releaseURL,
                                        NSString *notes,
                                        NSError *error);

@interface GSUpdateChecker : NSObject

// Silent check: only surfaces something when a newer release exists.
+ (void)checkInBackground;

// User-initiated check: always reports the result (update, up to date, error).
+ (void)checkWithUserInteraction;

// Reads the newest GitHub release. No UI, so it can be exercised on its own.
+ (void)fetchLatestVersionWithCompletion:(GSUpdateFetchCompletion)completion;

// Compares dotted version strings, tolerating decorated tags such as
// "ver._2.7.1" or "Version 2.7.1". Exposed so it can be tested on its own.
+ (NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB;

@end
