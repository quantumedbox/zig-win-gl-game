pub usingnamespace @import("win/gl.zig");

export var render_callback: ?fn()void = null;
export var resize_callback: ?fn(width: c_uint, height: c_uint)void = null;

pub fn setRenderCallback(callback: @TypeOf(render_callback)) void {
  render_callback = callback;
}

pub fn setResizeCallback(callback: @TypeOf(resize_callback)) void {
  resize_callback = callback;
}
