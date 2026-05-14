// SidebarView.h — left navigation sidebar for the settings window
#pragma once
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SettingsTab) {
    SettingsTabModels    = 0,
    SettingsTabShortcuts = 1,
    SettingsTabWakeWord  = 2,
    SettingsTabAudio     = 3,
    SettingsTabVocab     = 4,
    SettingsTabPrivacy   = 5,
    SettingsTabAbout     = 6,
};

@class SidebarView;

@protocol SidebarViewDelegate <NSObject>
- (void)sidebarView:(SidebarView *)sidebar didSelectTab:(SettingsTab)tab;
@end

@interface SidebarView : NSView
@property (nonatomic, weak)   id<SidebarViewDelegate> delegate;
@property (nonatomic, assign) SettingsTab             selectedTab;
- (instancetype)initWithFrame:(NSRect)frame;
@end
