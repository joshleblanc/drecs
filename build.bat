set DRB_ROOT=..

md native
md native\windows-amd64
clang.exe -v -shared .\native\flecs-bind.c --sysroot=C:\mingw64 --target=x86_64-w64-mingw32 -fuse-ld=lld -isystem %DRB_ROOT%\include -I. -Dflecs_EXPORTS -DFLECS_NO_CPP -DFLECS_USE_OS_ALLOC -std=gnu99 -lws2_32 -o %DRB_ROOT%\mygame\native\windows-amd64\flecs-ext.dll