cmake_minimum_required(VERSION 3.16)
project(heu LANGUAGES CXX OBJCXX)

if(NOT APPLE)
    message(FATAL_ERROR "heu is macOS only")
endif()

# Target macOS 14+ (Sonoma). All APIs used are available on 14+.
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS version" FORCE)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

# ── whisper.cpp sub-project ───────────────────────────────────────────────────
set(WHISPER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../whisper.cpp"
    CACHE PATH "Path to whisper.cpp source tree")

if(NOT EXISTS "${WHISPER_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR "whisper.cpp not found at ${WHISPER_ROOT}")
endif()

set(BUILD_SHARED_LIBS      OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_METAL             ON  CACHE BOOL "" FORCE)

add_subdirectory(${WHISPER_ROOT} whisper_build EXCLUDE_FROM_ALL)

# ── whisper example helpers (vad_simple, similarity) ─────────────────────────
# WHISPER_BUILD_EXAMPLES is OFF so we compile common.cpp ourselves.
set(EXAMPLES_DIR "${WHISPER_ROOT}/examples")

add_library(heu_common STATIC
    ${EXAMPLES_DIR}/common.cpp
    ${EXAMPLES_DIR}/common-whisper.cpp
    ${EXAMPLES_DIR}/common-ggml.cpp
    ${EXAMPLES_DIR}/grammar-parser.cpp
)
target_include_directories(heu_common PUBLIC
    ${EXAMPLES_DIR}
    ${WHISPER_ROOT}/include
    ${WHISPER_ROOT}/ggml/include
)
target_link_libraries(heu_common PUBLIC whisper)

# ── heu sources ───────────────────────────────────────────────────────────────
# engine.cpp must come first: it defines MINIAUDIO_IMPLEMENTATION
# before engine.hpp's include-guard pulls in miniaudio.h in declaration-only mode.
add_executable(heu
    src/engine.cpp           # MINIAUDIO_IMPLEMENTATION lives here — must be first
    src/whisper_runner.cpp
    src/processing_loop.cpp
    src/HeuHUDView.mm
    src/WaveOverlay.mm
    src/AppDelegate.mm
    src/text_inserter.mm
    src/hotkey.mm
    src/ModelManager.mm
    src/SettingsPanel.mm
    src/main.mm
)

target_include_directories(heu PRIVATE
    src                      # engine.hpp, whisper_runner.hpp, etc.
    ${EXAMPLES_DIR}          # common.h, miniaudio.h
    ${WHISPER_ROOT}/include  # whisper.h
    ${WHISPER_ROOT}/ggml/include
)

target_compile_options(heu PRIVATE
    -fobjc-arc
    -Wall
    -Wno-unused-parameter
)

target_link_libraries(heu PRIVATE
    heu_common
    "-framework Cocoa"
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework Metal"
    "-framework AVFoundation"
    "-framework ApplicationServices"
)

install(TARGETS heu DESTINATION bin)
