// https://lib.openmpt.org/doc/libopenmpt_c_overview.html

const std = @import("std");
const engine = @import("engine.zig"); // todo: Shouldn't be hardcoded path, but implementation defined

const portaudio = @cImport({
    @cInclude("portaudio/portaudio.h");
});

const libopenmpt = @cImport({
    @cInclude("libopenmpt/libopenmpt.h");
    @cInclude("libopenmpt/libopenmpt_stream_callbacks_file.h");
});

const MAX_TRACKER_FILE_SIZE: usize = 512 * 1024; // 512KB

pub const REPEAT_FOREVER: i32 = -1;
pub const REPEAT_ONCE: i32 = 0;

const Filter = enum(c_int) {
    Default = 0,
    None = 1,
    Linear = 2,
    Cubic = 4,
};

const BUFFER_SIZE: c_int = 480;
const SAMPLE_RATE: c_int = 48000;

var left: [BUFFER_SIZE]i16 = [_]i16{0} ** BUFFER_SIZE;
var right: [BUFFER_SIZE]i16 = [_]i16{0} ** BUFFER_SIZE;
var buffers: [2]*[BUFFER_SIZE]i16 = .{ &left, &right};
var interleaved_buffer: [BUFFER_SIZE * 2]i16 = undefined;
var is_interleaved = false;


fn logCallback(msg: ?[*:0]const u8, userData: ?*anyopaque) callconv(.C) void {
    _ = userData;
    if (msg) |text| {
        if (engine.console.Writer()) |writer| {
            writer.print("{s}\n", .{text}) catch {
                @panic("writer error in log callback");
            };
        } else |err| {
            _ = err catch {};
            @panic("cannot get console handle for logging");
        }
    }
}

fn errorCallback(err: c_int, userData: ?*anyopaque) callconv(.C) c_int {
    _ = err;
    _ = userData;
    return libopenmpt.OPENMPT_ERROR_FUNC_RESULT_DEFAULT & ~libopenmpt.OPENMPT_ERROR_FUNC_RESULT_LOG;
}

fn printError(func_name: ?[*:0]const u8, mod_err: c_int, mod_err_str: ?[*:0]const u8) !void {
    const writer = engine.console.Writer() catch @panic("cannot get console handle");
    if (mod_err == libopenmpt.OPENMPT_ERROR_OUT_OF_MEMORY) {
        if (libopenmpt.openmpt_error_string(mod_err)) |err_str| {
            defer libopenmpt.openmpt_free_string(err_str);
            try writer.print("error: {s}\n", .{err_str});
        } else {
            try writer.print("error: OPENMPT_ERROR_OUT_OF_MEMORY\n", .{});
        }
    } else {
        if (mod_err_str) |err_str| {
            try writer.print("error: function {s} failed: {s}\n", .{func_name, err_str});
        } else {
            if (libopenmpt.openmpt_error_string(mod_err)) |err_str| {
                defer libopenmpt.openmpt_free_string(err_str);
                try writer.print("error: function {s} failed: {s}\n", .{func_name, err_str});
            } else {
                try writer.print("error: function {s} failed\n", .{func_name});
            }
        }
    }
}

