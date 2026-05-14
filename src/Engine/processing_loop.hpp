// processing_loop.hpp — background state machine declaration
// Pure C++.
#pragma once

#include "engine.hpp"

// Main processing loop. Run on a std::thread in main().
// Transitions: DETECTING → LISTENING → PROCESSING → DETECTING
// Calls eng->on_state_change and eng->on_transcription when appropriate.
void processing_loop(HeuEngine * eng);
