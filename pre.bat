set DRB_ROOT=..\
md native
md native\windows-amd64
@REM clang -v -shared .\external\flecs.c --sysroot=C:\mingw64 -std=gnu99 --target=x86_64-w64-mingw32 -fuse-ld=lld -isystem %DRB_ROOT%\include -I. -lWs2_32 -o native\flecs.o
clang -v -shared .\app\ext.c --sysroot=C:\mingw64 -std=gnu99 --target=x86_64-w64-mingw32 -fuse-ld=lld -isystem %DRB_ROOT%\include -I.  -DCMAKE_EXPORT_COMPILE_COMMANDS=1 -lWs2_32 -o native\windows-amd64\flecs.dll
