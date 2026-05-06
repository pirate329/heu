// engine.cpp — audio capture callback and ring buffer helpers
//
// This is the ONLY translation unit that defines MINIAUDIO_IMPLEMENTATION.
// The define must appear before the first include of miniaudio.h in this TU
// so that it wins before engine.hpp's include-guard kicks in.

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"   // ← full implementation compiled here

#include "engine.hpp"    // engine.hpp's #include "miniaudio.h" is now a no-op

#include <algorithm>
#include <cmath>

// ── Global singleton ─────────────────────────────────────────────────────────
HeuEngine * g_engine = nullptr;

// ── Audio capture callback ────────────────────────────────────────────────────
// Called from CoreAudio real-time thread. Must be lock-free and non-blocking.
void audio_data_callback(ma_device * dev, void * /*out*/,
                         const void * in, ma_uint32 frames) {
    HeuEngine * eng = static_cast<HeuEngine *>(dev->pUserData);
    if (!eng || !in) return;

    const float * pcm = static_cast<const float *>(in);
    size_t pos = eng->ring_pos.load(std::memory_order_relaxed);

    // Compute RMS for this chunk (cheap — used only for periodic debug log)
    float rms = 0.0f;
    for (ma_uint32 i = 0; i < frames; i++) {
        eng->ring[pos % kRingSamples] = pcm[i];
        rms += pcm[i] * pcm[i];
        pos++;
    }
    eng->ring_pos.store(pos, std::memory_order_release);

    // Log roughly once per second so we can confirm audio is flowing
    static int s_tick = 0;
    if (++s_tick % 80 == 0) {
        rms = sqrtf(rms / frames);
        fprintf(stderr, "[audio] callback alive | frames=%-4u  rms=%.5f  ring_pos=%zu\n",
                frames, rms, pos);
        fflush(stderr);
    }
}

// ── Ring buffer helpers ───────────────────────────────────────────────────────

// Grab the last `ms` milliseconds of captured audio.
std::vector<float> grab_last_ms(HeuEngine * eng, int ms) {
    size_t n       = static_cast<size_t>((ms / 1000.0) * kSampleRate);
    size_t end_pos = eng->ring_pos.load(std::memory_order_acquire);
    size_t avail   = std::min(end_pos, static_cast<size_t>(kRingSamples));
    n = std::min(n, avail);

    std::vector<float> out(n);
    size_t start = end_pos - n;
    for (size_t i = 0; i < n; i++) out[i] = eng->ring[(start + i) % kRingSamples];
    return out;
}

// Grab all audio written since `start_pos` (capped at ring capacity).
std::vector<float> grab_since(HeuEngine * eng, size_t start_pos) {
    size_t end_pos = eng->ring_pos.load(std::memory_order_acquire);
    size_t n       = end_pos - start_pos;
    if (n > static_cast<size_t>(kRingSamples)) {
        start_pos = end_pos - kRingSamples;
        n = kRingSamples;
    }
    std::vector<float> out(n);
    for (size_t i = 0; i < n; i++) out[i] = eng->ring[(start_pos + i) % kRingSamples];
    return out;
}

// Compute RMS energy per bar from the last ~180ms of audio.
// Called from the main thread to drive the VU meter — safe because ring_pos is atomic.
std::vector<float> compute_level_bars(HeuEngine * eng, int n_bars) {
    auto audio = grab_last_ms(eng, 180);
    std::vector<float> bars(n_bars, 0.0f);
    if (audio.empty()) return bars;

    size_t win = std::max((size_t)1, audio.size() / n_bars);
    for (int i = 0; i < n_bars; i++) {
        size_t s = i * win;
        size_t e = std::min(s + win, audio.size());
        float  r = 0.0f;
        for (size_t j = s; j < e; j++) r += audio[j] * audio[j];
        bars[i] = sqrtf(r / static_cast<float>(e - s));
    }
    return bars;
}
