set DRB_ROOT=..

md native
md native\windows-amd64
git clone git@github.com:SanderMertens/flecs.git
%DRB_ROOT%\dragonruby-bind.exe --compiler-flags="--sysroot=C:\mingw64 -IC:\LLVM\lib\clang\10.0.0\include -std=c99" --output=native\ext-bind.c flecs\distr\flecs.h
clang.exe -shared .\native\ext-bind.c --sysroot=C:\mingw64 -IC:\LLVM\lib\clang\10.0.0\include -std=c99 --target=x86_64-w64-mingw32 -fuse-ld=lld -isystem %DRB_ROOT%\include -I. -o %DRB_ROOT%\mygame\native\windows-amd64\ext.dll