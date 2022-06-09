const std = @import("std");
const win = std.os.windows;
const winapi = @import("winapi.zig");
const gl = @import("gl.zig");

// todo: Ability to override the window title
const default_window_title = "ASD engine";

extern var render_callback: ?fn()void;
extern var resize_callback: ?fn(width: c_uint, height: c_uint)void;
extern fn initEngine() void;
extern fn deinitEngine() void;

pub export fn main() void {
    const hInstance = @ptrCast(win.HINSTANCE, winapi.GetModuleHandleA(null) orelse unreachable);

    const className = std.unicode.utf8ToUtf16LeStringLiteral("OpenGL");
    const class = win.user32.WNDCLASSEXW {
        .lpszClassName = className,
        .lpfnWndProc = messageCallback,
        .hInstance = hInstance,
        .style = win.user32.CS_OWNDC | win.user32.CS_HREDRAW | win.user32.CS_VREDRAW,
        .hIcon = null,
        .hIconSm = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
    };

    _ = win.user32.registerClassExW(&class) catch @panic("cannot register class");

    const window = win.user32.createWindowExW(
        0,
        className,
        std.unicode.utf8ToUtf16LeStringLiteral(default_window_title),
        win.user32.WS_OVERLAPPEDWINDOW,
        win.user32.CW_USEDEFAULT, win.user32.CW_USEDEFAULT,
        640, 480,
        null, null, hInstance, null
    ) catch @panic("cannot create window");

    _ = win.user32.showWindow(window, winapi.SW_SHOWNORMAL);

    messageloop: while (true) {
        var msg: win.user32.MSG = undefined;
        if (win.user32.getMessageW(&msg, null, 0, 0)) {
            _ = win.user32.translateMessage(&msg);
            _ = win.user32.dispatchMessageW(&msg);
        } else |err| switch (err) {
            error.Quit => break :messageloop,
            else => @panic("error getting message in event loop"),
        }
    }
}

fn messageCallback(hwnd: win.HWND, uMsg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(win.WINAPI) win.LRESULT {
    const glcontext = struct {
        var device: win. HDC = undefined;
        var handle: win.HGLRC = undefined;
    };

    switch (uMsg) {
        win.user32.WM_CREATE => {
            glcontext.device = win.user32.getDC(hwnd) catch @panic("cannot get device handle");
            glcontext.handle = gl.initGlContext(glcontext.device) catch @panic("cannot initialize opengl context");
            if (!win.gdi32.wglMakeCurrent(glcontext.device, glcontext.handle))
                @panic("cannot make gl context current");
            initEngine();
        },
        win.user32.WM_DESTROY => {
            deinitEngine();
            if (!win.user32.releaseDC(hwnd, glcontext.device)) @panic("cannot release device context");
            gl.deinitGlContext(glcontext.handle) catch @panic("cannot deinit gl context");
            win.user32.postQuitMessage(0);
        },
        win.user32.WM_PAINT => {
            if (render_callback) |render| render();
            if (!win.gdi32.SwapBuffers(glcontext.device))
                @panic("cannot swap buffers");
        },
        win.user32.WM_SIZE => {
            if (resize_callback) |callback| callback(@intCast(c_uint, @truncate(i16, lParam)), @intCast(c_uint, @truncate(i16, lParam >> 16)));
        },
        else => return win.user32.defWindowProcW(hwnd, uMsg, wParam, lParam),
    }
    return 0;
}
