fn load_rom(abs_rom_location: []const u8, max_bytes: usize, allocator: Allocator) ![]u8 {
    var file = try std.fs.openFileAbsolute(abs_rom_location, .{});
    defer file.close();

    // Read the contents
    const cartridge_rom = try file.readToEndAlloc(allocator, max_bytes);

    return cartridge_rom;
}

const System = struct {
    tracer: Tracer,
    bus: Bus,
    cpu: Cpu,
    gpu: Gpu,
    joypad: Joypad,
    timer: Timer,
    cartridge: Cartridge,
    ram: [64 << 10]u8,
};

pub const Emulator = struct {
    //gpa: std.heap.DebugAllocator,
    allocator: std.mem.Allocator,
    system: *System,
    boot_rom: []u8,
    cartridge_rom: []u8,
    external_ram: []u8,

    pub fn Init(allocator: Allocator, enable_tracer: bool) !Emulator {
        const boot_location = "F:\\Projects\\higan\\higan\\System\\Game Boy\\boot.dmg-1.rom";
        const rom_location = "C:\\Users\\Leo\\Emulation\\Gameboy\\Pokemon Red (UE) [S][!].gb";
        //const rom_location = "C:\\Users\\Leo\\Emulation\\Gameboy\\Tetris (World) (Rev 1).gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\cpu_instrs\\cpu_instrs.gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\cpu_instrs\\individual\\01-special.gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\cpu_instrs\\individual\\03-op sp,hl.gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\cpu_instrs\\individual\\09-op r,r.gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\cpu_instrs\\individual\\10-bit ops.gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\instr_timing\\instr_timing.gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\interrupt_time\\interrupt_time.gb"; //GBC only
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\blargg\\mem_timing-2\\mem_timing.gb";
        //const rom_location = "F:\\Projects\\game-boy-emu-zig\\test-roms\\dmg-acid2\\dmg-acid2.gb";

        const buffer_size = 2 * 1024 * 1024;

        const sys = try allocator.create(System);
        errdefer allocator.destroy(sys);

        const boot_rom = try load_rom(boot_location, 256, allocator);
        const cartridge_rom = try load_rom(rom_location, buffer_size, allocator);
        const external_ram = try allocator.alloc(u8, 64 << 10);
        @memset(&sys.ram, 0);

        sys.cartridge = Cartridge.init(cartridge_rom[0..], external_ram[0..]);
        sys.tracer = Tracer.init(enable_tracer);
        sys.bus = Bus.init(&sys.ram, &sys.cartridge);
        sys.gpu = Gpu.init(&sys.bus, &sys.ram, &sys.tracer);
        sys.cpu = Cpu.init(boot_rom, &sys.bus, &sys.tracer);
        sys.joypad = Joypad.init(&sys.bus);
        sys.timer = Timer.init(&sys.bus);

        sys.bus.connectGpu(&sys.gpu);
        sys.bus.connectCpu(&sys.cpu);
        sys.bus.connectTimer(&sys.timer);
        sys.bus.connectJoypad(&sys.joypad);

        return Emulator{
            //.gpa = gpa,
            .allocator = allocator,

            .boot_rom = boot_rom,
            .cartridge_rom = cartridge_rom,
            .external_ram = external_ram,
            .system = sys,
        };
    }

    pub fn close(self: Emulator) void {
        self.allocator.free(self.system.bus.ram);

        self.allocator.free(self.external_ram);
        self.allocator.free(self.cartridge_rom);
        self.allocator.free(self.boot_rom);

        self.allocator.destroy(self.system);
    }

    pub fn run_until_frameready(self: Emulator) !void {
        const zone = tracy.beginZone(@src(), .{ .name = "run_until_frameready" });
        defer zone.end();
        while (!self.system.gpu.consume_frame_ready()) {
            _ = self.system.cpu.step();
        }
    }

    pub fn getFrameBuffer(self: Emulator) FrameBufferInfo {
        return FrameBufferInfo{ .framebuffer = &self.system.gpu.framebuffer, .width = Gpu.RESOLUTION_WIDTH, .height = Gpu.RESOLUTION_HEIGHT };
    }

    pub fn snapshotTiles(self: Emulator) FrameBufferInfo {
        return FrameBufferInfo{ .framebuffer = self.system.gpu.snapshotTiles(), .width = 16 * 8, .height = 24 * 8 };
    }
};

pub const FrameBufferInfo = struct {
    framebuffer: []u8,
    width: u32,
    height: u32,
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const tracy = @import("tracy");
//pub const cpu_functions = @import("cpu_functions.zig");
const cpu_import = @import("cpu.zig");
const bus_import = @import("bus.zig");
const gpu_import = @import("gpu.zig");
const cartridge_import = @import("cartridge.zig");
const Logger = @import("logger.zig");
const Tracer = @import("tracer.zig").Tracer;
const Timer = @import("timer.zig").Timer;
const Joypad = @import("joypad.zig").Joypad;
const Bus = bus_import.Bus;
const Cpu = cpu_import.Cpu;
const Gpu = gpu_import.Gpu;
const Cartridge = cartridge_import.Cartridge;
const GpuStepResult = gpu_import.GpuStepResult;
