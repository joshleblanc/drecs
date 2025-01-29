set DRB_ROOT=..

md native
md native\windows-amd64
%DRB_ROOT%\dragonruby-bind.exe --ffi-module=FLECS --compiler-flags="--sysroot=C:\mingw64 -IC:\LLVM\lib\clang\10.0.0\include -std=c99" --output=native\flecs-bind.c external\flecs-bind.h

powershell -Command "(gc native\flecs-bind.c) -replace 'sizeof\((.+) \(.+\) __attribute__\(\(.+\)\)\);', 'sizeof($1*));' | Out-File -encoding ASCII native\flecs-bind.c"

powershell -Command "(gc native\flecs-bind.c) | ForEach-Object { if ($_ -match '#include ""external\\flecs-bind.h""') { '#include \""external\flecs.h\""', '#include \""external\flecs.c\""' } else { $_ } } | Out-File -encoding ASCII native\flecs-bind.c"

REM sizeof\((.+) \(.+\) __attribute__\(\(.+\)\)\);
REM sizeof($1*));