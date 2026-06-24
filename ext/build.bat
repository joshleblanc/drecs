@echo off
REM Build the drecs parallel runtime DLL.
REM Run from drecs\ext\.
setlocal
set DR_INCLUDE=..\..\..\include

REM Output to drecs\native\windows-amd64\ so DR.dlopen "drecs_parallel" finds it.
set OUT_DIR=..\native\windows-amd64
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

gcc -shared -O2 ^
    -I"%DR_INCLUDE%" ^
    -o "%OUT_DIR%\drecs_parallel.dll" ^
    drecs_parallel.c

if errorlevel 1 (
    echo Build failed.
    exit /b 1
)
echo Built %OUT_DIR%\drecs_parallel.dll
