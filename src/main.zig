//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

fn load_rom(abs_rom_location: []const u8, max_bytes: usize, allocator: Allocator) ![]u8 {
    var file = try std.fs.openFileAbsolute(abs_rom_location, .{});
    defer file.close();

    // Read the contents
    const cartridge_rom = try file.readToEndAlloc(allocator, max_bytes);

    return cartridge_rom;
}

pub fn main() !void {
    tracy.setThreadName("Main");
    defer tracy.message("Graceful main thread exit");

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

    var emulator = try Emulator.Init();
    defer emulator.close();

    var prev_time = try std.time.Instant.now();

    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
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

        _ = c.SDL_RenderClear(renderer);
        const gameRect = c.SDL_Rect{ .x = 0, .y = 0, .w = Gpu.RESOLUTION_WIDTH * ratio, .h = Gpu.RESOLUTION_HEIGHT * ratio };
        const tilesRect = c.SDL_Rect{ .x = Gpu.RESOLUTION_WIDTH * ratio + 10, .y = 0, .w = Gpu.TILEDEBUG_WIDTH * ratio, .h = Gpu.TILEDEBUG_HEIGHT * ratio };
        _ = c.SDL_RenderCopy(renderer, gameTexture, null, &gameRect);
        _ = c.SDL_RenderCopy(renderer, tilesTexture, null, &tilesRect);
        c.SDL_RenderPresent(renderer);

        const target_frame_time_ms = 16;
        const delta_time_ms = (try std.time.Instant.now()).since(prev_time) / std.time.ns_per_ms;
        if (delta_time_ms < target_frame_time_ms) {
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

const Emulator = struct {
    //gpa: std.heap.DebugAllocator,
    allocator: std.mem.Allocator,
    cpu: *Cpu,
    gpu: *Gpu,
    boot_rom: []u8,
    cartridge_rom: []u8,

    pub fn Init() !Emulator {
        //  Get an allocator
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        //defer arena.deinit();
        //const allocator = arena.allocator();

        const boot_location = "F:\\Projects\\higan\\higan\\System\\Game Boy\\boot.dmg-1.rom";
        const rom_location = "C:\\Users\\Leo\\Emulation\\Gameboy\\Pokemon Red (UE) [S][!].gb";
        const buffer_size = 2 * 1024 * 1024;

        const boot_rom = try load_rom(boot_location, 256, std.heap.page_allocator);
        const cartridge_rom = try load_rom(rom_location, buffer_size, std.heap.page_allocator);

        //var device_rom = [];

        var ram: [8 << 10 << 10]u8 = undefined;
        @memset(&ram, 0);

        var bus = Bus.init(ram[0..ram.len], cartridge_rom[0..cartridge_rom.len]);
        var gpu = Gpu.init(&bus, ram[0..ram.len]);
        var cpu = Cpu.init(boot_rom, &bus);
        bus.connectGpu(&gpu);

        return Emulator{
            //.gpa = gpa,
            .allocator = allocator,
            .cpu = &cpu,
            .gpu = &gpu,
            .boot_rom = boot_rom,
            .cartridge_rom = cartridge_rom,
        };
    }

    pub fn close(self: Emulator) void {
        self.allocator.free(self.cartridge_rom);
        self.allocator.free(self.boot_rom);

        //const deinit_status = self.gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        //if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }

    pub fn run_until_frameready(self: Emulator) !void {
        const zone = tracy.beginZone(@src(), .{ .name = "run_until_frameready" });
        defer zone.end();
        var gpuResult = GpuStepResult.Normal;
        while (gpuResult != GpuStepResult.FrameReady) {
            const clocks = self.cpu.step();
            gpuResult = self.gpu.step(clocks);
        }
    }

    pub fn getFrameBuffer(self: Emulator) FrameBufferInfo {
        return FrameBufferInfo{ .framebuffer = &self.gpu.framebuffer, .width = Gpu.RESOLUTION_WIDTH, .height = Gpu.RESOLUTION_HEIGHT };
    }

    pub fn snapshotTiles(self: Emulator) FrameBufferInfo {
        return FrameBufferInfo{ .framebuffer = self.gpu.snapshotTiles(), .width = 16 * 8, .height = 24 * 8 };
    }
};

const FrameBufferInfo = struct {
    framebuffer: []u8,
    width: u32,
    height: u32,
};

const Bus = struct {
    ram: []u8,
    cartridgerom: []const u8,
    gpu: *Gpu = undefined,

    pub fn init(ram: []u8, cartridge_rom: []const u8) Bus {
        return Bus{
            .ram = ram,
            .cartridgerom = cartridge_rom,
        };
    }

    fn connectGpu(self: *Bus, gpu: *Gpu) void {
        self.gpu = gpu;
    }

    pub fn read(self: Bus, address: u16) u8 {
        return switch (address) {
            0...0x3FFF => {
                return self.cartridgerom[address];
            },
            0xFF42 => {
                return self.gpu.scroll_y;
            },
            0xFF43 => {
                return self.gpu.scroll_x;
            },
            0xFF44 => {
                return self.gpu.ly;
                //return 0;
            },

            0xFF80...0xFFFF => { // HRAM
                return self.ram[address];
            },
            else => {
                std.debug.panic("unhandled read address 0x{x}", .{address});
            },
        };
    }

    pub fn write(self: Bus, address: u16, value: u8) void {
        switch (address) {
            0...0x7FFF => {
                @panic("Cannot write to ROM");
            },
            0x8000...0x9FFF => { //vram
                //TODO: do we need to split ram from vram?
                self.ram[address] = value;
            },
            0xC000...0xCFFF => {
                self.ram[address] = value;
            },

            0xFF40 => {
                self.gpu.lcd_control = @bitCast(value);
            },
            0xFF42 => {
                self.gpu.scroll_y = value;
            },
            0xFF43 => {
                self.gpu.scroll_x = value;
            },
            0xFF47 => {
                self.gpu.background_palette = @bitCast(value);
            },
            0xFF48 => {
                self.gpu.object_palette[0] = @bitCast(value);
            },
            0xFF49 => {
                self.gpu.object_palette[1] = @bitCast(value);
            },
            0xFF4A => {
                self.gpu.window_y = value;
            },
            0xFF4B => {
                self.gpu.window_x = value;
            },

            0xFF80...0xFFFF => { // HRAM
                self.ram[address] = value;
            },
            else => {
                std.debug.panic("unhandled write address 0x{x}", .{address});
            },
        }
    }
};

const CpuFlags = struct {
    z: bool,

    fn debug_str(self: CpuFlags) [1:0]u8 {
        var buf: [1:0]u8 = undefined;
        buf[0] = if (self.z) 'Z' else 'z';
        return buf;
    }
};

const Registers = packed union {
    f: packed struct {
        AF: u16,
        BC: u16,
        DE: u16,
        HL: u16,
    },
    s: packed struct {
        f: packed struct {
            _unused: u4,
            c: u1,
            h: u1,
            n: u1,
            z: u1,
        },
        a: u8,

        c: u8,
        b: u8,

        e: u8,
        d: u8,

        l: u8,
        h: u8,
    },

    pub fn init() Registers {
        return Registers{ .f = .{
            .AF = 0x0000,
            .BC = 0x0000,
            .DE = 0x0000,
            .HL = 0x0000,
        } };
    }

    pub fn debug_flag_str(self: Registers) [4:0]u8 {
        var buf: [4:0]u8 = undefined;
        buf[0] = if (self.s.f.z == 1) 'Z' else 'z';
        buf[1] = if (self.s.f.n == 1) 'N' else 'n';
        buf[2] = if (self.s.f.h == 1) 'H' else 'h';
        buf[3] = if (self.s.f.c == 1) 'C' else 'c';
        return buf;
    }
};

const ArgInfo = enum { None, U8, U16 };

const OpCodeInfo = struct {
    name: []const u8,
    code: u8,
    args: [2]ArgInfo,
    f: opFunc,
    pub fn init(code: u8, name: []const u8, args: [2]ArgInfo, f: opFunc) OpCodeInfo {
        return OpCodeInfo{
            .name = name,
            .code = code,
            .args = args,
            .f = f,
        };
    }
};

fn NotImplemented(_: *Cpu) !mcycles {
    return error.NotImplemented;
}

fn nop(_: *Cpu) !mcycles {
    return 1;
}

fn inc_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b += 1;
    cpu.r.s.f.z = if (cpu.r.s.b == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((cpu.r.s.b & 0xFF) == 0) 1 else 0;
    return 1;
}

fn dec_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b -= 1;
    cpu.r.s.f.z = if (cpu.r.s.b == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.b & 0b1000_0000) == 1) 1 else 0;
    return 1;
}

fn load_d8_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = Cpu.fetch(cpu);
    return 2;
}

