// https://lib.openmpt.org/doc/libopenmpt_c_overview.html

// todo: Define error set
// todo: Ability to change track at already existing player
// todo: Interspection of playback, such as BPM, how far in the track player is and etc.

const std = @import("std");
const engine = @import("engine.zig"); // todo: Shouldn't be hardcoded path, but implementation defined

const portaudio = @cImport({
    @cInclude("portaudio/portaudio.h");
});

const libopenmpt = @cImport({
    @cInclude("libopenmpt/libopenmpt.h");
    @cInclude("libopenmpt/libopenmpt_stream_callbacks_file.h");
});

const MAX_TRACKER_FILE_SIZE: usize = 1024 * 1024; // 1MiB

pub const REPEAT_FOREVER: i32 = -1;
pub const REPEAT_ONCE: i32 = 0;

const Filter = enum(c_int) {
    Default = 0,
    None = 1,
    Linear = 2,
    Cubic = 4,
};

const DEFAULT_SAMPLERATE: c_int = 44100;

pub const TrackerPlayer = struct {
    module: ?*libopenmpt.openmpt_module,
    stream: ?*portaudio.PaStream,
    samplerate: i32 = DEFAULT_SAMPLERATE,
    is_interleaved: bool,
    is_stopped: bool,

    const Self = @This();

    pub fn from_file(filename: []const u8, allocator: std.mem.Allocator) !*Self {
        const writer = try engine.console.Writer();

        var result = try allocator.create(Self);

        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var file_allocator = std.heap.page_allocator;
        var buffer = try file.readToEndAlloc(file_allocator, MAX_TRACKER_FILE_SIZE);
        defer file_allocator.free(buffer);

        var mod_err = libopenmpt.OPENMPT_ERROR_OK;
        var mod_err_str: [*c]const u8 = undefined;
        result.module = libopenmpt.openmpt_module_create_from_memory2(&buffer[0], buffer.len, logCallback, null, errorCallback, null, &mod_err, &mod_err_str, null) orelse {
            defer libopenmpt.openmpt_free_string(mod_err_str);
            try printError("openmpt_module_create2()", mod_err, mod_err_str);
            return error.Unexpected;
        };

        if (libopenmpt.openmpt_module_set_render_param(result.module, libopenmpt.OPENMPT_MODULE_RENDER_INTERPOLATIONFILTER_LENGTH, @enumToInt(Filter.None)) == 0)
            _ = try writer.write("openmpt_module_set_render_param() gave error\n");

        if (libopenmpt.openmpt_module_set_repeat_count(result.module, -1) == 0)
            _ = try writer.write("openmpt_module_set_repeat_count() gave error\n");

        var pa_error = portaudio.Pa_Initialize();
        if (pa_error != portaudio.paNoError) {
            try writer.print("Pa_Initialize() failed with error {x}\n", .{pa_error});
            return error.Unexpected;
        }

        var stream_params = std.mem.zeroes(portaudio.PaStreamParameters);
        stream_params.device = portaudio.Pa_GetDefaultOutputDevice();
        if (stream_params.device == portaudio.paNoDevice) {
            _ = try writer.write("Pa_GetDefaultOutputDevice() failed");
            return error.Unexpected;
        }

        result.samplerate = DEFAULT_SAMPLERATE;

        stream_params.channelCount = 2;
        stream_params.sampleFormat = portaudio.paInt16 | portaudio.paNonInterleaved;
        stream_params.suggestedLatency = portaudio.Pa_GetDeviceInfo(stream_params.device).*.defaultLowOutputLatency;

        pa_error = portaudio.Pa_OpenStream(&result.stream, null, &stream_params, @intToFloat(f64, result.samplerate), 0, portaudio.paNoFlag, trackerCallback, result);
        if (pa_error == portaudio.paSampleFormatNotSupported) {
            stream_params.sampleFormat = portaudio.paInt16;
            result.is_interleaved = true;
            pa_error = portaudio.Pa_OpenStream(&result.stream, null, &stream_params, @intToFloat(f64, result.samplerate), 0, portaudio.paNoFlag, trackerCallback, result);
        }
        if (pa_error != portaudio.paNoError or result.stream == null) {
            try writer.print("Pa_OpenDefaultStream() failed with error {x}\n", .{pa_error});
            return error.Unexpected;
        }

        pa_error = portaudio.Pa_StartStream(result.stream);
        if (pa_error != portaudio.paNoError) {
            try writer.print("Pa_StartStream() failed with error {x}\n", .{pa_error});
            return error.Unexpected;
        }

        return result;
    }

    pub fn stop(self: *Self) !void {
        std.debug.assert(!self.is_stopped);
        if (portaudio.Pa_StopStream(self.stream) != portaudio.paNoError)
            @panic("cannot stop portaudio stream");
        self.is_stopped = true;
    }

    pub fn play(self: *Self) !void {
        std.debug.assert(self.is_stopped);
        if (portaudio.Pa_StartStream(self.stream) != portaudio.paNoError)
            @panic("cannot stop portaudio stream");
        self.is_stopped = false;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.stop() catch @panic("cannot stop tracker player stream");
        if (portaudio.Pa_CloseStream(self.stream) != portaudio.paNoError)
            @panic("cannot close portaudio stream");
        if (portaudio.Pa_Terminate() != portaudio.paNoError)
            @panic("cannot terminate portaudio");
        libopenmpt.openmpt_module_destroy(self.module);
        allocator.destroy(self);
    }
};

// todo: We could render frames in advance for callback to consume, could produce less overhead
// note: It currently assumes stereo output, we might consider providing hint whether it's mono or stereo
fn trackerCallback(inputBuffer: ?*const anyopaque, outputBuffer: ?*anyopaque, framesPerBuffer: c_ulong, timeInfo: [*c]const portaudio.PaStreamCallbackTimeInfo, statusFlags: portaudio.PaStreamCallbackFlags, userData: ?*anyopaque) callconv(.C) c_int {
    _ = inputBuffer;
    _ = timeInfo;
    _ = statusFlags;

    std.debug.assert(userData != null);
    std.debug.assert(outputBuffer != null);

    var data = @ptrCast(*TrackerPlayer, @alignCast(@alignOf(TrackerPlayer), userData)); // todo: Should we pass all data here? It makes it simple, but could be problematic

    libopenmpt.openmpt_module_error_clear(data.module);

    var count: usize = undefined;
    if (data.is_interleaved) {
        var output = @ptrCast([*]i16, @alignCast(@alignOf(i16), outputBuffer));
        count = libopenmpt.openmpt_module_read_interleaved_stereo(data.module, data.samplerate, framesPerBuffer, &output[0]);
    } else {
        var output = @ptrCast([*][*]i16, @alignCast(@alignOf([*]i16), outputBuffer));
        count = libopenmpt.openmpt_module_read_stereo(data.module, data.samplerate, framesPerBuffer, output[0], output[1]);
    }
    // todo: What to do if count != framesPerBuffer? It might mean different things depending on whether track is playing repeatedly or not

    // todo: Might be quite slow IO, better create some sort of queue with pending strings to output, that is dispatched separately
    // Check errors
    var mod_err = libopenmpt.openmpt_module_error_get_last(data.module);
    if (mod_err != libopenmpt.OPENMPT_ERROR_OK) {
        var mod_err_str = libopenmpt.openmpt_module_error_get_last_message(data.module);
        defer libopenmpt.openmpt_free_string(mod_err_str);
        printError("openmpt_module_read_stereo()", mod_err, mod_err_str) catch @panic("cannot print error");
    }

    return portaudio.paContinue;
}

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
