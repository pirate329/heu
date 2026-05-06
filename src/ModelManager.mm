// ModelManager.mm — model catalog, download via NSURLSession, hot-switch
#import "ModelManager.h"
#include "engine.hpp"
#include "processing_loop.hpp"
#include "whisper.h"
#include <thread>
#include <chrono>

// Declared in engine.cpp
extern bool g_first_run;

static NSString * const kHFBase =
    @"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/";

// ── WhisperModel ──────────────────────────────────────────────────────────────
@implementation WhisperModel
- (NSString *)filename { return [NSString stringWithFormat:@"ggml-%@.bin", self.modelId]; }
@end

// ── ModelManager ──────────────────────────────────────────────────────────────
@interface ModelManager () <NSURLSessionDownloadDelegate>
@property (nonatomic, copy) NSString      * currentModelPath;  // readwrite override
@property (strong) NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> * tasks;
@property (strong) NSMutableDictionary<NSString *, NSDate *>                  * startTimes;
@property (strong) NSURLSession          * session;
@end

@implementation ModelManager

+ (instancetype)shared {
    static ModelManager * s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[ModelManager alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    _tasks      = [NSMutableDictionary dictionary];
    _startTimes = [NSMutableDictionary dictionary];
    NSURLSessionConfiguration * cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForResource = 0;   // no overall timeout for large downloads
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    return self;
}

// ── Catalog ───────────────────────────────────────────────────────────────────
- (NSArray<WhisperModel *> *)models {
    static NSArray * list;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        NSArray * raw = @[
            @[@"tiny.en",          @"Tiny · English",      @"Fastest, ~32× realtime",      @75000000],
            @[@"tiny",             @"Tiny · Multilingual", @"Fastest, 99 languages",        @75000000],
            @[@"base.en",          @"Base · English",      @"Fast, good accuracy",          @142000000],
            @[@"base",             @"Base · Multilingual", @"Fast, 99 languages",           @142000000],
            @[@"small.en",         @"Small · English",     @"Balanced speed & accuracy",    @466000000],
            @[@"small",            @"Small · Multilingual",@"Balanced, 99 languages",       @466000000],
            @[@"medium.en",        @"Medium · English",    @"Accurate, English only",       @1533000000],
            @[@"medium",           @"Medium · Multilingual",@"Accurate, 99 languages",      @1533000000],
            @[@"large-v3-turbo",   @"Large Turbo",         @"Fast + accurate, 99 languages",@809000000],
            @[@"large-v3",         @"Large v3",            @"Best accuracy, 99 languages",  @2900000000],
        ];
        NSMutableArray * out = [NSMutableArray array];
        for (NSArray * r in raw) {
            WhisperModel * m  = [WhisperModel new];
            m.modelId         = r[0];
            m.displayName     = r[1];
            m.detail          = r[2];
            m.sizeBytes       = [r[3] longLongValue];
            [out addObject:m];
        }
        list = [out copy];
    });
    return list;
}

// ── Paths ─────────────────────────────────────────────────────────────────────
- (void)setCurrentModelPath:(NSString *)path {
    _currentModelPath = [path copy];
}

- (NSString *)modelsDirectory {
    if (_currentModelPath)
        return [_currentModelPath stringByDeletingLastPathComponent];
    // Default: ~/Library/Application Support/heu/models/
    NSString * appSupport = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [appSupport stringByAppendingPathComponent:@"heu/models"];
}

- (NSString *)pathForModel:(WhisperModel *)model {
    return [self.modelsDirectory stringByAppendingPathComponent:model.filename];
}

- (BOOL)isDownloaded:(WhisperModel *)model {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self pathForModel:model]];
}

- (BOOL)isCurrent:(WhisperModel *)model {
    return [self.currentModelPath isEqualToString:[self pathForModel:model]];
}

- (BOOL)isDownloading:(WhisperModel *)model {
    return self.tasks[model.modelId] != nil;
}

// ── Download ──────────────────────────────────────────────────────────────────
- (void)downloadModel:(WhisperModel *)model {
    if (self.tasks[model.modelId]) return;   // already in flight
    NSURL * url = [NSURL URLWithString:[kHFBase stringByAppendingString:model.filename]];
    NSURLSessionDownloadTask * task = [self.session downloadTaskWithURL:url];
    self.tasks[model.modelId]      = task;
    self.startTimes[model.modelId] = [NSDate date];
    [task resume];
    fprintf(stderr, "[model] downloading %s\n", model.modelId.UTF8String);
    fflush(stderr);
}

- (void)cancelDownload:(WhisperModel *)model {
    [self.tasks[model.modelId] cancel];
    [self.tasks      removeObjectForKey:model.modelId];
    [self.startTimes removeObjectForKey:model.modelId];
}

// NSURLSessionDownloadDelegate
- (void)URLSession:(NSURLSession *)__unused s
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)__unused wrote
 totalBytesWritten:(int64_t)written
