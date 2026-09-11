//
//  GeneralPreferencesViewController.m
//  gfxCardStatus
//
//  Created by Michal Vančo on 7/11/11.
//  Copyright 2011 Michal Vančo. All rights reserved.
//

#import "GeneralPreferencesViewController.h"
#import "GSNotifier.h"
#import "GSPreferences.h"
#import "GSStartup.h"
#import "GSGPU.h"

#define kGeneralPreferencesName         @"General"

@interface GeneralPreferencesViewController (Internal)
- (BOOL)isLegacyMachine;
- (IBAction)prefCheckboxChanged:(id)sender;
@end

@implementation GeneralPreferencesViewController

@synthesize prefChkSmartIcons;
@synthesize prefChkStartup;
@synthesize prefs;

#pragma mark - Initializers

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (!(self = [super initWithNibName:@"GeneralPreferencesView" bundle:nil]))
        return nil;
    
    prefs = [GSPreferences sharedInstance];
    
    return self;
}

#pragma mark - Overrides

- (void)loadView
{
    [super loadView];

    // The checkboxes are bound to prefs.prefsDict, so toggling one mutates
    // the dictionary without any notification. Wire up a target/action so we
    // can persist the change and apply its side effects right away. Use the
    // nil-terminated initializer: outlets that aren't connected are nil, and an
    // array literal would throw on a nil element.
    NSArray *checkboxes = [[NSArray alloc] initWithObjects:prefChkStartup, prefChkSmartIcons, nil];
    for (NSButton *checkbox in checkboxes) {
        checkbox.target = self;
        checkbox.action = @selector(prefCheckboxChanged:);
        [checkbox setTitle:Str([checkbox title])];
    }
}

- (IBAction)prefCheckboxChanged:(id)sender
{
    // The binding has already written the new value into prefsDict; persist it
    // (which also posts GSPreferencesDidChangeNotification so the menu bar icon
    // refreshes) and apply the start-at-login side effect now.
    [prefs savePreferences];
    if (sender == prefChkStartup)
        [GSStartup loadAtStartup:prefs.shouldStartAtLogin];
}

#pragma mark - Passthrough properties

- (BOOL)isLegacyMachine
{
    return [GSGPU isLegacyMachine];
}

#pragma mark - GSPreferencesModule protocol

- (NSString *)title
{
    return Str(kGeneralPreferencesName);
}

- (NSString *)identifier
{
    return kGeneralPreferencesName;
}

- (NSImage *)image
{
    return [NSImage imageNamed:NSImageNamePreferencesGeneral];
}

@end
