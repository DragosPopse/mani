@echo off

if not exist build mkdir build
if not exist build\mani mkdir build\mani

odin.exe build generator -show-timings -debug -out:build\mani\mani.exe
REM ..\vendor\odin\odin.exe build src -target:js_wasm32 -target-features:+bulk-memory,+atomics -strict-style -show-timings -debug -out:build\web\game.wasm
