const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    var exe = b.addExecutable("asd", "src/win/entry.zig");
    exe.setBuildMode(mode);

    var game = b.addObject("game", "src/game.zig");
    game.addIncludeDir("c:/env/tools/mingw64/x86_64-w64-mingw32/include");
    // game.linkLibC();
    game.addIncludeDir("./inc");

    exe.addObject(game);

    exe.addIncludeDir("./inc");
    exe.addIncludeDir("c:/env/tools/mingw64/x86_64-w64-mingw32/include");
    exe.addLibraryPath("libs");
    exe.linkLibC();
    exe.linkSystemLibrary("portaudio");
    exe.linkSystemLibrary("openmpt");
    exe.linkSystemLibrary("opengl32");
    exe.setOutputDir("./");
    exe.install();
}
