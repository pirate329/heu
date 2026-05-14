// ModelRowView.h — per-model row in the redesigned settings panel
#pragma once
#import <Cocoa/Cocoa.h>
#import "ModelManager.h"

@interface ModelRowView : NSView
@property (strong) WhisperModel * model;
- (instancetype)initWithModel:(WhisperModel *)model frame:(NSRect)frame;
- (void)refresh;
- (void)setDownloadFraction:(double)f speedBytesPerSec:(double)speed;
@end
