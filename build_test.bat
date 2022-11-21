@echo off

xcopy test\lua542.dll build\test\lua542.dll /Y
odin build test -debug -ignore-unknown-attributes -out:build\test\test.exe