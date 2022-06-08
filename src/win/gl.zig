const std = @import("std");
const win = std.os.windows;

const gl = @cImport({
    @cInclude("gl/gl.h");
    @cInclude("gl/wgl.h");
});
// todo: is there a way to import locally and export at the same time?
pub usingnamespace @cImport({
    @cInclude("gl/gl.h");
});

// https://www.khronos.org/registry/OpenGL/extensions/ARB/WGL_ARB_pixel_format.txt
var wglChoosePixelFormatARB: fn(hdc: win.HDC, piAttribIList: ?*const c_int, pfAttribFList: ?*const win.FLOAT, nMaxFormats: win.UINT, piFormats: ?*const c_int, nNumFormats: ?*win.UINT) callconv(win.WINAPI) win.BOOL = undefined;
var wglCreateContextAttribsARB: fn(hdc: win.HDC, hShareContext: ?win.HGLRC, attribList: ?*const c_int) callconv(win.WINAPI) ?win.HGLRC = undefined;

pub fn loadFunction(comptime asType: type, name: [*:0]const u8) ?asType {
    return @ptrCast(asType, gl.wglGetProcAddress(name));
}

fn loadFunctions() !void {
    wglChoosePixelFormatARB = loadFunction(@TypeOf(wglChoosePixelFormatARB), "wglChoosePixelFormatARB") orelse return error.Unexpected;
    wglCreateContextAttribsARB = loadFunction(@TypeOf(wglCreateContextAttribsARB), "wglCreateContextAttribsARB") orelse return error.Unexpected;
}

fn initBasicContext(device: win.HDC) !win.HGLRC {
    const PFD_DRAW_TO_WINDOW = 0x00000004;
    const PFD_SUPPORT_OPENGL = 0x00000020;
    const PFD_DOUBLEBUFFER = 0x00000001;
    const PFD_TYPE_RGBA = 0;
    const PFD_MAIN_PLANE = 0;

    const descriptor = win.gdi32.PIXELFORMATDESCRIPTOR {
        .nVersion = 1,
        .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .iPixelType = PFD_TYPE_RGBA,
        .cColorBits = 32,
        .cRedBits = 0,
        .cRedShift = 0,
        .cGreenBits = 0,
        .cGreenShift = 0,
        .cBlueBits = 0,
        .cBlueShift = 0,
        .cAlphaBits = 0,
        .cAlphaShift = 0,
        .cAccumBits = 0,
        .cAccumRedBits = 0,
        .cAccumGreenBits = 0,
        .cAccumBlueBits = 0,
        .cAccumAlphaBits = 0,
        .cDepthBits = 24,
        .cStencilBits = 8,
        .cAuxBuffers = 0,
        .iLayerType = PFD_MAIN_PLANE,
        .bReserved = 0,
        .dwLayerMask = 0,
        .dwVisibleMask = 0,
        .dwDamageMask = 0,
    };

    const pixelFormat = win.gdi32.ChoosePixelFormat(device, &descriptor);
    if (!win.gdi32.SetPixelFormat(device, pixelFormat, &descriptor))
        return error.Unexpected;

    if (win.gdi32.wglCreateContext(device)) |context| {
        return context;
    } else return error.Unexpected;
}

fn initProperContext(device: win.HDC) !win.HGLRC {
    std.debug.assert(wglChoosePixelFormatARB != undefined);
    std.debug.assert(wglCreateContextAttribsARB != undefined);

    const PFD_DRAW_TO_WINDOW = 0x00000004;
    const PFD_SUPPORT_OPENGL = 0x00000020;
    const PFD_DOUBLEBUFFER = 0x00000001;
    const PFD_TYPE_RGBA = 0;
    const PFD_MAIN_PLANE = 0;

    // https://docs.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-pixelformatdescriptor
    const descriptor = win.gdi32.PIXELFORMATDESCRIPTOR {
        .nVersion = 1,
        .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .iPixelType = PFD_TYPE_RGBA,
        .cColorBits = 32,
        .cRedBits = 0,
        .cRedShift = 0,
        .cGreenBits = 0,
        .cGreenShift = 0,
        .cBlueBits = 0,
        .cBlueShift = 0,
        .cAlphaBits = 0,
        .cAlphaShift = 0,
        .cAccumBits = 0,
        .cAccumRedBits = 0,
        .cAccumGreenBits = 0,
        .cAccumBlueBits = 0,
        .cAccumAlphaBits = 0,
        .cDepthBits = 24,
        .cStencilBits = 8,
        .cAuxBuffers = 0,
        .iLayerType = PFD_MAIN_PLANE,
        .bReserved = 0,
        .dwLayerMask = 0,
        .dwVisibleMask = 0,
        .dwDamageMask = 0,
    };

    const attribList = [_]c_int{
        gl.WGL_DRAW_TO_WINDOW_ARB, gl.GL_TRUE,
        gl.WGL_SUPPORT_OPENGL_ARB, gl.GL_TRUE,
        gl.WGL_DOUBLE_BUFFER_ARB, gl.GL_TRUE,
        gl.WGL_PIXEL_TYPE_ARB, gl.WGL_TYPE_RGBA_ARB,
        gl.WGL_COLOR_BITS_ARB, 32,
        gl.WGL_DEPTH_BITS_ARB, 24,
        gl.WGL_STENCIL_BITS_ARB, 8,
        0, // END
    };

    var pixelFormat: c_int = undefined;
    var numFormats: win.UINT = undefined;
    if (wglChoosePixelFormatARB(device, &attribList[0], null, 1, &pixelFormat, &numFormats) == 0)
        return error.Unexpected;
    _ = numFormats;

    if (!win.gdi32.SetPixelFormat(device, pixelFormat, &descriptor))
        return error.Unexpected;

    if (wglCreateContextAttribsARB(device, null, null)) |context| {
        return context;
    } else return error.Unexpected;
}

pub fn deinitGlContext(context: win.HGLRC) !void {
    const wglDeleteContext = @extern(fn(oldContext: win.HGLRC) callconv(win.WINAPI) bool, .{ .name = "wglDeleteContext" });

    if (!win.gdi32.wglMakeCurrent(null, null))
        return error.Unexpected;
    if (!wglDeleteContext(context))
        return error.Unexpected;
}

pub fn initGlContext(device: win.HDC) !win.HGLRC {
    // We required to create context to get WGL_ARB_pixel_format extension function pointers
    const dummyContext = try initBasicContext(device);
    if (!win.gdi32.wglMakeCurrent(device, dummyContext))
        return error.Unexpected;
    try loadFunctions();
    try deinitGlContext(dummyContext);
    return initProperContext(device);
}

pub const GlVersion = struct {
    majorVersion: u8,
    minorVersion: u8,
};

pub fn getGlVersion() !GlVersion {
    if (@ptrCast(?[*:0]const u8, gl.glGetString(gl.GL_VERSION))) |version| {
        const size = std.mem.len(version);
        const endOfVesionString = std.mem.indexOfScalar(u8, version[0..size], ' ') orelse size;
        const endOfMajorVersion = std.mem.indexOfScalar(u8, version[0..size], '.') orelse return error.Unexpected;
        return GlVersion{
            .majorVersion = try std.fmt.parseUnsigned(u8, version[0..endOfMajorVersion], 10),
            .minorVersion = try std.fmt.parseUnsigned(u8, version[(endOfMajorVersion + 1)..(endOfVesionString - 2)], 10),
        };
    } else return error.Unexpected;
}
