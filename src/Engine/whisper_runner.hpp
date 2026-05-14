// whisper_runner.hpp — whisper inference helpers
// Pure C++. Include from both .cpp and .mm files.
#pragma once

#include "engine.hpp"
#include <string>
#include <vector>

// Run whisper on pcm audio. fast_mode = smaller context, greedy, for wake checks.
std::string run_whisper(HeuEngine * eng, std::vector<float> pcm,
                        int n_threads, bool fast_mode);

// Return true if `text` contains (or is similar to) a wake word variant.
bool has_wake_word(const std::string & text);

// Remove the wake word prefix from a full transcription.
// Returns empty string if nothing remains after stripping.
std::string strip_wake_word(const std::string & text);
