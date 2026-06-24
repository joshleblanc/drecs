@echo off
REM Build my_systems.dll for the native_systems sample.
REM
REM Layout assumed:
REM   <dragonruby_root>\drecs\samples\native_systems\build.bat (this file)
REM   <dragonruby_root>\include\dragonruby.h
REM   <dragonruby_root>\drecs\ext\drecs_kernel.h
REM
REM Output goes to native\windows-amd64\my_systems.dll inside this sample.

setlocal
set DR_INCLUDE=..\..\..\include
set DRECS_INCLUDE=..\..\ext

REM Output to drecs\native\windows-amd64\ so DR.dlopen "my_systems" finds it.
set OUT_DIR=..\..\native\windows-amd64
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

gcc -shared -O2 ^
    -I"%DR_INCLUDE%" -I"%DRECS_INCLUDE%" ^
    -o "%OUT_DIR%\my_systems.dll" ^
    app\my_systems.c

if errorlevel 1 (
    echo Build failed.
    exit /b 1
)
echo Built %OUT_DIR%\my_systems.dll
