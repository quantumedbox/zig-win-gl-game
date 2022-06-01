zig build-obj src/game.zig -I c:/env/tools/mingw64/x86_64-w64-mingw32/include -O ReleaseSmall
zig build-exe src/win/entry.zig game.obj -lopengl32 -I c:/env/tools/mingw64/x86_64-w64-mingw32/include -O ReleaseSmall
rem todo: make proper build
