const std = @import("std");
const engine = @import("engine.zig");
const tracker = @import("tracker.zig");

// const BlockType = enum(u8) {
//   grey, // Inert block
//   end, // Activator piece
//   _,
// };

const Color = [4]f32;

// const initQueueSize: u8 = 4;
const backgroundColor = Color{ 0.15, 0.10, 0.20, 1.00 };

var windowWidth: u32 = 640;
var windowHeight: u32 = 480;

var writer: engine.console.WriterType = undefined;

// var queue: [128]BlockType = undefined;
// var queueSize: u8 = 4;

// var blockWidth: f32 = undefined;
// var blockHeight: f32 = undefined;

export fn initEngine() void {
    _ = engine.setRenderCallback(render);
    _ = engine.setResizeCallback(resize);
    tracker.play() catch |err| {
        writer.print("Tracker error: {err}", .{err}) catch @panic("cannot print");
    };
    // setupGame(initQueueSize);
}

// fn setupGame(size: u8) void {
//   queueSize = size;
//   std.mem.set(BlockType, queue[0..(size - 2)], .grey);
//   queue[size - 1] = .end;
// }

fn applyColor(comptime func: anytype, color: Color) callconv(.Inline) void {
    @call(.{}, func, .{ color[0], color[1], color[2], color[3] });
}

// fn drawBlock(kind: BlockType, offset: u8) void {
//   const x1: f32 = -1.0 + (blockWidth * @intToFloat(f32, offset)) * 2.0;
//   const y1: f32 = 0.0 - blockHeight;
//   const x2: f32 = -1.0 + (blockWidth * @intToFloat(f32, offset + 1)) * 2.0;
//   const y2: f32 = 0.0 + blockHeight;
//   const color: Color = switch (kind) {
//     .grey => .{ 0.25, 0.25, 0.25, 1.00 },
//     .end  => .{ 1.00, 1.00, 1.00, 1.00 },
//     else => unreachable,
//   };
//   applyColor(engine.glColor4f, color);
//   engine.glRectf(x1, y1, x2, y2);
// }

fn render() void {
    applyColor(engine.glClearColor, backgroundColor);
    engine.glClear(engine.GL_COLOR_BUFFER_BIT);

    // for (queue[0..queueSize]) |kind, offset| {
    //   drawBlock(kind, @intCast(u8, offset));
    // }
}

fn resize(width: c_uint, height: c_uint) void {
    _ = width;
    _ = height;

    // windowWidth = @intCast(u32, width);
    // windowHeight = @intCast(u32, height);

    // const windowWidthFloat = @intToFloat(f32, width);
    // const windowHeightFloat = @intToFloat(f32, height);
    // const queueSizeFloat = @intToFloat(f32, queueSize);

    // todo: search for appropriate ratio

    // blockWidth = (windowWidthFloat / queueSizeFloat) / windowWidthFloat;
    // blockHeight = (windowWidthFloat / queueSizeFloat) / windowHeightFloat;
}