totalBytesExpectedToWrite:(int64_t)expected {
    if (expected <= 0) return;
    double fraction = (double)written / (double)expected;
    NSString * url  = task.originalRequest.URL.lastPathComponent;
    WhisperModel * model = [self modelForFilename:url];
    if (!model) return;
    NSDate * start = self.startTimes[model.modelId];
    double elapsed = start ? -[start timeIntervalSinceNow] : 1.0;
    double speed   = (elapsed > 0.5) ? (double)written / elapsed : 0.0;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate modelDownloadProgress:model fraction:fraction speedBytesPerSec:speed];
    });
}

- (void)URLSession:(NSURLSession *)__unused s
      downloadTask:(NSURLSessionDownloadTask *)task
didFinishDownloadingToURL:(NSURL *)tmp {
    NSString * filename = task.originalRequest.URL.lastPathComponent;
    WhisperModel * model = [self modelForFilename:filename];

    NSString * dest = [self.modelsDirectory stringByAppendingPathComponent:filename];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.modelsDirectory
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSError * err;
    [[NSFileManager defaultManager] moveItemAtURL:tmp toURL:[NSURL fileURLWithPath:dest] error:&err];

    [self.tasks      removeObjectForKey:model.modelId];
    [self.startTimes removeObjectForKey:model.modelId];
    fprintf(stderr, "[model] download done: %s → %s\n",
            filename.UTF8String, dest.UTF8String);
    fflush(stderr);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate modelDownloadFinished:model error:err];
    });
}

- (void)URLSession:(NSURLSession *)__unused s task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!error) return;
    NSString * filename = task.originalRequest.URL.lastPathComponent;
    WhisperModel * model = [self modelForFilename:filename];
    if (!model) return;
    [self.tasks removeObjectForKey:model.modelId];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate modelDownloadFinished:model error:error];
    });
}

// ── Hot-switch ────────────────────────────────────────────────────────────────
- (void)switchToModel:(WhisperModel *)model {
    NSString * path = [self pathForModel:model];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (!g_engine) return;

        bool isFirstLoad = (g_engine->wctx == nullptr);

        if (!isFirstLoad) {
            // Pause the processing loop until we're done swapping
            g_engine->paused.store(true, std::memory_order_release);

            // Wait for processing to be idle (DETECTING state)
            using clock = std::chrono::steady_clock;
            auto deadline = clock::now() + std::chrono::seconds(30);
            while (g_engine->state.load() != HeuState::DETECTING) {
                if (clock::now() > deadline) {
                    g_engine->paused.store(false, std::memory_order_release);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSError * e = [NSError errorWithDomain:@"heu" code:1
                            userInfo:@{NSLocalizedDescriptionKey:@"Engine did not reach idle state"}];
                        [self.delegate modelSwitchFinished:model error:e];
                    });
                    return;
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }

            // Free old context
            whisper_free(g_engine->wctx);
            g_engine->wctx = nullptr;
        }

        whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu    = true;
        cparams.flash_attn = true;
        whisper_context * newCtx =
            whisper_init_from_file_with_params(path.UTF8String, cparams);

        NSError * err = nil;
        if (newCtx) {
            g_engine->wctx = newCtx;
            _currentModelPath = [path copy];
            fprintf(stderr, "[model] switched to %s\n", model.modelId.UTF8String);
        } else {
            err = [NSError errorWithDomain:@"heu" code:2
                userInfo:@{NSLocalizedDescriptionKey:@"Failed to load model"}];
            fprintf(stderr, "[model] failed to load %s\n", path.UTF8String);
        }
        fflush(stderr);

        if (!isFirstLoad) {
            g_engine->paused.store(false, std::memory_order_release);
        }

        // First load: start mic and processing thread now that we have a model
        if (isFirstLoad && newCtx) {
            // Init and start microphone
            ma_device_config cfg = ma_device_config_init(ma_device_type_capture);
            cfg.capture.format   = ma_format_f32;
            cfg.capture.channels = 1;
            cfg.sampleRate       = 16000;
            cfg.dataCallback     = audio_data_callback;
            cfg.pUserData        = g_engine;
            if (ma_device_init(nullptr, &cfg, &g_engine->ma_dev) == MA_SUCCESS) {
                g_engine->ma_ok = true;
                ma_device_start(&g_engine->ma_dev);
                fprintf(stderr, "[heu] microphone started after first model load\n");
            } else {
                fprintf(stderr, "[heu] failed to start microphone\n");
            }
            fflush(stderr);
            // Start the processing thread
            g_engine->proc_thread = std::thread(processing_loop, g_engine);
            g_first_run = false;
            fprintf(stderr, "[heu] engine started\n"); fflush(stderr);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate modelSwitchFinished:model error:err];
        });
    });
}

// ── Helpers ───────────────────────────────────────────────────────────────────
- (WhisperModel *)modelForFilename:(NSString *)filename {
    for (WhisperModel * m in self.models)
        if ([m.filename isEqualToString:filename]) return m;
    return nil;
}

@end
