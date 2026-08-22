heu — local voice-to-text for macOS
=====================================

Author : pirate329 <amankumar020003@gmail.com>
License: MIT


WHAT IS THIS
------------
heu is a lightweight macOS menu bar app that transcribes your speech and
inserts the text directly into whatever app you are typing in.
It runs entirely offline using whisper.cpp — no internet, no cloud.


HOW IT WORKS
------------
1. Hold the fn key to start dictating.
2. Release fn when you are done.
3. The transcribed text is inserted at your cursor automatically.

heu uses OpenAI Whisper (via whisper.cpp) running locally on your GPU
through Apple Metal. Audio is captured at 16 kHz and processed in real time.


REQUIREMENTS
------------
- macOS 14 (Sonoma) or later (tested on macOS 26 Tahoe)
- Apple Silicon (M1 or newer) — required, the build is arm64-only
- A whisper.cpp ggml model file (see MODELS section)
- Xcode Command Line Tools
- CMake 3.16+


DEPENDENCIES
------------
This project depends on whisper.cpp. Clone it alongside this repo:

    git clone https://github.com/ggerganov/whisper.cpp ../whisper.cpp

The expected directory layout is:

    wishper/
    ├── heu/          ← this repo
    └── whisper.cpp/  ← whisper.cpp cloned here


MODELS
------
Download a model into whisper.cpp/models/:

    cd ../whisper.cpp
    bash models/download-ggml-model.sh small.en

Supported models (small to large):
    ggml-tiny.en.bin
    ggml-base.en.bin
    ggml-small.en.bin      (recommended — good balance of speed and accuracy)
    ggml-medium.en.bin
    ggml-large-v3.bin

heu will auto-detect any ggml model placed in:
    ~/Library/Application Support/heu/models/


BUILD
-----
    cd heu
    cmake -B build -S .
    cmake --build build -j$(sysctl -n hw.logicalcpu)

The binary will be at build/heu. Run it directly:

    ./build/heu -m ../whisper.cpp/models/ggml-small.en.bin


INSTALL AS APP BUNDLE
---------------------
Create /Applications/heu.app with the following structure:

    heu.app/
    └── Contents/
        ├── Info.plist
        └── MacOS/
            ├── heu          (copy of build/heu)
            └── models/
                └── ggml-small.en.bin  (symlink or copy)

See src/Info.plist for the required bundle configuration.

Or just run the packaging script, which builds the bundle, ad-hoc signs it,
and produces a distributable DMG in dist/:

    bash scripts/package.sh


PERMISSIONS
-----------
On first launch heu will request:

  Microphone     — required to capture your voice
  Accessibility  — required to detect which text field is focused
                   and to insert transcribed text
  Automation     — required to send Cmd+V keystrokes to other apps
                   (System Settings → Privacy & Security → Automation)

All three must be granted for full functionality.


KEYBOARD SHORTCUT
-----------------
    fn (hold)   Start listening
    fn (release) Stop and transcribe


PROJECT STRUCTURE
-----------------
    src/
      Info.plist                 Bundle configuration
      App/
        main.mm                  Entry point, arg parsing, Cocoa run loop
        AppDelegate.*            Menu bar item, HUD wiring, engine callbacks
      Engine/
        engine.hpp/.cpp          Audio capture (miniaudio), ring buffer, shared state
        processing_loop.*        Background thread: VAD, whisper inference, wake word
        whisper_runner.*         Whisper context wrapper
      Input/
        hotkey.*                 fn key event tap (push-to-talk)
        text_inserter.*          AX text insertion + Cmd+V clipboard fallback
      HUD/
        HeuHUDView.*             On-screen listening / transcribing overlay
        WaveOverlay.*            Fullscreen wave animation (top of screen)
      Model/
        ModelManager.*           Tracks currently loaded model path
      UI/
        StatusBar/PillStatusView.*  Menu bar pill
        Settings/SettingsPanel.*    Models & Settings panel
        Settings/SidebarView.*      Settings sidebar
        Settings/ModelRowView.*     Model list row
        Settings/MeterView.*        Audio level meter
