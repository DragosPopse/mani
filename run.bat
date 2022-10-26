@echo off

build\mani\mani.exe -in-dir:test
REM odin run src/main.odin -file -- -mani-collection:shared -in-dir:test -out-dir:mani_gen -out-package:mani_gen