fn inc_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c += 1;
    cpu.r.s.f.z = if (cpu.r.s.c == 1) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((cpu.r.s.c & 0x0F) == 0) 1 else 0;
    return 1;
}

fn dec_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c -= 1;
    cpu.r.s.f.z = if (cpu.r.s.c == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.c & 0b1000_0000) == 1) 1 else 0;
    return 1;
}

fn load_d8_to_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c = Cpu.fetch(cpu);
    return 2;
}

fn load_d16_to_de(cpu: *Cpu) !mcycles {
    cpu.r.f.DE = Cpu.fetch16(cpu);
    return 3;
}

fn inc_de(cpu: *Cpu) !mcycles {
    cpu.r.f.DE += 1;
    return 2;
}

fn dec_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d -= 1;
    return 1;
}

fn rotate(cpu: *Cpu, data: *u8) void {
    const carry: u1 = if (data.* & 0b1000_0000 != 0) 1 else 0;
    const shifted = (data.* << 1);
    const around = @as(u8, cpu.r.s.f.c);
    data.* = shifted | around;

    cpu.r.s.f.z = if (data.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = carry;
}

fn rotate_left_a(cpu: *Cpu) !mcycles {
    rotate(cpu, &cpu.r.s.a);
    cpu.r.s.f.z = 0;
    return 1;
}

fn load_a_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.a;
    return 1;
}

fn load_a_to_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c = cpu.r.s.a;
    return 1;
}

fn load_D_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.d;
    return 1;
}

fn load_a_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.r.s.a;
    return 1;
}

fn load_a_to_h(cpu: *Cpu) !mcycles {
    cpu.r.s.h = cpu.r.s.a;
    return 1;
}

fn store_a_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    return 2;
}

fn load_e_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.e;
    return 1;
}

fn load_h_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.h;
    return 1;
}

