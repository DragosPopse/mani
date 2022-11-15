@echo off

if not exist build mkdir build
if not exist build\test mkdir build\test

xcopy test\lua542.dll build\test\lua542.dll /Y
odin build test -debug -ignore-unknown-attributes -out:build\test\test.exe
build\test\test.exe 