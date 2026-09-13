//
//  GSPreferences.h
//  gfxCardStatus
//
//  Created by Cody Krieger on 9/26/10.
//  Copyright 2010 Cody Krieger. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// Posted whenever the preferences dictionary is persisted (GSPreferences
// doesn't use NSUserDefaults, so this is how the rest of the app finds out
// that a preference changed).
extern NSString * const GSPreferencesDidChangeNotification;

@interface GSPreferences : NSObject <NSWindowDelegate> {
    NSMutableDictionary *_prefsDict;
}

@property (strong) NSMutableDictionary *prefsDict;

- (void)setUpPreferences;
- (void)setDefaults;
- (void)savePreferences;

- (BOOL)shouldCheckForUpdatesOnStartup;
- (BOOL)shouldStartAtLogin;
- (BOOL)shouldDisplayNotifications;
- (BOOL)shouldUseSmartMenuBarIcons;

- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;

+ (GSPreferences *)sharedInstance;

@end
