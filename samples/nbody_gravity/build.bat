@echo off
REM Build nbody_kernel.dll for the nbody_gravity sample.
REM
REM Layout assumed (matches native_bench / native_boids):
REM   <dragonruby_root>\drecs\samples\nbody_gravity\build.bat (this file)
REM   <dragonruby_root>\include\dragonruby.h
REM   <dragonruby_root>\drecs\ext\drecs_kernel.h
REM
REM Output goes to drecs\native\windows-amd64\ so DR.dlopen "nbody_kernel"
REM finds it via DragonRuby's native-library search.

setlocal
set DR_INCLUDE=..\..\..\include
set DRECS_INCLUDE=..\..\ext

set OUT_DIR=..\..\native\windows-amd64
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

gcc -shared -O2 ^
    -I"%DR_INCLUDE%" -I"%DRECS_INCLUDE%" ^
    -o "%OUT_DIR%\nbody_kernel.dll" ^
    app\nbody_kernel.c

if errorlevel 1 (
    echo Build failed.
    exit /b 1
)
echo Built %OUT_DIR%\nbody_kernel.dll