fn subtract_l_from_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a -= cpu.r.s.l;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) < (cpu.r.s.l & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (cpu.r.s.a < cpu.r.s.l) 1 else 0;
    return 1;
}

fn subtract_b_from_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a -= cpu.r.s.b;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) < (cpu.r.s.b & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (cpu.r.s.a < cpu.r.s.b) 1 else 0;
    return 1;
}

fn load_d16_to_sp(cpu: *Cpu) !mcycles {
    cpu.sp = cpu.fetch16();
    return 3;
}

fn store_a_to_indirectHL_dec(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    cpu.r.f.HL -= 1;
    return 2;
}

fn load_indirectHL_dec_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.load(cpu.r.f.HL);
    cpu.r.f.HL -= 1;
    return 2;
}

fn dec_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a -= 1;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) == 0x0F) 1 else 0;
    return 1;
}

fn load_d8_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = Cpu.fetch(cpu);
    return 2;
}

fn load_indirect16_to_a(cpu: *Cpu) !mcycles {
    const addr = Cpu.fetch16(cpu);
    cpu.r.s.a = cpu.load(addr);
    return 4;
}

fn load_a_to_indirect16(cpu: *Cpu) !mcycles {
    const addr = Cpu.fetch16(cpu);
    cpu.store(addr, cpu.r.s.a);
    return 4;
}

fn load_indirect8_to_a(cpu: *Cpu) !mcycles {
    const addr: u16 = 0xFF00 + @as(u16, Cpu.fetch(cpu));
    cpu.r.s.a = cpu.load(addr);
    return 3;
}

fn load_a_to_indirect8(cpu: *Cpu) !mcycles {
    const addr: u16 = 0xFF00 + @as(u16, Cpu.fetch(cpu));

    cpu.store(addr, cpu.r.s.a);
    return 3;
}

fn pop_to_HL(cpu: *Cpu) !mcycles {
    cpu.r.f.HL = cpu.pop16();
    return 3;
}

fn store_a_to_indirect_c(cpu: *Cpu) !mcycles {
    cpu.store(0xFF00 + @as(u16, cpu.r.s.c), cpu.r.s.a);
    return 2;
}

fn add_u8_as_signed_to_u16(dest: u8, pc: u16) u16 {
    const signed_dest: i16 = @intCast(@as(i8, @bitCast(dest)));
    const pc_signed: i16 = @intCast(pc);
    const new_pc_singed: i16 = pc_signed + signed_dest;
    return @intCast(new_pc_singed);
}

fn pop_bc(cpu: *Cpu) !mcycles {
    cpu.r.f.BC = cpu.pop16();
    return 3;
}

fn jmp(cpu: *Cpu) !mcycles {
    const dest = Cpu.fetch16(cpu);
    cpu.pc = dest;
    return 4;
}

fn push_bc(cpu: *Cpu) !mcycles {
    cpu.push16(cpu.r.f.BC);
    return 4;
}

fn return_from_call(cpu: *Cpu) !mcycles {
    cpu.pc = cpu.pop16();
    return 4;
}

fn jmp_s8(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
    return 3;
}

fn load_indirectDE_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.load(cpu.r.f.DE);
    return 2;
}
fn dec_e(cpu: *Cpu) !mcycles {
    cpu.r.s.e -= 1;
    cpu.r.s.f.z = if (cpu.r.s.e == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.e & 0x0F) == 0x0F) 1 else 0;
    return 1;
}

fn load_d8_to_e(cpu: *Cpu) !mcycles {
    cpu.r.s.e = cpu.fetch();
    return 2;
}

fn jmp_nz_s8(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    var timing: mcycles = 2;
    if (cpu.r.s.f.z == 0) {
        cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
        timing += 1;
    }
    return timing;
}

fn load_d16_to_HL(cpu: *Cpu) !mcycles {
    cpu.r.f.HL = Cpu.fetch16(cpu);
    return 3;
}

fn store_a_to_IndirectHL_inc(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    cpu.r.f.HL += 1;
    return 2;
}

fn inc_HL(cpu: *Cpu) !mcycles {
    cpu.r.f.HL += 1;
    return 2;
}

fn inc_H(cpu: *Cpu) !mcycles {
    cpu.r.s.h += 1;
    cpu.r.s.f.z = if (cpu.r.s.h == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((cpu.r.s.h & 0x0F) == 0) 1 else 0;
    return 1;
}

fn jmp_if_zero(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    var timing: mcycles = 2;
    if (cpu.r.s.f.z == 1) {
        cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
        timing += 1;
    }
    return timing;
}

fn load_d8_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.fetch();
    return 2;
}

fn call16(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch16();
    cpu.push16(cpu.pc);
    cpu.pc = dest;
    return 6;
}

fn compare_immediate8_ra(cpu: *Cpu) !mcycles {
    const immediate = Cpu.fetch(cpu);
    cpu.r.s.f.z = if (cpu.r.s.a == immediate) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) < (immediate & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (cpu.r.s.a < immediate) 1 else 0;
    return 2;
}

fn xor_a_with_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a ^= cpu.r.s.a;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    return 1;
}

fn disable_interrupts(cpu: *Cpu) !mcycles {
    cpu.interrupt.enabled = false;
    return 1;
}

fn rotate_left_c(cpu: *Cpu) !mcycles {
    rotate(cpu, &cpu.r.s.c);
    return 2;
}

