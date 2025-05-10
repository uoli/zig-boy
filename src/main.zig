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
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    //  Get an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }
    //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena.deinit();
    //const allocator = arena.allocator();

    const boot_location = "F:\\Projects\\higan\\higan\\System\\Game Boy\\boot.dmg-1.rom";
    const rom_location = "C:\\Users\\Leo\\Emulation\\Gameboy\\Pokemon Red (UE) [S][!].gb";
    const buffer_size = 2 * 1024 * 1024;

    const boot_rom = try load_rom(boot_location, 256, std.heap.page_allocator);
    defer allocator.free(boot_rom);

    const cartridge_rom = try load_rom(rom_location, buffer_size, std.heap.page_allocator);
    defer allocator.free(cartridge_rom);

    //var device_rom = [];

    var ram: [8 << 10 << 10]u8 = undefined;
    @memset(&ram, 0);

    var bus = Bus.init(ram[0..ram.len], cartridge_rom[0..cartridge_rom.len]);

    var cpu = Cpu.init(boot_rom, &bus);

    while (true) {
        cpu.step();
    }

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!
}

const Bus = struct {
    ram: []u8,
    cartridgerom: []const u8,

    pub fn init(ram: []u8, cartridge_rom: []const u8) Bus {
        return Bus{
            .ram = ram,
            .cartridgerom = cartridge_rom,
        };
    }

    pub fn read(self: Bus, address: u16) u8 {
        return switch (address) {
            0...0x3FFF => {
                return self.cartridgerom[address];
            },
            0xFF00...0xFFFF => { // HRAM
                return self.ram[address];
            },
            else => {
                std.debug.panic("unhandled read address 0x{x}", .{address});
            },
        };
    }

    pub fn write(self: Bus, address: u16, value: u8) void {
        switch (address) {
            0...0x3FFF => {
                @panic("Cannot write to ROM");
            },
            0x8000...0x9FFF => { //vram
                //TODO: do we need to split ram from vram?
                self.ram[address] = value;
            },
            0xC000...0xCFFF => {
                self.ram[address] = value;
            },
            0xFF00...0xFFFF => { // HRAM
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
    length: u8,
    cycles: u8,
    args: [2]ArgInfo,
    f: *const fn (*Cpu) anyerror!void,
    pub fn init(code: u8, name: []const u8, length: u8, cycles: u8, args: [2]ArgInfo, f: *const fn (*Cpu) anyerror!void) OpCodeInfo {
        return OpCodeInfo{
            .name = name,
            .code = code,
            .length = length,
            .cycles = cycles,
            .args = args,
            .f = f,
        };
    }
};

fn NotImplemented(_: *Cpu) !void {
    return error.NotImplemented;
}

fn nop(_: *Cpu) !void {}

fn load_d8_to_c(cpu: *Cpu) !void {
    cpu.r.s.c = Cpu.fetch(cpu);
}

fn load_a_to_b(cpu: *Cpu) !void {
    cpu.r.s.b = cpu.r.s.a;
}

fn load_D_to_b(cpu: *Cpu) !void {
    cpu.r.s.b = cpu.r.s.d;
}

fn load_d16_to_sp(cpu: *Cpu) !void {
    cpu.sp = cpu.fetch16();
}

fn store_a_to_indirectHL_dec(cpu: *Cpu) !void {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    cpu.r.f.HL -= 1;
}

fn load_d8_to_a(cpu: *Cpu) !void {
    cpu.r.s.a = Cpu.fetch(cpu);
}

fn load_indirect16_to_a(cpu: *Cpu) !void {
    const addr = Cpu.fetch16(cpu);
    cpu.r.s.a = cpu.load(addr);
}

fn load_a_to_indirect16(cpu: *Cpu) !void {
    const addr = Cpu.fetch16(cpu);
    cpu.store(addr, cpu.r.s.a);
}

fn load_indirect8_to_a(cpu: *Cpu) !void {
    const addr: u16 = 0xFF00 + @as(u16, Cpu.fetch(cpu));
    cpu.r.s.a = cpu.load(addr);
}

fn load_a_to_indirect8(cpu: *Cpu) !void {
    const addr: u16 = 0xFF00 + @as(u16, Cpu.fetch(cpu));

    cpu.store(addr, cpu.r.s.a);
}

fn pop_to_HL(cpu: *Cpu) !void {
    cpu.r.f.HL = cpu.pop16();
}

fn store_a_to_indirect_c(cpu: *Cpu) !void {
    cpu.store(0xFF00 + @as(u16, cpu.r.s.c), cpu.r.s.a);
}

fn add_u8_as_signed_to_u16(dest: u8, pc: u16) u16 {
    const signed_dest: i16 = @intCast(@as(i8, @bitCast(dest)));
    const pc_signed: i16 = @intCast(pc);
    const new_pc_singed: i16 = pc_signed + signed_dest;
    return @intCast(new_pc_singed);
}

fn jmp(cpu: *Cpu) !void {
    const dest = Cpu.fetch16(cpu);
    cpu.pc = dest;
}

fn jmp_s8(cpu: *Cpu) !void {
    const dest = Cpu.fetch(cpu);
    cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
}

fn jmp_nz_s8(cpu: *Cpu) !void {
    const dest = Cpu.fetch(cpu);
    if (cpu.r.s.f.z == 0) {
        cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
    }
}

fn load_d16_to_HL(cpu: *Cpu) !void {
    cpu.r.f.HL = Cpu.fetch16(cpu);
}

fn jmp_if_zero(cpu: *Cpu) !void {
    const dest = Cpu.fetch(cpu);
    if (cpu.r.s.f.z == 1) {
        cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
    }
}

fn call16(cpu: *Cpu) !void {
    cpu.push16(cpu.pc);
    const dest = Cpu.fetch16(cpu);
    cpu.pc = dest;
}

fn compare_immediate8_ra(cpu: *Cpu) !void {
    const immediate = Cpu.fetch(cpu);
    cpu.r.s.f.z = if (cpu.r.s.a == immediate) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) < (immediate & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (cpu.r.s.a < immediate) 1 else 0;
}

fn xor_a_with_a(cpu: *Cpu) !void {
    cpu.r.s.a ^= cpu.r.s.a;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
}

fn disable_interrupts(cpu: *Cpu) !void {
    cpu.interrupt.enabled = false;
}

fn shift_left_B(cpu: *Cpu) !void {
    cpu.r.s.b = cpu.r.s.b << 1;
    //Z N H C
    cpu.r.s.f.z = if (cpu.r.s.b == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = if ((cpu.r.s.b >> 7) == 1) 1 else 0;
}

fn copy_compl_bit7_to_z(cpu: *Cpu) !void {
    cpu.r.s.f.z = if ((cpu.r.s.h >> 7) != 1) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
}

fn reset_a_bit0(cpu: *Cpu) !void {
    cpu.r.s.a &= 0xFE;
}

const Interrupts = packed struct {
    vblank: bool,
    lcd_stat: bool,
    timer: bool,
    serial: bool,
    joypad: bool,
    _: u3,
};

fn process_opcodetable(table: []const OpCodeInfo) struct { [256]OpCodeInfo, [256]*const fn (*Cpu) anyerror!void } {
    const NoArgs = [_]ArgInfo{ .None, .None };
    const err: OpCodeInfo = OpCodeInfo.init(0x00, "EXT ERR", 0, 0, NoArgs, &NotImplemented);
    var opcodetable: [256]OpCodeInfo = undefined;
    var jmptable: [256]*const fn (*Cpu) anyerror!void = undefined;
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
    scroll_x: u8,
    scroll_y: u8,
    window_x: u8,
    window_y: u8,
    disable_boot_rom: u8,
    timer: struct { modulo: u8, control: packed struct {
        clock_select: u2,
        timer_stop: bool,
        _: u5,
    } },
    lcd_control: packed struct {
        bg_display: bool,
        obj_display_enable: bool,
        obj_size: bool,
        bg_tilemap_display_select: bool,
        bg_and_window_tile_select: bool,
        window_display_enable: bool,
        window_tilemap_display_select: bool,
        lcd_dissplay_enable: bool,
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
    jmptable: [256]*const fn (*Cpu) anyerror!void,
    extended_opcodetable: [256]OpCodeInfo,
    extended_jmptable: [256]*const fn (*Cpu) anyerror!void,

    pub fn init(boot_rom: []const u8, bus: *Bus) Cpu {
        const NoArgs = [_]ArgInfo{ .None, .None };
        const Single8Arg = [_]ArgInfo{ .U8, .None };
        const Single16Arg = [_]ArgInfo{ .U16, .None };

        const opcodesInfo = [_]OpCodeInfo{
            OpCodeInfo.init(0x00, "NOP", 0, 0, NoArgs, &nop),
            OpCodeInfo.init(0x0e, "LD C, d8", 0, 0, NoArgs, &load_d8_to_c),
            OpCodeInfo.init(0x18, "JR s8", 0, 0, Single8Arg, &jmp_s8),
            OpCodeInfo.init(0x20, "JR NZ, s8", 0, 0, Single8Arg, &jmp_nz_s8),
            OpCodeInfo.init(0x21, "LD HL, d16", 0, 0, Single16Arg, &load_d16_to_HL),
            OpCodeInfo.init(0x28, "JR Z", 0, 0, Single8Arg, &jmp_if_zero),
            OpCodeInfo.init(0x31, "LD SP, d16", 0, 0, Single16Arg, &load_d16_to_sp),
            OpCodeInfo.init(0x32, "LD (HL-), A", 0, 0, NoArgs, &store_a_to_indirectHL_dec),
            OpCodeInfo.init(0x3e, "LD A, d8", 0, 0, Single8Arg, &load_d8_to_a),
            OpCodeInfo.init(0x47, "LD B, A", 0, 0, NoArgs, &load_a_to_b),
            OpCodeInfo.init(0x50, "LD D, B", 0, 0, NoArgs, &load_D_to_b),
            OpCodeInfo.init(0xAF, "XOR A", 0, 0, NoArgs, &xor_a_with_a),
            OpCodeInfo.init(0xC3, "JMP", 0, 0, Single16Arg, &jmp),
            //OpCodeInfo.init(0xCB, "Xtended", 0, 0, Single16Arg, &cb_extended),
            OpCodeInfo.init(0xCD, "CALL a16", 0, 0, Single16Arg, &call16),
            OpCodeInfo.init(0xE0, "LD (a8), A", 0, 0, Single8Arg, &load_a_to_indirect8),
            OpCodeInfo.init(0xE1, "POP HL", 0, 0, NoArgs, &pop_to_HL),
            OpCodeInfo.init(0xE2, "LD (C), A", 0, 0, NoArgs, &store_a_to_indirect_c),
            OpCodeInfo.init(0xEA, "LD (a16), A", 0, 0, Single16Arg, &load_a_to_indirect16),
            OpCodeInfo.init(0xF0, "LD A, (a8)", 0, 0, Single8Arg, &load_indirect8_to_a),
            OpCodeInfo.init(0xF3, "DI", 0, 0, NoArgs, &disable_interrupts),
            OpCodeInfo.init(0xFE, "CP A,", 0, 0, Single8Arg, &compare_immediate8_ra),
            OpCodeInfo.init(0xFA, "LD A (a16)", 0, 0, Single16Arg, &load_indirect16_to_a),
        };

        const extended_opcodesInfo = [_]OpCodeInfo{
            OpCodeInfo.init(0x20, "SLA B", 0, 0, NoArgs, &shift_left_B),
            OpCodeInfo.init(0x7c, "BIT 7, H", 0, 0, NoArgs, &copy_compl_bit7_to_z),
            OpCodeInfo.init(0x87, "RES 0, A", 0, 0, NoArgs, &reset_a_bit0),
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
            .scroll_x = 0,
            .scroll_y = 0,
            .window_x = 0,
            .window_y = 0,
            .timer = .{ .modulo = 0, .control = .{ .clock_select = 0, .timer_stop = false, ._ = undefined } },
            .lcd_control = @bitCast(@as(u8, 0x91)),
            .background_palette = .{ .color0 = 0, .color1 = 0, .color2 = 0, .color3 = 0 },
            .object_palette = .{ .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 }, .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 } },
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
            0xFF40 => {
                self.lcd_control = @bitCast(value);
            },
            0xFF42 => {
                self.scroll_y = value;
            },
            0xFF43 => {
                self.scroll_x = value;
            },
            0xFF47 => {
                self.background_palette = @bitCast(value);
            },
            0xFF48 => {
                self.object_palette[0] = @bitCast(value);
            },
            0xFF49 => {
                self.object_palette[1] = @bitCast(value);
            },
            0xFF50 => {
                self.disable_boot_rom = value;
            },
            0xFF4A => {
                self.window_y = value;
            },
            0xFF4B => {
                self.window_x = value;
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

    fn decode_and_execute(self: *Cpu, instruction: u8) void {
        if (instruction == 0xCB) {
            const extended_instruction = self.fetch();
            self.extended_jmptable[extended_instruction](self) catch {
                std.debug.panic("Error decoding and executing ext opcode 0xCB, 0x{x:02}\n", .{extended_instruction});
            };
            return;
        }
        self.jmptable[instruction](self) catch {
            std.debug.panic("Error decoding and executing opcode 0x{x:02}\n", .{instruction});
        };
    }

    pub fn step(self: *Cpu) void {
        self.print_trace();
        const instruction = self.fetch();
        self.decode_and_execute(instruction);
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

        std.debug.print("[CPU] 0x{x:04} 0x{x:02} {s: <6}{s} AF:0x{x:04} BC:0x{x:04} DE:0x{x:04} HL:0x{x:04} SP:0x{x:04} {s}\n", .{ self.pc, opInfo.code, opInfo.name, args_str, self.r.f.AF, self.r.f.BC, self.r.f.DE, self.r.f.HL, self.sp, self.r.debug_flag_str() });
    }
};

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

// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zig_hello_world_lib");
//const lib = @import("root.zig");
const expect = std.testing.expect;
