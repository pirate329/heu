// ModelManager.h — Whisper model catalog, download, and hot-switch
#pragma once
#import <Cocoa/Cocoa.h>

// ── Model descriptor ──────────────────────────────────────────────────────────
@interface WhisperModel : NSObject
@property (copy) NSString * modelId;      // "medium.en"
@property (copy) NSString * displayName;  // "Medium · English only"
@property (copy) NSString * detail;       // "Accurate, fast on Apple Silicon"
@property long long          sizeBytes;   // approximate compressed size
@end

// ── Delegate ──────────────────────────────────────────────────────────────────
@protocol ModelManagerDelegate <NSObject>
- (void)modelDownloadProgress:(WhisperModel *)model fraction:(double)fraction speedBytesPerSec:(double)speed;
- (void)modelDownloadFinished:(WhisperModel *)model error:(NSError *)error;
- (void)modelSwitchFinished:(WhisperModel *)model error:(NSError *)error;
@end

// ── Manager (singleton) ───────────────────────────────────────────────────────
@interface ModelManager : NSObject

+ (instancetype)shared;

@property (weak)   id<ModelManagerDelegate>   delegate;
@property (copy,readonly) NSString           * modelsDirectory;
@property (copy,readonly) NSString           * currentModelPath;
@property (strong,readonly) NSArray<WhisperModel *> * models;

// Called once from main() after the model is loaded
- (void)setCurrentModelPath:(NSString *)path;

- (BOOL)isDownloaded:(WhisperModel *)model;
- (BOOL)isCurrent:(WhisperModel *)model;
- (NSString *)pathForModel:(WhisperModel *)model;

// Download a model (NSURLSession background download)
- (void)downloadModel:(WhisperModel *)model;
- (void)cancelDownload:(WhisperModel *)model;
- (BOOL)isDownloading:(WhisperModel *)model;

// Hot-swap the running whisper context (pauses engine, loads model, resumes)
- (void)switchToModel:(WhisperModel *)model;

@end
