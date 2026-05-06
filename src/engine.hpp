// engine.hpp — shared types, constants, and HeuEngine
//
// Pure C++. Safe to #include from .cpp and .mm files.
// NOTE: miniaudio.h is included here for ma_device.
//       MINIAUDIO_IMPLEMENTATION must be defined in engine.cpp ONLY — before
//       including this header — so the include-guard trick works correctly.
#pragma once

#include "miniaudio.h"  // ma_device; IMPLEMENTATION defined in engine.cpp only

#include <atomic>
#include <functional>
#include <string>
#include <thread>
#include <vector>

struct whisper_context;   // full type in whisper.h; include it where you call whisper_*

// ── Tunables ──────────────────────────────────────────────────────────────────
static constexpr int   kSampleRate        = 16000;
static constexpr int   kRingSeconds       = 30;
static constexpr int   kRingSamples       = kSampleRate * kRingSeconds;
static constexpr int   kWakeWindowMs      = 3000;   // rolling window for wake check
static constexpr int   kWakeIntervalMs    = 1000;   // how often to check for wake word
static constexpr int   kMinListenMs       = 1500;   // minimum record duration after wake
static constexpr int   kMaxListenMs       = 15000;  // max record duration before auto-stop
static constexpr int   kVadSilenceMs      = 800;    // trailing silence → end of speech
static constexpr float kVadThold          = 0.6f;
static constexpr float kFreqThold         = 100.0f;
static constexpr int   kWakeThreads       = 2;
static constexpr int   kTranscribeThreads = 4;
static constexpr float kWakeSimilarity    = 0.72f;  // Levenshtein threshold for wake word

// ── App states ────────────────────────────────────────────────────────────────
enum class HeuState : int {
    DETECTING  = 0,   // scanning for "hey heu"
    LISTENING  = 1,   // recording the user's command
    PROCESSING = 2,   // running whisper on the recording
};

// ── Engine ────────────────────────────────────────────────────────────────────
// All runtime state. Owned by main(). Pointer shared via g_engine global.
struct HeuEngine {
    whisper_context * wctx = nullptr;

    // Single-writer lock-free ring buffer (writer = audio thread)
    std::vector<float>   ring;
    std::atomic<size_t>  ring_pos{0};  // ever-increasing counter

    // Command audio buffer (used during LISTENING → PROCESSING transition)
    std::vector<float>   cmd_audio;
    size_t               cmd_start_pos = 0;  // ring_pos snapshot at wake detection

    ma_device  ma_dev;
    bool       ma_ok = false;

    std::atomic<HeuState> state{HeuState::DETECTING};
    std::atomic<bool>     running{true};
    std::atomic<bool>     paused{false};           // true while model is being hot-swapped
    std::atomic<bool>     manual_trigger{false};   // fn pressed  → jump to LISTENING
    std::atomic<bool>     force_stop{false};       // fn released → end LISTENING immediately
    std::atomic<bool>     is_manual_listen{false}; // true = skip VAD, only stop on fn-release

    // UI callbacks — always dispatched to main thread by the callee
    std::function<void(HeuState)>           on_state_change;
    std::function<void(const std::string&)> on_transcription;

    std::thread proc_thread;
};

// Global singleton. Defined in engine.cpp, assigned in main.mm.
extern HeuEngine * g_engine;

// True when the app launched with no model — Settings panel opens automatically.
extern bool g_first_run;

// ── Ring buffer helpers (engine.cpp) ─────────────────────────────────────────
std::vector<float> grab_last_ms(HeuEngine * eng, int ms);
std::vector<float> grab_since  (HeuEngine * eng, size_t start_pos);

// Compute per-bar audio energy for VU meter (safe from any thread)
std::vector<float> compute_level_bars(HeuEngine * eng, int n_bars);

// miniaudio capture callback — registered in main.mm
void audio_data_callback(ma_device * dev, void * out,
                         const void * in, ma_uint32 frames);
