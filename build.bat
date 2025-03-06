@echo off
set DRB_ROOT=..\
if not exist native mkdir native
if not exist native\windows-amd64 mkdir native\windows-amd64

clang -isystem %DRB_ROOT% -shared ^
  -target x86_64-windows-gnu ^
  -I %DRB_ROOT%\include ^
  lib\ext.c ^
  -v ^
  -o native\windows-amd64\ext.dll