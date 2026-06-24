@echo off
REM Build bench_kernel.dll for the native_bench sample.
REM
REM Layout assumed:
REM   <dragonruby_root>\drecs\samples\native_bench\build.bat (this file)
REM   <dragonruby_root>\include\dragonruby.h
REM   <dragonruby_root>\drecs\ext\drecs_kernel.h
REM
REM Output goes to drecs\native\windows-amd64\ so DR.dlopen "bench_kernel" finds it.

setlocal
set DR_INCLUDE=..\..\..\include
set DRECS_INCLUDE=..\..\ext

set OUT_DIR=..\..\native\windows-amd64
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

gcc -shared -O2 ^
    -I"%DR_INCLUDE%" -I"%DRECS_INCLUDE%" ^
    -o "%OUT_DIR%\bench_kernel.dll" ^
    app\bench_kernel.c

if errorlevel 1 (
    echo Build failed.
    exit /b 1
)
echo Built %OUT_DIR%\bench_kernel.dll
