@echo off
echo Building DragonRuby C Extension

set DRB_ROOT=..\
if not exist native mkdir native
if not exist native\windows-amd64 mkdir native\windows-amd64

echo Compiling ext.c to ext.dll...
clang -shared .\lib\ext.c ^
  --sysroot=C:\mingw64 ^
  --target=x86_64-w64-mingw32 ^
  -fuse-ld=lld ^
  -isystem %DRB_ROOT%\include ^
  -I. ^
  -Wall ^
  -Wno-unused-function ^
  -g ^
  -O0 ^
  -o native\windows-amd64\ext.dll

if %ERRORLEVEL% NEQ 0 (
  echo Build failed with error code %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)

echo Build completed successfully!
echo DLL location: native\windows-amd64\ext.dll