fn shift_left_B(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.b << 1;
    cpu.r.s.f.z = if (cpu.r.s.b == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = if ((cpu.r.s.b >> 7) == 1) 1 else 0;
    return 2;
}

fn copy_compl_bit7_to_z(cpu: *Cpu) !mcycles {
    cpu.r.s.f.z = if ((cpu.r.s.h >> 7) != 1) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
    return 2;
}

fn reset_a_bit0(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= 0xFE;
    return 2;
}

const Interrupts = packed struct {
    vblank: bool,
    lcd_stat: bool,
    timer: bool,
    serial: bool,
    joypad: bool,
    _: u3,
};

const mcycles = usize;
const opFunc = *const fn (*Cpu) anyerror!mcycles;

fn process_opcodetable(table: []const OpCodeInfo) struct { [256]OpCodeInfo, [256]opFunc } {
    const NoArgs = [_]ArgInfo{ .None, .None };
    const err: OpCodeInfo = OpCodeInfo.init(0x00, "EXT ERR", NoArgs, &NotImplemented);
    var opcodetable: [256]OpCodeInfo = undefined;
    var jmptable: [256]opFunc = undefined;
    for (0..255) |i| {
        opcodetable[i] = err;
        jmptable[i] = err.f;
    }

    for (table) |value| {
        opcodetable[value.code] = value;
        jmptable[value.code] = value.f;
    }

    return .{ opcodetable, jmptable };
}

const Cpu = struct {
    boot_rom: []const u8,
    bus: *Bus,
    r: Registers,
    sp: u16,
    pc: u16,
    interrupt: struct { enabled: bool, interrupt_flag: Interrupts, interrupt_enabled: Interrupts },
    disable_boot_rom: u8,
    timer: struct { modulo: u8, control: packed struct {
        clock_select: u2,
        timer_stop: bool,
        _: u5,
    } },
    sound_flags: packed struct {
        sound_1_enabled: u1,
        sound_2_enabled: u1,
        sound_3_enabled: u1,
        sound_4_enabled: u1,
        _: u3,
        enabled: u1,
    },
    serial_data_transfer: struct {
        data: u8,
        control: packed struct {
            shift_clock: bool,
            clock_speed: bool,
            _: u5,
            transfer_start_flag: bool,
        },
    },

    opcodetable: [256]OpCodeInfo,
    jmptable: [256]opFunc,
    extended_opcodetable: [256]OpCodeInfo,
    extended_jmptable: [256]opFunc,

    pub fn init(boot_rom: []const u8, bus: *Bus) Cpu {
        const NoArgs = [_]ArgInfo{ .None, .None };
        const Single8Arg = [_]ArgInfo{ .U8, .None };
        const Single16Arg = [_]ArgInfo{ .U16, .None };

        const opcodesInfo = [_]OpCodeInfo{
            OpCodeInfo.init(0x00, "NOP", NoArgs, &nop),
            OpCodeInfo.init(0x04, "INC B", NoArgs, &inc_b),
            OpCodeInfo.init(0x05, "DEC B", NoArgs, &dec_b),
            OpCodeInfo.init(0x06, "LD B, d8", Single8Arg, &load_d8_to_b),
            OpCodeInfo.init(0x0c, "INC C", NoArgs, &inc_c),
            OpCodeInfo.init(0x0d, "DEC C", NoArgs, &dec_c),
            OpCodeInfo.init(0x0e, "LD C, d8", NoArgs, &load_d8_to_c),
            OpCodeInfo.init(0x11, "LD DE, d16", Single16Arg, &load_d16_to_de),
            OpCodeInfo.init(0x13, "INC DE", NoArgs, &inc_de),
            OpCodeInfo.init(0x15, "DEC D", NoArgs, &dec_d),
            OpCodeInfo.init(0x17, "RLA", NoArgs, &rotate_left_a),
            OpCodeInfo.init(0x18, "JR s8", Single8Arg, &jmp_s8),
            OpCodeInfo.init(0x1A, "LD A,(DE)", NoArgs, &load_indirectDE_to_a),
            OpCodeInfo.init(0x1D, "DEC E", NoArgs, &dec_e),
            OpCodeInfo.init(0x1E, "LD E, d8", Single8Arg, &load_d8_to_e),
            OpCodeInfo.init(0x20, "JR NZ, s8", Single8Arg, &jmp_nz_s8),
            OpCodeInfo.init(0x21, "LD HL, d16", Single16Arg, &load_d16_to_HL),
            OpCodeInfo.init(0x22, "LD (HL+), A", NoArgs, &store_a_to_IndirectHL_inc),
            OpCodeInfo.init(0x23, "INC HL", NoArgs, &inc_HL),
            OpCodeInfo.init(0x24, "INC H", NoArgs, &inc_H),
            OpCodeInfo.init(0x28, "JR Z", Single8Arg, &jmp_if_zero),
            OpCodeInfo.init(0x2e, "LD L, d8", Single8Arg, &load_d8_to_l),
            OpCodeInfo.init(0x31, "LD SP, d16", Single16Arg, &load_d16_to_sp),
            OpCodeInfo.init(0x32, "LD (HL-), A", NoArgs, &store_a_to_indirectHL_dec),
            OpCodeInfo.init(0x3a, "LD A, (HL-)", Single8Arg, &load_indirectHL_dec_to_a),
            OpCodeInfo.init(0x3d, "DEC A", NoArgs, &dec_a),
            OpCodeInfo.init(0x3e, "LD A, d8", Single8Arg, &load_d8_to_a),
            OpCodeInfo.init(0x47, "LD B, A", NoArgs, &load_a_to_b),
            OpCodeInfo.init(0x4f, "LD C, A", NoArgs, &load_a_to_c),
            OpCodeInfo.init(0x50, "LD D, B", NoArgs, &load_D_to_b),
            OpCodeInfo.init(0x57, "LD D, A", NoArgs, &load_a_to_d),
            OpCodeInfo.init(0x67, "LD H, A", NoArgs, &load_a_to_h),
            OpCodeInfo.init(0x77, "LD (HL), A", NoArgs, &store_a_to_indirectHL),
            OpCodeInfo.init(0x7b, "LD A, E", NoArgs, &load_e_to_a),
            OpCodeInfo.init(0x7c, "LD A, H", NoArgs, &load_h_to_a),
            OpCodeInfo.init(0x90, "SUB B", NoArgs, &subtract_b_from_a),
            OpCodeInfo.init(0x95, "SUB L", NoArgs, &subtract_l_from_a),
            //OpCodeInfo.init(0x96, "SUB (HL)", NoArgs, &subtract_),
            OpCodeInfo.init(0xAF, "XOR A", NoArgs, &xor_a_with_a),
            OpCodeInfo.init(0xC1, "POP BC", NoArgs, &pop_bc),
            OpCodeInfo.init(0xC3, "JMP", Single16Arg, &jmp),
            OpCodeInfo.init(0xC5, "PUSH BC", NoArgs, &push_bc),
            OpCodeInfo.init(0xC9, "RET", NoArgs, &return_from_call),
            //OpCodeInfo.init(0xCB, "Xtended", Single16Arg, &cb_extended),
            OpCodeInfo.init(0xCD, "CALL a16", Single16Arg, &call16),
            OpCodeInfo.init(0xE0, "LD (a8), A", Single8Arg, &load_a_to_indirect8),
            OpCodeInfo.init(0xE1, "POP HL", NoArgs, &pop_to_HL),
            OpCodeInfo.init(0xE2, "LD (C), A", NoArgs, &store_a_to_indirect_c),
            OpCodeInfo.init(0xEA, "LD (a16), A", Single16Arg, &load_a_to_indirect16),
            OpCodeInfo.init(0xF0, "LD A, (a8)", Single8Arg, &load_indirect8_to_a),
            OpCodeInfo.init(0xF3, "DI", NoArgs, &disable_interrupts),
            OpCodeInfo.init(0xFE, "CP A,", Single8Arg, &compare_immediate8_ra),
            OpCodeInfo.init(0xFA, "LD A (a16)", Single16Arg, &load_indirect16_to_a),
        };

        const extended_opcodesInfo = [_]OpCodeInfo{
            OpCodeInfo.init(0x11, "RL C", NoArgs, &rotate_left_c),
            OpCodeInfo.init(0x20, "SLA B", NoArgs, &shift_left_B),
            OpCodeInfo.init(0x7c, "BIT 7, H", NoArgs, &copy_compl_bit7_to_z),
            OpCodeInfo.init(0x87, "RES 0, A", NoArgs, &reset_a_bit0),
        };

        const opcodetable, const jmptable = process_opcodetable(&opcodesInfo);
        const extended_opcodetable, const extended_jmptable = process_opcodetable(&extended_opcodesInfo);

        return Cpu{
            .boot_rom = boot_rom,
            .disable_boot_rom = 0,
            .bus = bus,
            .r = Registers.init(),
            .sp = 0xFFFE,
            .pc = 0x0,
            .opcodetable = opcodetable,
            .jmptable = jmptable,
            .extended_opcodetable = extended_opcodetable,
            .extended_jmptable = extended_jmptable,
            .interrupt = .{
                .enabled = true,
                .interrupt_enabled = .{
                    .vblank = false,
                    .lcd_stat = false,
                    .timer = false,
                    .serial = false,
                    .joypad = false,
                    ._ = undefined,
                },
                .interrupt_flag = .{
                    .vblank = false,
                    .lcd_stat = false,
                    .timer = false,
                    .serial = false,
                    .joypad = false,
                    ._ = undefined,
                },
            },
            .timer = .{ .modulo = 0, .control = .{ .clock_select = 0, .timer_stop = false, ._ = undefined } },
            .sound_flags = .{
                .sound_1_enabled = 0,
                .sound_2_enabled = 0,
                .sound_3_enabled = 0,
                .sound_4_enabled = 0,
                ._ = 0,
                .enabled = 0,
            },
            .serial_data_transfer = .{
                .data = 0,
                .control = .{
                    .shift_clock = false,
                    .clock_speed = false,
                    ._ = undefined,
                    .transfer_start_flag = false,
                },
            },
        };
    }

    fn load(self: *Cpu, address: u16) u8 {
        if (self.disable_boot_rom == 0 and address < 0x0100) {
            return self.boot_rom[address];
        }
        return self.bus.read(address);
    }

    fn load16(self: *Cpu, address: u16) u16 {
        var result: u16 = 0;
        result += self.load(address);
        result += @as(u16, self.load(address + 1)) << 8;
        return result;
    }

    fn store(self: *Cpu, address: u16, value: u8) void {
        switch (address) {
            0xFF01 => {
                self.serial_data_transfer.data = value;
            },
            0xFF02 => {
                //Serial Data Transfer? ignore for now
                self.serial_data_transfer.control = @bitCast(value);
            },
            0xFF06 => {
                self.timer.modulo = value;
            },
            0xFF07 => {
                self.timer.control = @bitCast(value);
            },
            0xFF11...0xFF25 => {
                //No-Impl Sound related I/O ops
            },
            0xFF26 => {
                self.sound_flags.enabled = if (value & 0b1000_0000 == 0b1000_0000) 1 else 0;
            },
            0xFF50 => {
                self.disable_boot_rom = value;
            },
            0xFF0F => {
                self.interrupt.interrupt_flag = @bitCast(value);
                self.execute_interrupts_if_enabled();
            },
            0xFFFF => {
                self.interrupt.interrupt_enabled = @bitCast(value);
                self.execute_interrupts_if_enabled();
            },
            else => {
                self.bus.write(address, value);
            },
        }
    }

    fn fetch(self: *Cpu) u8 {
        const result = self.load(self.pc);
        self.pc += 1;
        return result;
    }

    fn fetch16(self: *Cpu) u16 {
        const result: u16 = self.load16(self.pc);
        self.pc += 2;
        return result;
    }

    fn push16(self: *Cpu, value: u16) void {
        self.sp -= 1;
        self.store(self.sp, @intCast(value >> 8));
        self.sp -= 1;
        self.store(self.sp, @intCast(value & 0xFF));
    }

    fn pop16(self: *Cpu) u16 {
        const low = self.load(self.sp);
        self.sp += 1;
        const high = self.load(self.sp);
        self.sp += 1;
        return @as(u16, high) << 8 | low;
    }

    fn decode_and_execute(self: *Cpu, instruction: u8) mcycles {
        if (instruction == 0xCB) {
            const extended_instruction = self.fetch();
            return self.extended_jmptable[extended_instruction](self) catch {
                std.debug.panic("Error decoding and executing ext opcode 0xCB, 0x{x:02}\n", .{extended_instruction});
            };
        }
        return self.jmptable[instruction](self) catch {
            std.debug.panic("Error decoding and executing opcode 0x{x:02}\n", .{instruction});
        };
    }

    pub fn step(self: *Cpu) mcycles {
        const zone = tracy.beginZone(@src(), .{ .name = "cpu step" });
        defer zone.end();
        //self.print_trace();
        const instruction = self.fetch();
        return self.decode_and_execute(instruction);
    }

    fn execute_interrupt(comptime T: type) type {
        return struct {
            fn do(cpu: *Cpu, flag: T, address: u16) void {
                if (flag.*) {
                    std.debug.print("Interrupt 0x{x}", .{address});
                    flag.* = false;
                    cpu.interrupt.enabled = false;
                    cpu.push16(cpu.pc);
                    cpu.pc = address;
                }
            }
        };
    }

    fn execute_interrupts_if_enabled(self: *Cpu) void {
        if (!self.interrupt.enabled) {
            return;
        }
        execute_interrupt(*align(1:0:1) bool).do(self, &self.interrupt.interrupt_flag.vblank, 0x0040);
        execute_interrupt(*align(1:1:1) bool).do(self, &self.interrupt.interrupt_flag.lcd_stat, 0x0048);
        execute_interrupt(*align(1:2:1) bool).do(self, &self.interrupt.interrupt_flag.timer, 0x0050);
        execute_interrupt(*align(1:3:1) bool).do(self, &self.interrupt.interrupt_flag.serial, 0x0058);
        execute_interrupt(*align(1:4:1) bool).do(self, &self.interrupt.interrupt_flag.joypad, 0x0060);
    }

    pub fn print_trace(self: *Cpu) void {
        const zone = tracy.beginZone(@src(), .{ .name = "cpu print_trace" });
        defer zone.end();
        var tmp_ip = self.pc;
        var opcode = self.load(tmp_ip);
        tmp_ip += 1;
        const is_extopcode = opcode == 0xCB;
        if (is_extopcode) {
            opcode = self.load(tmp_ip);
            tmp_ip += 1;
        }
        const opInfo = if (is_extopcode)
            self.extended_opcodetable[opcode]
        else
            self.opcodetable[opcode];
        const args = opInfo.args;
        var args_str: [10:0]u8 = undefined;
        @memset(args_str[0..10], ' ');

        for (args) |value| {
            switch (value) {
                .U8 => {
                    _ = std.fmt.bufPrint(&args_str, " 0x{x:02}", .{self.load(tmp_ip)}) catch unreachable;
                    tmp_ip += 1;
                },
                .U16 => {
                    _ = std.fmt.bufPrint(&args_str, " 0x{x:04}", .{self.load16(tmp_ip)}) catch unreachable;
                    tmp_ip += 2;
                },
                .None => {},
            }
        }

        std.debug.print("[CPU] 0x{x:04} 0x{x:02} {s: <12}{s} AF:0x{x:04} BC:0x{x:04} DE:0x{x:04} HL:0x{x:04} SP:0x{x:04} {s}\n", .{ self.pc, opInfo.code, opInfo.name, args_str, self.r.f.AF, self.r.f.BC, self.r.f.DE, self.r.f.HL, self.sp, self.r.debug_flag_str() });
    }
};

const SpriteAttribute = struct {
    y: u8,
    x: u8,
    tile_index: u8,
    flags: packed struct {
        cpalette: u2, //(CGB only)
        tile_vram: u1, //VRAM Bank (CGB only)
        pallete: u1,
        xflip: u1,
        yflip: u1,
        priority: u1,
    },
};

const SpriteData = struct {
    pattern: [16]u8,
    fn get_pixel_color_index(self: SpriteData, x: u8, y: u8) u2 {
        const row_high = self.pattern[y * 2];
        const row_low = self.pattern[y * 2 + 1];

        const pixel_low = std.math.shr(u8, row_low, (7 - x)) & 0b1;
        const pixel_high = std.math.shr(u8, row_high, (7 - x)) & 0b1;
        return @intCast((pixel_high << 1) | pixel_low);
    }
};

const GpuStepResult = enum {
    Normal,
    FrameReady,
};

const Gpu = struct {
    mode: u2,
    mode_clocks: usize,
    //scanline: u8,
    ram: []u8,
    bus: *Bus,

    ly: u8,
    scroll_x: u8,
    scroll_y: u8,
    window_x: u8,
    window_y: u8,
    lcd_control: packed struct {
        bg_display: bool,
        obj_display_enable: bool,
        obj_size: bool,
        bg_tilemap_display_select: bool,
        bg_and_window_tile_select: bool,
        window_display_enable: bool,
        window_tilemap_display_select: bool,
        lcd_display_enable: bool,
    },
    background_palette: packed struct {
        color0: u2,
        color1: u2,
        color2: u2,
        color3: u2,
    },
    object_palette: [2]packed struct {
        _: u2,
        color1: u2,
        color2: u2,
        color3: u2,
    },

    visibleSprites: [10]SpriteAttribute,
    visibleSpritesCount: usize,

    framebuffer: [RESOLUTION_WIDTH * RESOLUTION_HEIGHT]u8,
    dbgTileFramebuffer: [16 * 8 * 24 * 8]u8,

    pub fn init(bus: *Bus, ram: []u8) Gpu {
        return Gpu{
            .ram = ram,
            .bus = bus,
            .mode = 2,
            .mode_clocks = 0,
            .ly = 0,
            .visibleSprites = [_]SpriteAttribute{undefined} ** 10,
            .visibleSpritesCount = 0,
            .framebuffer = [_]u8{0} ** (RESOLUTION_WIDTH * RESOLUTION_HEIGHT),
            .dbgTileFramebuffer = [_]u8{0} ** (TILEDEBUG_WIDTH * TILEDEBUG_HEIGHT),
            .scroll_x = 0,
            .scroll_y = 0,
            .window_x = 0,
            .window_y = 0,
            .lcd_control = @bitCast(@as(u8, 0x91)),
            .background_palette = .{ .color0 = 0, .color1 = 0, .color2 = 0, .color3 = 0 },
            .object_palette = .{ .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 }, .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 } },
        };
    }

    const OAM_CLOCKS = 20;
    const RASTER_CLOKS = 43;
    const HBLANK_CLOKS = 51;
    const VBLANK_CLOKS = 114 * 10;
    const RESOLUTION_WIDTH = 160;
    const RESOLUTION_HEIGHT = 144;
    const TILEDEBUG_WIDTH = 16 * 8;
    const TILEDEBUG_HEIGHT = 24 * 8;

    pub fn step(self: *Gpu, cpuClocks: mcycles) GpuStepResult {
        const zone = tracy.beginZone(@src(), .{ .name = "gpu step" });
        defer zone.end();
        self.mode_clocks += cpuClocks;
        switch (self.mode) {
            0 => { //H-Blank
                if (self.mode_clocks >= HBLANK_CLOKS) {
                    self.mode_clocks %= HBLANK_CLOKS;
                    if (self.ly < 144) {
                        self.ly += 1;
                        self.mode = 2;
                    } else {
                        self.mode = 1;
                        self.ly = 0;
                        return GpuStepResult.FrameReady;
                    }
                }
            },
            1 => { //V-Blank
                if (self.mode_clocks >= VBLANK_CLOKS) {
                    self.mode_clocks %= VBLANK_CLOKS;
                    self.mode = 2;
                }
            },
            2 => { //OAM
                if (self.mode_clocks >= OAM_CLOCKS) {
                    self.mode_clocks %= OAM_CLOCKS;
                    self.mode = 3;
                    self.findVisibleSprites();
                }
            },
            3 => { //raster
                if (self.mode_clocks >= RASTER_CLOKS) {
                    self.mode_clocks %= RASTER_CLOKS;
                    self.mode = 0;
                    self.drawscanline();
                }
            },
        }
        return GpuStepResult.Normal;
    }

    fn findVisibleSprites(self: *Gpu) void {
        const sprite_attrbiute_table_begin = 0xFE00;
        const sprite_attrbiute_table_end = 0xFE9F;
        const sprite_attrbiute_table = self.ram[sprite_attrbiute_table_begin..sprite_attrbiute_table_end];
        const sprite_aatribute = sliceCast(SpriteAttribute, sprite_attrbiute_table, 0, 40);

        //TODO: support 16 height as well
        const sprite_height = 8;

        self.visibleSpritesCount = 0;
        for (sprite_aatribute) |value| {
            if (value.y > self.ly) continue;
            if (value.y + sprite_height <= self.ly) continue;

            self.visibleSprites[self.visibleSpritesCount] = value;
            self.visibleSpritesCount += 1;
            if (self.visibleSpritesCount == self.visibleSprites.len) break;
        }
    }

    inline fn getBackgroundColor(self: *Gpu, color_index: u2) u8 {
        switch (color_index) {
            0 => return self.background_palette.color0,
            1 => return self.background_palette.color1,
            2 => return self.background_palette.color2,
            3 => return self.background_palette.color3,
        }
    }

    fn drawscanline(self: *Gpu) void {
        const tile_width = 8;
        const tile_height = 8;
        const shades = [_]u8{ 0, 63, 128, 255 }; //this might need to be inverted

        const tile_data_vram = self.ram[0x8000..0x8FFF];
        const tile_data = sliceCast(SpriteData, tile_data_vram, 0, 0xFFF);

        std.debug.assert(self.lcd_control.bg_and_window_tile_select == true);

        //Draw BG
        const bg_map_1 = if (self.lcd_control.bg_tilemap_display_select == false) self.ram[0x9800..0x9BFF] else self.ram[0x9C00..0x9FFF];
        for (bg_map_1, 0..) |tile_index, i| {
            const tile_x = i % 32;
            const tile_y = i / 32;
            const tile = tile_data[tile_index];

            const scrolled_y = (self.ly + self.scroll_y) % 255;
            //const scrolled_y = self.ly;

            if (tile_y * tile_height > scrolled_y or tile_y * tile_height + tile_height <= scrolled_y) continue; //TODO: optimize so we dont have to check and continue here
            if (tile_x * tile_width > RESOLUTION_WIDTH) continue;

            const y: u8 = scrolled_y % tile_height;

            for (0..tile_width) |x| {
                const framebuffer_x = tile_x * 8 + x;
                if (framebuffer_x >= RESOLUTION_WIDTH) break;
                const color_index = tile.get_pixel_color_index(@intCast(x), y);
                //const palette_table = if (sprite.flags.pallete == 0) self.ram[0xFF48] else self.ram[0xFF49];
                //const shade: u2 = @intCast((palette_table >> (color_index * 2)) & 0b11);
                //if (shade == 0) continue; //transparency
                const framebuffer_index: usize = (@as(usize, self.ly) * RESOLUTION_WIDTH) + framebuffer_x;
                if (framebuffer_index >= self.framebuffer.len)
                    break;
                self.framebuffer[framebuffer_index] = shades[self.getBackgroundColor(color_index)];
            }
        }

        //Draw Window

        //draw sprites
        const sprite_width = 8;
        for (0..RESOLUTION_WIDTH) |index| {
            const i: u8 = @intCast(index);
            for (0..self.visibleSpritesCount) |si| {
                const sprite = self.visibleSprites[si];
                //TODO: handle priority and x-ordering
                if (sprite.x > i or sprite.x + sprite_width <= i) continue;
                const sprite_x: u8 = i - sprite.x;
                const sprite_y: u8 = self.ly - sprite.y;
                const sprite_pattern = tile_data[sprite.tile_index];
                const color_index = sprite_pattern.get_pixel_color_index(sprite_x, sprite_y);
                const palette_table = if (sprite.flags.pallete == 0) self.ram[0xFF48] else self.ram[0xFF49];
                const shade: u2 = @intCast((palette_table >> (color_index * 2)) & 0b11);
                if (shade == 0) continue; //transparency
                const framebuffer_index: usize = (@as(usize, self.ly) * RESOLUTION_WIDTH) + index;
                self.framebuffer[framebuffer_index] = shades[shade];
            }
        }
    }
    fn frameready(_: *Gpu) void {}

    fn snapshotTiles(self: *Gpu) []u8 {
        const sprite_width = 8;
        const sprite_height = 8;
        const tiles_colum = 16;
        const fb_width = tiles_colum * 8;

        const sprite_table = self.ram[0x8000..0x97FF];
        const sprite_data = sliceCast(SpriteData, sprite_table, 0, 0xFF);
        const shades = [_]u8{ 0, 63, 128, 255 };
        for (sprite_data, 0..) |sprite, si| {
            const fbGrid_x = si % tiles_colum;
            const fbGrid_y = si / tiles_colum;
            for (0..sprite_width) |x| {
                for (0..sprite_height) |y| {
                    const color_index: u2 = sprite.get_pixel_color_index(@intCast(x), @intCast(y));
                    const framebuffer_y: usize = fbGrid_y * sprite_height + y;
                    const framebuffer_x: usize = fbGrid_x * sprite_width + x;
                    const framebuffer_index: usize = (framebuffer_y * fb_width) + framebuffer_x;
                    self.dbgTileFramebuffer[framebuffer_index] = shades[color_index];
                }
            }
        }
        return &self.dbgTileFramebuffer;
    }
};

fn sliceCast(comptime T: type, buffer: []const u8, offset: usize, count: usize) []T {
    if (offset + count * @sizeOf(type) > buffer.len) unreachable;

    const ptr = @intFromPtr(buffer.ptr) + offset;
    const arrPtr: [*]T = @ptrFromInt(ptr);
    return arrPtr[0..count];
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
const math = std.math;
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const tracy = @import("tracy");

// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zig_hello_world_lib");
//const lib = @import("root.zig");
const expect = std.testing.expect;
