pub usingnamespace @import("win/gl.zig");
pub const console = @import("win/console.zig");

export var render_callback: ?fn()void = null;
export var resize_callback: ?fn(width: c_uint, height: c_uint)void = null;

pub fn setRenderCallback(callback: @TypeOf(render_callback)) @TypeOf(render_callback) {
    const prev = render_callback;
    render_callback = callback;
    return prev;
}

pub fn setResizeCallback(callback: @TypeOf(resize_callback)) @TypeOf(resize_callback) {
    const prev = resize_callback;
    resize_callback = callback;
    return prev;
}
