const std = @import("std");
const win = std.os.windows;
const winapi = @import("winapi.zig");

const WriterContext = struct { handle: win.HANDLE, };
pub const WriterType = std.io.Writer(WriterContext, WriterError, write);
pub const WriterError = error { CannotWrite, NotFullyPrinted, };

// todo: Cache GetStdHandle result after first getting? Should work if std handles are guaranteed to live in whole lifespan of process
pub fn Writer() !WriterType {
    const outHandle = win.GetStdHandle(win.STD_OUTPUT_HANDLE);
    if (outHandle) |handle| {
        return WriterType { .context = .{ .handle = handle } };
    } else |err| return err;
}

fn write(context: WriterContext, string: []const u8) WriterError!usize {
    var charsWritten: win.DWORD = undefined;
    if (winapi.WriteConsoleA(context.handle, &string[0], @intCast(win.DWORD, string.len), &charsWritten, null) == 0) {
        std.debug.print("windows error code on attempt to write to std_output_handle: {x}\n", .{winapi.GetLastError()});
        return WriterError.CannotWrite;
    }
    if (charsWritten != string.len)
        return WriterError.NotFullyPrinted;
    return charsWritten;
}
