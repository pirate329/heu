// whisper_runner.cpp — whisper inference + wake word detection
// Pure C++.

#include "whisper_runner.hpp"
#include "whisper.h"
#include "common.h"   // similarity()

#include <algorithm>
#include <cctype>
#include <cstring>
#include <string>
#include <vector>

// ── Wake word variants ────────────────────────────────────────────────────────
// Whisper often mishears "hey heu" — cover the common confusions.
static const std::vector<std::string> kWakeWords = {
    "hey heu", "hay hue", "hey hu",    "hey hue",
    "hey you", "a hue",   "heyheu",    "hey heyou",
    "hey hew", "hay hew", "hey hew",   "heyhew",
    "hey hoo", "a who",   "hey who",   "hey hoo",
};

// ── String helpers ────────────────────────────────────────────────────────────
static std::string str_lower(std::string s) {
    for (char & c : s) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    return s;
}

static void strip_punct(std::string & s) {
    s.erase(std::remove_if(s.begin(), s.end(),
        [](char c){ return c == ',' || c == '.' || c == '!' || c == '?'; }),
        s.end());
}

// ── Public API ────────────────────────────────────────────────────────────────

bool has_wake_word(const std::string & text) {
    std::string t = str_lower(text);
    strip_punct(t);
    for (const auto & ww : kWakeWords) {
        if (t.find(ww) != std::string::npos) return true;
        if (::similarity(t, ww) >= kWakeSimilarity)  return true;
    }
    return false;
}

std::string strip_wake_word(const std::string & text) {
    std::string lower = str_lower(text);
    strip_punct(lower);

    for (const auto & ww : kWakeWords) {
        size_t pos = lower.find(ww);
        if (pos != std::string::npos) {
            std::string rest = text.substr(pos + ww.size());
            size_t s = rest.find_first_not_of(" \t,.");
            return (s == std::string::npos) ? "" : rest.substr(s);
        }
    }
    // Wake word not found in text — trim whitespace and return as-is
    size_t s = text.find_first_not_of(" \t\n\r");
    size_t e = text.find_last_not_of (" \t\n\r");
    return (s == std::string::npos) ? "" : text.substr(s, e - s + 1);
}

std::string run_whisper(HeuEngine * eng, std::vector<float> pcm,
                        int n_threads, bool fast_mode) {
    if (pcm.empty()) return "";

    whisper_full_params wp = whisper_full_default_params(
        fast_mode ? WHISPER_SAMPLING_GREEDY : WHISPER_SAMPLING_BEAM_SEARCH);

    wp.print_progress       = false;
    wp.print_special        = false;
    wp.print_realtime       = false;
    wp.print_timestamps     = false;
    wp.translate            = false;
    wp.no_context           = true;
    wp.no_timestamps        = true;
    wp.single_segment       = fast_mode;
    wp.max_tokens           = fast_mode ? 16 : 0;
    wp.language             = "en";
    wp.n_threads            = n_threads;
    wp.temperature          = fast_mode ? 0.0f : 0.4f;
    wp.temperature_inc      = fast_mode ? 0.0f : 0.2f;
    wp.greedy.best_of       = fast_mode ? 1 : 5;
    wp.beam_search.beam_size= fast_mode ? -1 : 5;
    // Slightly smaller context for speed, but large enough to cover 3 s window.
    // 64 frames ≈ 1.3 s which was truncating the wake word; 0 = full context.
    wp.audio_ctx            = 0;

    if (whisper_full(eng->wctx, wp, pcm.data(), static_cast<int>(pcm.size())) != 0) {
        return "";
    }

    std::string result;
    const int n = whisper_full_n_segments(eng->wctx);
    for (int i = 0; i < n; i++) {
        const char * t = whisper_full_get_segment_text(eng->wctx, i);
        if (t) result += t;
    }
    return result;
}
