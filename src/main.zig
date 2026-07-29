//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

fn key_to_button(sym: c.SDL_Keycode) ?Joypad.Button {
    return switch (sym) {
        c.SDLK_RIGHT => .Right,
        c.SDLK_LEFT => .Left,
        c.SDLK_UP => .Up,
        c.SDLK_DOWN => .Down,
        c.SDLK_x => .A,
        c.SDLK_z => .B,
        c.SDLK_BACKSPACE => .Select,
        c.SDLK_RETURN => .Start,
        else => null,
    };
}

pub fn main() !void {
    tracy.setThreadName("Main");
    defer tracy.message("Graceful main thread exit");

    Logger.init();
    defer Logger.deinit();

    //  Get an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("leak?");
    }
    const allocator = gpa.allocator();

    var enable_tracer = false;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); //executable name
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--enable-tracer")) {
            enable_tracer = true;
        } else {
            std.debug.print("unknown argument: {s}\n", .{arg});
            return error.UnknownArgument;
        }
    }
    //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena.deinit();
    //const allocator = arena.allocator();

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, (Gpu.RESOLUTION_WIDTH + 10 + Gpu.TILEDEBUG_WIDTH) * 2, Gpu.TILEDEBUG_HEIGHT * 2, c.SDL_WINDOW_OPENGL) orelse
        {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
    defer c.SDL_DestroyWindow(screen);
    c.SDL_SetWindowResizable(screen, 1);
    c.SDL_SetWindowMinimumSize(screen, Gpu.RESOLUTION_WIDTH + 10 + Gpu.TILEDEBUG_WIDTH, Gpu.TILEDEBUG_HEIGHT);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);
    _ = c.SDL_GL_SetSwapInterval(0);

    var quit = false;

    const gameTexture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, Gpu.RESOLUTION_WIDTH, Gpu.RESOLUTION_HEIGHT);
    defer c.SDL_DestroyTexture(gameTexture);

    //tiles_column = 16
    //tiles_row = 24
    //tiles 8x8
    const tilesTexture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA8888,
        c.SDL_TEXTUREACCESS_STREAMING,
        Gpu.TILEDEBUG_WIDTH,
        Gpu.TILEDEBUG_HEIGHT,
    );
    defer c.SDL_DestroyTexture(tilesTexture);

    var emulator = try Emulator.Init(allocator, enable_tracer);
    defer emulator.close();

    const lock_framerate = false;

    var prev_time = try std.time.Instant.now();

    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_KEYDOWN => {
                    const button = key_to_button(event.key.keysym.sym) orelse continue;
                    emulator.system.joypad.Press(button);
                },
                c.SDL_KEYUP => {
                    const button = key_to_button(event.key.keysym.sym) orelse continue;
                    emulator.system.joypad.Release(button);
                },
                c.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }
        const zone = tracy.beginZone(@src(), .{ .name = "window loop" });
        defer zone.end();

        //const delta_time = (try std.time.Instant.now()).since(prev_time);
        prev_time = try std.time.Instant.now();

        try emulator.run_until_frameready();

        const pixels = emulator.getFrameBuffer();
        const tilesPixels = emulator.snapshotTiles();
        copy_framebuffer_to_SDL_tex(pixels, gameTexture);
        copy_framebuffer_to_SDL_tex(tilesPixels, tilesTexture);

        var screen_width: c_int = 0;
        var screen_height: c_int = 0;
        c.SDL_GetWindowSize(screen, @ptrCast(&screen_width), @ptrCast(&screen_height));
        const ratio = @divTrunc(screen_height, Gpu.TILEDEBUG_HEIGHT);

        _ = c.SDL_SetRenderDrawColor(renderer, 0x30, 0x30, 0x30, 0xFF);
        _ = c.SDL_RenderClear(renderer);
        const gameRect = c.SDL_Rect{ .x = 0, .y = 0, .w = Gpu.RESOLUTION_WIDTH * ratio, .h = Gpu.RESOLUTION_HEIGHT * ratio };
        const tilesRect = c.SDL_Rect{ .x = Gpu.RESOLUTION_WIDTH * ratio + 10, .y = 0, .w = Gpu.TILEDEBUG_WIDTH * ratio, .h = Gpu.TILEDEBUG_HEIGHT * ratio };
        _ = c.SDL_RenderCopy(renderer, gameTexture, null, &gameRect);
        _ = c.SDL_RenderCopy(renderer, tilesTexture, null, &tilesRect);
        c.SDL_RenderPresent(renderer);

        const target_frame_time_ms = 16;
        const delta_time_ms = (try std.time.Instant.now()).since(prev_time) / std.time.ns_per_ms;
        if (lock_framerate and delta_time_ms < target_frame_time_ms) {
            c.SDL_Delay(target_frame_time_ms - @as(u32, @intCast(delta_time_ms)));
        }
    }
}

fn copy_framebuffer_to_SDL_tex(fbi: FrameBufferInfo, texture: ?*c.SDL_Texture) void {
    const color_depth = 4;
    const alpha: u8 = 255;
    var pitch: c_int = 0;
    var bytes: [*c]c_char = undefined;
    _ = c.SDL_LockTexture(texture, null, @ptrCast(&bytes), @ptrCast(&pitch));
    for (0..fbi.height) |y| {
        for (0..fbi.width) |x| {
            const fbc = fbi.framebuffer[(y * fbi.width + x)];

            bytes[(y * fbi.width + x) * @sizeOf(u8) * color_depth] = @bitCast(alpha); //alpha
            bytes[(y * fbi.width + x) * @sizeOf(u8) * color_depth + 1] = @bitCast(fbc); //blue
            bytes[(y * fbi.width + x) * @sizeOf(u8) * color_depth + 2] = @bitCast(fbc); //green
            bytes[(y * fbi.width + x) * @sizeOf(u8) * color_depth + 3] = @bitCast(fbc); //red
            //@memcpy(&bytes[(y * fbi.width + x) * @sizeOf(u8) * rgba.len], rgba);
        }
    }
    c.SDL_UnlockTexture(texture);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const tracy = @import("tracy");
//pub const cpu_functions = @import("cpu_functions.zig");
const Logger = @import("logger.zig");
const emulator_import = @import("emulator.zig");
const Emulator = emulator_import.Emulator;
const FrameBufferInfo = emulator_import.FrameBufferInfo;
const Joypad = @import("joypad.zig").Joypad;
const Gpu = @import("gpu.zig").Gpu;

// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zig_hello_world_lib");
//const lib = @import("root.zig");
const expect = std.testing.expect;