pub fn play() !void {
    const writer = try engine.console.Writer();

    var file = try std.fs.cwd().openFile("tracks/evilness.it", .{});
    defer file.close();

    var allocator = std.heap.page_allocator;
    var buffer = try file.readToEndAlloc(allocator, MAX_TRACKER_FILE_SIZE);
    defer allocator.free(buffer);

    var mod_err = libopenmpt.OPENMPT_ERROR_OK;
    var mod_err_str: [*c]const u8 = undefined;
    var module = libopenmpt.openmpt_module_create_from_memory2(&buffer[0], buffer.len, logCallback, null, errorCallback, null, &mod_err, &mod_err_str, null);
    if (module == null) {
        defer libopenmpt.openmpt_free_string(mod_err_str);
        try printError("openmpt_module_create2()", mod_err, mod_err_str);
        mod_err_str = null;
        return error.Unexpected;
    }
    defer libopenmpt.openmpt_module_destroy(module);

    if (libopenmpt.openmpt_module_set_render_param(module, libopenmpt.OPENMPT_MODULE_RENDER_INTERPOLATIONFILTER_LENGTH, @enumToInt(Filter.None)) == 0)
        _ = try writer.write("openmpt_module_set_render_param() gave error\n");

    if (libopenmpt.openmpt_module_set_repeat_count(module, -1) == 0)
        _ = try writer.write("openmpt_module_set_repeat_count() gave error\n");

    var pa_error = portaudio.Pa_Initialize();
    if (pa_error != portaudio.paNoError) {
        try writer.print("Pa_Initialize() failed with error {x}\n", .{pa_error});
        return error.Unexpected;
    }
    defer {
        if (portaudio.Pa_Terminate() != portaudio.paNoError) {
            @panic("cannot terminate portaudio");
        }
    }

    var stream: ?*portaudio.PaStream = null;
    pa_error = portaudio.Pa_OpenDefaultStream(&stream, 0, 2, portaudio.paInt16 | portaudio.paNonInterleaved, SAMPLE_RATE, portaudio.paFramesPerBufferUnspecified, null, null);
    if (pa_error == portaudio.paSampleFormatNotSupported) {
        is_interleaved = true;
        pa_error = portaudio.Pa_OpenDefaultStream(&stream, 0, 2, portaudio.paInt16, SAMPLE_RATE, portaudio.paFramesPerBufferUnspecified, null, null);
    }
    if (pa_error != portaudio.paNoError or stream == null) {
        try writer.print("Pa_OpenDefaultStream() failed with error {x}\n", .{pa_error});
        return error.Unexpected;
    }
    defer {
        if (portaudio.Pa_IsStreamActive(stream) == 1) {
            if (portaudio.Pa_StopStream(stream) != portaudio.paNoError) {
                @panic("cannot stop portaudio stream");
            }
        }
        if (portaudio.Pa_CloseStream(stream) != portaudio.paNoError) {
            @panic("cannot close portaudio stream");
        }
    }

    pa_error = portaudio.Pa_StartStream(stream);
    if (pa_error != portaudio.paNoError) {
        try writer.print("Pa_StartStream() failed with error {x}\n", .{pa_error});
        return error.Unexpected;
    }

    var count: usize = 0;
    // todo: Start new thread, or alternatively define it via callback, so that stream would ask for data appropriately
    while (true) {
        libopenmpt.openmpt_module_error_clear(module);

        // Get samples
        if (is_interleaved) {
            count = libopenmpt.openmpt_module_read_interleaved_stereo(module, SAMPLE_RATE, BUFFER_SIZE, &interleaved_buffer);
        } else {
            count = libopenmpt.openmpt_module_read_stereo(module, SAMPLE_RATE, BUFFER_SIZE, &left, &right);
        }

        // Check errors
        mod_err = libopenmpt.openmpt_module_error_get_last(module);
        mod_err_str = libopenmpt.openmpt_module_error_get_last_message(module);
        if (mod_err != libopenmpt.OPENMPT_ERROR_OK) {
            defer libopenmpt.openmpt_free_string(mod_err_str);
            try printError("openmpt_module_read_stereo()", mod_err, mod_err_str);
            mod_err_str = null;
        }

        // End of track
        if (count == 0)
            break;

        // Write samples to stream
        pa_error = portaudio.Pa_WriteStream(stream, if (is_interleaved) &interleaved_buffer else &buffers, @intCast(c_ulong, count));
        if (pa_error == portaudio.paOutputUnderflowed)
            pa_error = portaudio.paNoError;
        if (pa_error != portaudio.paNoError) {
            try writer.print("Pa_WriteStream() failed, error: {x}\n", .{pa_error});
            return error.Unexpected;
        }
    }
}
