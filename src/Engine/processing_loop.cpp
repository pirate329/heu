// processing_loop.cpp — the main state machine
// Pure C++. Runs on a background thread.

#include "processing_loop.hpp"
#include "whisper_runner.hpp"
#include "common.h"   // vad_simple

#include <chrono>
#include <cstdio>
#include <thread>

// ─────────────────────────────────────────────────────────────────────────────
// State machine
// ─────────────────────────────────────────────────────────────────────────────
void processing_loop(HeuEngine * eng) {
    using clock = std::chrono::steady_clock;
    using ms    = std::chrono::milliseconds;

    auto last_wake_check = clock::now();
    auto listen_start    = clock::now();

    while (eng->running.load(std::memory_order_relaxed)) {
        // Block here while a model hot-swap is in progress
        while (eng->paused.load(std::memory_order_acquire))
            std::this_thread::sleep_for(ms(30));

        auto now = clock::now();

        // Idle if no model is loaded yet (first-run setup mode)
        if (eng->wctx == nullptr) {
            std::this_thread::sleep_for(ms(200));
            continue;
        }

        switch (eng->state.load(std::memory_order_acquire)) {

        // ── DETECTING ─────────────────────────────────────────────────────────
        // Periodically run whisper on a short rolling window.
        // If the output contains the wake word, transition to LISTENING.
        case HeuState::DETECTING: {
            // Hotkey path: skip whisper entirely, jump straight to LISTENING
            if (eng->manual_trigger.exchange(false, std::memory_order_acq_rel)) {
                fprintf(stderr, "[heu] hotkey triggered — starting listen\n"); fflush(stderr);
                eng->is_manual_listen.store(true, std::memory_order_release);
                eng->cmd_start_pos = eng->ring_pos.load(std::memory_order_acquire);
                listen_start = clock::now();
                eng->state.store(HeuState::LISTENING, std::memory_order_release);
                if (eng->on_state_change) eng->on_state_change(HeuState::LISTENING);
                break;
            }

            auto since = std::chrono::duration_cast<ms>(now - last_wake_check).count();
            if (since < kWakeIntervalMs) { std::this_thread::sleep_for(ms(20)); break; }
            last_wake_check = now;

            auto audio = grab_last_ms(eng, kWakeWindowMs);
            fprintf(stderr, "[detect] ring_pos=%zu  grabbed %zu samples (%.1fs)\n",
                    eng->ring_pos.load(), audio.size(),
                    audio.size() / (float)kSampleRate);
            fflush(stderr);

            if (audio.size() < static_cast<size_t>(kSampleRate / 2)) {
                fprintf(stderr, "[detect] not enough audio yet, skipping\n");
                break;
            }

            // Simple RMS energy gate:
            // vad_simple() is an end-of-speech detector (returns true when recent energy
            // DROPS relative to the overall window) — not suitable as an activity gate.
            // Instead, compute RMS directly and compare to a noise-floor threshold.
            float rms = 0.0f;
            for (float s : audio) rms += s * s;
            rms = sqrtf(rms / audio.size());
            fprintf(stderr, "[detect] audio rms=%.5f  noise_floor≈0.005  speech_thold=0.015\n", rms);
            fflush(stderr);

            // Skip whisper if audio is at or near the noise floor.
            // Observed silence RMS ~0.004; threshold 0.007 to be just above it.
            // If whisper never triggers, raise input volume in System Settings → Sound → Input.
            if (rms < 0.007f) {
                fprintf(stderr, "[detect] rms=%.5f below 0.007 — skipping\n", rms);
                break;
            }
            fprintf(stderr, "[detect] speech detected (rms=%.4f) — running whisper\n", rms);

            std::string text = run_whisper(eng, audio, kWakeThreads, /*fast=*/true);
            if (text.empty()) { fprintf(stderr, "[detect] whisper returned empty\n"); break; }
            fprintf(stderr, "[heu] wake check: '%s'\n", text.c_str());

            if (has_wake_word(text)) {
                fprintf(stderr, "[heu] ** wake word detected **\n");
                eng->cmd_start_pos = eng->ring_pos.load(std::memory_order_acquire);
                listen_start = clock::now();
                eng->state.store(HeuState::LISTENING, std::memory_order_release);
                if (eng->on_state_change) eng->on_state_change(HeuState::LISTENING);
            }
            break;
        }

        // ── LISTENING ─────────────────────────────────────────────────────────
        // Accumulate audio until silence or timeout.
        case HeuState::LISTENING: {
            auto elapsed = std::chrono::duration_cast<ms>(now - listen_start).count();

            if (elapsed < 300) { std::this_thread::sleep_for(ms(50)); break; }

            auto audio     = grab_since(eng, eng->cmd_start_pos);
            bool timed_out = elapsed >= kMaxListenMs;
            bool silence   = false;

            bool force = eng->force_stop.exchange(false, std::memory_order_acq_rel);

            // In push-to-talk (manual) mode skip VAD — only stop on fn-release or timeout
            bool manual = eng->is_manual_listen.load(std::memory_order_acquire);
            if (!manual && elapsed >= kMinListenMs) {
                auto copy = audio;
                silence = vad_simple(copy, kSampleRate, kVadSilenceMs,
                                     kVadThold, kFreqThold, false);
                fprintf(stderr, "[listen] elapsed=%lldms  silence=%s\n",
                        elapsed, silence ? "YES → stopping" : "no");
                fflush(stderr);
            }

            if (timed_out || silence || force) {
                fprintf(stderr, "[heu] recording done (%lldms)%s\n",
                        elapsed, timed_out ? " [timeout]" : force ? " [fn released]" : " [silence]");
                eng->cmd_audio = std::move(audio);
                eng->state.store(HeuState::PROCESSING, std::memory_order_release);
                if (eng->on_state_change) eng->on_state_change(HeuState::PROCESSING);
            } else {
                std::this_thread::sleep_for(ms(80));
            }
            break;
        }

        // ── PROCESSING ────────────────────────────────────────────────────────
        // Full transcription, strip wake word prefix, fire callback.
        case HeuState::PROCESSING: {
            std::string raw   = run_whisper(eng, eng->cmd_audio,
                                            kTranscribeThreads, /*fast=*/false);
            std::string clean = strip_wake_word(raw);
            fprintf(stderr, "[heu] transcript: '%s'\n", clean.c_str());

            if (!clean.empty() && eng->on_transcription) {
                eng->on_transcription(clean);
            }

            eng->cmd_audio.clear();
            eng->is_manual_listen.store(false, std::memory_order_release);
            eng->state.store(HeuState::DETECTING, std::memory_order_release);
            if (eng->on_state_change) eng->on_state_change(HeuState::DETECTING);
            break;
        }
        } // switch
    }
}
