// main.mm — entry point
//
// Responsibilities:
//   1. Parse command-line args
//   2. Load the whisper model
//   3. Init + start the miniaudio capture device
//   4. Start the processing thread
//   5. Run the Cocoa event loop (blocks until quit)
#import "AppDelegate.h"
#import "ModelManager.h"
#import <AVFoundation/AVFoundation.h>
#include "engine.hpp"
#include "processing_loop.hpp"
#include "whisper.h"

#include <cstdio>
#include <semaphore.h>
#include <string>

static void print_usage(const char * prog) {
    fprintf(stderr,
        "usage: %s [options]\n"
        "\n"
        "options:\n"
        "  -m, --model PATH    path to whisper ggml model [required]\n"
        "  -ng, --no-gpu       disable Metal/GPU inference\n"
        "  -h,  --help         show this message\n"
        "\n"
        "example:\n"
        "  %s -m ../whisper.cpp/models/ggml-base.en.bin\n"
        "\n", prog, prog);
}

int main(int argc, char * argv[]) {
    std::string model_path;
    bool use_gpu = true;

    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if      (a == "-h" || a == "--help")   { print_usage(argv[0]); return 0; }
        else if (a == "-ng" || a == "--no-gpu") { use_gpu = false; }
        else if ((a == "-m" || a == "--model") && i+1 < argc) { model_path = argv[++i]; }
        else    { fprintf(stderr, "unknown arg: %s\n\n", a.c_str());
                  print_usage(argv[0]); return 1; }
    }

    if (model_path.empty()) {
        // Search standard locations for any ggml model
        NSString * execDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
        NSArray<NSString *> * searchDirs = @[
            [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"models"],
            [execDir stringByAppendingPathComponent:@"models"],
            [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"heu/models"],
        ];
        NSArray<NSString *> * preferred = @[
            @"ggml-small.en.bin", @"ggml-base.en.bin", @"ggml-small.bin",
            @"ggml-base.bin", @"ggml-tiny.en.bin", @"ggml-tiny.bin",
            @"ggml-medium.en.bin", @"ggml-medium.bin",
            @"ggml-large-v3-turbo.bin", @"ggml-large-v3.bin",
        ];
        for (NSString * dir in searchDirs) {
            for (NSString * name in preferred) {
                NSString * path = [dir stringByAppendingPathComponent:name];
                if ([[NSFileManager defaultManager] isReadableFileAtPath:path]) {
                    model_path = path.UTF8String;
                    break;
                }
            }
            if (!model_path.empty()) break;
        }
        if (model_path.empty()) {
            fprintf(stderr, "error: no model found.\n"
                    "  Place a ggml-*.bin in ~/Library/Application Support/heu/models/\n"
                    "  or run with: %s -m <path>\n\n", argv[0]);
            print_usage(argv[0]); return 1;
        }
        fprintf(stderr, "[heu] auto-detected model: %s\n", model_path.c_str());
    }

    // ── Request microphone permission (macOS TCC) ─────────────────────────────
    // Without explicit permission the OS silently delivers near-zero audio.
    {
        AVAuthorizationStatus status =
            [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
        fprintf(stderr, "[heu] mic permission status: %ld (%s)\n", (long)status,
                status == AVAuthorizationStatusAuthorized   ? "AUTHORIZED" :
                status == AVAuthorizationStatusDenied       ? "DENIED — grant in System Settings → Privacy → Microphone" :
                status == AVAuthorizationStatusRestricted   ? "RESTRICTED" :
                                                              "NOT DETERMINED — will request now");
        fflush(stderr);

        if (status == AVAuthorizationStatusDenied) {
            fprintf(stderr, "[heu] ERROR: microphone access denied.\n"
                            "       Open System Settings → Privacy & Security → Microphone\n"
                            "       and enable access for Terminal (or this app).\n");
            return 1;
        }

        if (status == AVAuthorizationStatusNotDetermined) {
            // Block until the user responds to the system prompt
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                     completionHandler:^(BOOL granted) {
                fprintf(stderr, "[heu] mic permission: %s\n", granted ? "GRANTED" : "DENIED");
                fflush(stderr);
                dispatch_semaphore_signal(sem);
            }];
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

            if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]
                    != AVAuthorizationStatusAuthorized) {
                fprintf(stderr, "[heu] mic access not granted, exiting.\n");
                return 1;
            }
        }
    }

    // ── Load whisper model ────────────────────────────────────────────────────
    fprintf(stderr, "[heu] loading model: %s\n", model_path.c_str());

    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu    = use_gpu;
    cparams.flash_attn = use_gpu;

    HeuEngine engine;
    engine.ring.resize(kRingSamples, 0.0f);
    g_engine = &engine;

    engine.wctx = whisper_init_from_file_with_params(model_path.c_str(), cparams);
    if (!engine.wctx) {
        fprintf(stderr, "[heu] failed to load model '%s'\n", model_path.c_str());
        return 1;
    }
    fprintf(stderr, "[heu] model loaded\n");
    [[ModelManager shared] setCurrentModelPath:
        [NSString stringWithUTF8String:model_path.c_str()]];

    // ── List and select audio capture device ──────────────────────────────────
    ma_context ma_ctx;
    if (ma_context_init(nullptr, 0, nullptr, &ma_ctx) == MA_SUCCESS) {
        ma_device_info * capture_devs = nullptr;
        ma_uint32        capture_count = 0;
        if (ma_context_get_devices(&ma_ctx, nullptr, nullptr,
                                   &capture_devs, &capture_count) == MA_SUCCESS) {
            fprintf(stderr, "[heu] available capture devices:\n");
            for (ma_uint32 i = 0; i < capture_count; i++) {
                fprintf(stderr, "  [%u] %s%s\n", i,
                        capture_devs[i].name,
                        capture_devs[i].isDefault ? "  ← default" : "");
            }
            fflush(stderr);
        }
        ma_context_uninit(&ma_ctx);
    }

    // ── Init audio capture ────────────────────────────────────────────────────
    ma_device_config cfg = ma_device_config_init(ma_device_type_capture);
    cfg.capture.format   = ma_format_f32;
    cfg.capture.channels = 1;
    cfg.sampleRate       = static_cast<ma_uint32>(kSampleRate);
    cfg.dataCallback     = audio_data_callback;
    cfg.pUserData        = &engine;

    if (ma_device_init(nullptr, &cfg, &engine.ma_dev) != MA_SUCCESS) {
        fprintf(stderr, "[heu] failed to init audio device\n");
        whisper_free(engine.wctx); return 1;
    }
    engine.ma_ok = true;

    if (ma_device_start(&engine.ma_dev) != MA_SUCCESS) {
        fprintf(stderr, "[heu] failed to start audio device\n");
        return 1;
    }

    // Log what miniaudio actually negotiated (may differ from requested)
    fprintf(stderr, "[heu] microphone active\n");
    fprintf(stderr, "[heu] device name    : %s\n",  engine.ma_dev.capture.name);
    fprintf(stderr, "[heu] sample rate    : %u Hz (requested %d)\n",
            engine.ma_dev.sampleRate, kSampleRate);
    fprintf(stderr, "[heu] channels       : %u\n",  engine.ma_dev.capture.channels);
    fprintf(stderr, "[heu] format         : %d  (5=f32)\n", engine.ma_dev.capture.format);
    fflush(stderr);

    // ── Start background processing thread ────────────────────────────────────
    engine.proc_thread = std::thread(processing_loop, &engine);

    fprintf(stderr, "[heu] ready — say \"hey heu\" to start dictating\n");

    // ── Cocoa event loop (blocks until Quit) ──────────────────────────────────
    @autoreleasepool {
        NSApplication * app = [NSApplication sharedApplication];
        // LSUIElement=true in Info.plist already sets accessory policy.
        // Calling setActivationPolicy again after bundle launch on macOS 26
        // conflicts with the window server registration and hides the status item.
        HeuDelegate * delegate = [[HeuDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
