const std = @import("std");
const win = std.os.windows;

const WriterContext = struct { handle: win.HANDLE, };
const WriterType = std.io.Writer(WriterContext, WriterError, Write);
const WriterError = error { CannotWrite, NotFullyPrinted, };

pub fn Writer() !WriterType {
  const outHandle = win.GetStdHandle(win.STD_OUTPUT_HANDLE);
  if (outHandle) |handle| {
    return WriterType { .context = .{ .handle = handle } };
  } else |err| return err;
}

extern "kernel32" fn WriteConsoleA(hConsoleOutput: win.HANDLE, lpBuffer: ?*const anyopaque, nNumberOfCharsToWrite: win.DWORD, lpNumberOfCharsWritten: ?*win.DWORD, lpReserved: ?*anyopaque) callconv(win.WINAPI) win.BOOL;
fn write(context: WriterContext, string: []const u8) WriterError!usize {
  var charsWritten: win.DWORD = undefined;
  if (WriteConsoleA(context.handle, &string[0], @intCast(win.DWORD, string.len), &charsWritten, null) == 0)
    return WriterError.CannotWrite;
  if (charsWritten != string.len)
    return WriterError.NotFullyPrinted;
  return charsWritten;
}
