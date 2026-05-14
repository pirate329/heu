// SettingsPanel.h — model browser & downloader panel
#pragma once
#import <Cocoa/Cocoa.h>

@interface SettingsPanel : NSObject
+ (instancetype)shared;
- (void)show;
@end
