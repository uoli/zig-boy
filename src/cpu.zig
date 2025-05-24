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

const Interrupts = packed struct {
    vblank: bool,
    lcd_stat: bool,
    timer: bool,
    serial: bool,
    joypad: bool,
    _: u3,
};

pub const mcycles = usize;
pub const opFunc = *const fn (*Cpu) anyerror!mcycles;

fn init_tables(opcodetable: *[256]OpCodeInfo, jmptable: *[256]opFunc) void {
    const cf = @import("cpu_functions.zig");
    const err: OpCodeInfo = OpCodeInfo.init(0x00, "EXT ERR", .None);
    for (0..255 + 1) |i| {
        opcodetable[i] = err;
        jmptable[i] = &cf.NotImplemented;
    }
}

const JoypadSelectState = enum(u1) { Selected = 0, NotSelected = 1 };
const JoypadButtonFlagState = enum(u1) { Pressed = 0, NotPressed = 1 };

pub const Cpu = struct {
    boot_rom: []const u8,
    cycles_counter: u64,
    bus: *Bus,
    r: Registers,
    sp: u16,
    pc: u16,
    halted: bool,
    interrupt: struct { enabled: bool, interrupt_flag: Interrupts, interrupt_enabled: Interrupts },
    enable_trace: bool,
    disable_boot_rom: u8,
    timer: struct {
        modulo: u8,
        divider_register: u16,
        counter: u8,
        control: packed struct {
            clock_select: u2,
            timer_running: bool,
            _: u5,
        },
    },
    joypad: packed struct {
        P10_Right_or_A: JoypadButtonFlagState,
        P11_Left_or_B: JoypadButtonFlagState,
        P12_Up_or_Select: JoypadButtonFlagState,
        P13_Down_or_Start: JoypadButtonFlagState,
        P14_Select_Direction: JoypadSelectState,
        P15_Select_Button: JoypadSelectState,
        _: u2,
    },
    dma: struct {
        requested: bool,
        source: u16,
        cycles_remaining: u8,
    },
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
        var opcodetable: [256]OpCodeInfo = undefined;
        var jmptable: [256]opFunc = undefined;

        init_tables(&opcodetable, &jmptable);
        cpu_opcode_matadata_gen.get_opcodes_table(&opcodetable);
        const cf = @import("cpu_functions.zig");

        jmptable[0x00] = &cf.nop;
        jmptable[0x01] = &cf.load_d16_to_bc;
        jmptable[0x02] = &cf.load_bc_indirect_to_a;
        jmptable[0x04] = &cf.inc_b;
        jmptable[0x05] = &cf.dec_b;
        jmptable[0x06] = &cf.load_d8_to_b;
        jmptable[0x07] = &cf.rotate_left_carry_a;
        jmptable[0x09] = &cf.add_HL_BC;
        jmptable[0x0b] = &cf.dec_bc;
        jmptable[0x0c] = &cf.inc_c;
        jmptable[0x0d] = &cf.dec_c;
        jmptable[0x0e] = &cf.load_d8_to_c;
        jmptable[0x0f] = &cf.rotate_right_carry_a;
        jmptable[0x11] = &cf.load_d16_to_de;
        jmptable[0x12] = &cf.store_a_to_indirectDE;
        jmptable[0x13] = &cf.inc_de;
        jmptable[0x14] = &cf.inc_d;
        jmptable[0x15] = &cf.dec_d;
        jmptable[0x16] = &cf.load_d8_to_d;
        jmptable[0x17] = &cf.rotate_left_a;
        jmptable[0x18] = &cf.jmp_s8;
        jmptable[0x19] = &cf.add_de_to_hl;
        jmptable[0x1A] = &cf.load_indirectDE_to_a;
        jmptable[0x1B] = &cf.dec_de;
        jmptable[0x1C] = &cf.inc_e;
        jmptable[0x1D] = &cf.dec_e;
        jmptable[0x1E] = &cf.load_d8_to_e;
        jmptable[0x20] = &cf.jmp_nz_s8;
        jmptable[0x21] = &cf.load_d16_to_HL;
        jmptable[0x22] = &cf.store_a_to_IndirectHL_inc;
        jmptable[0x23] = &cf.inc_HL;
        jmptable[0x24] = &cf.inc_H;
        jmptable[0x26] = &cf.load_d8_to_h;
        jmptable[0x28] = &cf.jmp_if_zero;
        jmptable[0x29] = &cf.add_hl_hl;
        jmptable[0x2a] = &cf.load_HL_indirect_inc_to_a;
        jmptable[0x2c] = &cf.inc_l;
        jmptable[0x2e] = &cf.load_d8_to_l;
        jmptable[0x2f] = &cf.compl_a;
        jmptable[0x30] = &cf.jump_not_carry_s8;
        jmptable[0x31] = &cf.load_d16_to_sp;
        jmptable[0x32] = &cf.store_a_to_indirectHL_dec;
        jmptable[0x34] = &cf.inc_indirect_hl;
        jmptable[0x35] = &cf.dec_indirect_hl;
        jmptable[0x36] = &cf.store_d8_to_indirectHL;
        jmptable[0x37] = &cf.set_carry_flag;
        jmptable[0x38] = &cf.jump_s8_if_carry;
        jmptable[0x3a] = &cf.load_indirectHL_dec_to_a;
        jmptable[0x3c] = &cf.inc_a;
        jmptable[0x3d] = &cf.dec_a;
        jmptable[0x3e] = &cf.load_d8_to_a;
        jmptable[0x3f] = &cf.flip_carry_flag;
        jmptable[0x41] = &cf.load_c_to_b;
        jmptable[0x42] = &cf.load_d_to_b;
        jmptable[0x44] = &cf.load_h_to_b;
        jmptable[0x46] = &cf.load_indirect_hl_to_b;
        jmptable[0x47] = &cf.load_a_to_b;
        jmptable[0x4a] = &cf.load_d_to_c;
        jmptable[0x4d] = &cf.load_l_to_c;
        jmptable[0x4f] = &cf.load_a_to_c;
        jmptable[0x50] = &cf.load_b_to_d;
        jmptable[0x51] = &cf.load_c_to_d;
        jmptable[0x54] = &cf.load_h_to_d;
        jmptable[0x56] = &cf.load_indirect_hl_to_d;
        jmptable[0x57] = &cf.load_a_to_d;
        jmptable[0x5D] = &cf.load_l_to_e;
        jmptable[0x5E] = &cf.load_indirect_hl_to_e;
        jmptable[0x5F] = &cf.load_a_to_e;
        jmptable[0x62] = &cf.load_d_to_h;
        jmptable[0x67] = &cf.load_a_to_h;
        jmptable[0x68] = &cf.load_b_to_l;
        jmptable[0x6b] = &cf.load_e_to_l;
        jmptable[0x6e] = &cf.load_indirect_hl_to_l;
        jmptable[0x6f] = &cf.load_a_to_l;
        jmptable[0x70] = &cf.store_b_to_indirectHL;
        jmptable[0x71] = &cf.store_c_to_indirectHL;
        jmptable[0x72] = &cf.store_d_to_indirectHL;
        jmptable[0x73] = &cf.store_e_to_indirectHL;
        jmptable[0x76] = &cf.halt;
        jmptable[0x77] = &cf.store_a_to_indirectHL;
        jmptable[0x78] = &cf.load_b_to_a;
        jmptable[0x79] = &cf.load_c_to_a;
        jmptable[0x7a] = &cf.load_d_to_a;
        jmptable[0x7b] = &cf.load_e_to_a;
        jmptable[0x7c] = &cf.load_h_to_a;
        jmptable[0x7d] = &cf.load_l_to_a;
        jmptable[0x7e] = &cf.load_hl_indirect_to_a;
        jmptable[0x80] = &cf.add_a_to_b;
        jmptable[0x81] = &cf.add_a_to_c;
        jmptable[0x82] = &cf.add_a_to_d;
        jmptable[0x83] = &cf.add_a_to_e;
        jmptable[0x85] = &cf.add_a_to_l;
        jmptable[0x86] = &cf.add_a_to_hl_indirect;
        jmptable[0x87] = &cf.add_a_to_a;
        jmptable[0x88] = &cf.add_b_cy_a_to_a;
        jmptable[0x90] = &cf.subtract_b_from_a;
        jmptable[0x92] = &cf.subtract_d_from_a;
        jmptable[0x95] = &cf.subtract_l_from_a;
        jmptable[0x98] = &cf.subtract_a_b_cf;
        jmptable[0xA0] = &cf.and_b_with_a;
        jmptable[0xA3] = &cf.and_e_with_a;
        jmptable[0xA6] = &cf.and_indirect_hl_a;
        jmptable[0xA7] = &cf.and_a_with_a;
        jmptable[0xA8] = &cf.xor_b_with_a;
        jmptable[0xAF] = &cf.xor_a_with_a;
        jmptable[0xB0] = &cf.or_b_with_a;
        jmptable[0xB1] = &cf.or_c_with_a;
        jmptable[0xB2] = &cf.or_d_with_a;
        jmptable[0xB3] = &cf.or_e_with_a;
        jmptable[0xB6] = &cf.or_indirect_hl_with_a;
        jmptable[0xB8] = &cf.compare_b_to_a;
        jmptable[0xB9] = &cf.compare_c_to_a;
        jmptable[0xBE] = &cf.compare_indirectHL_to_a;
        jmptable[0xC0] = &cf.return_if_not_zero;
        jmptable[0xC1] = &cf.pop_bc;
        jmptable[0xC2] = &cf.jmp_if_not_zero;
        jmptable[0xC3] = &cf.jmp;
        jmptable[0xC5] = &cf.push_bc;
        jmptable[0xC6] = &cf.add_a_d8;
        jmptable[0xC8] = &cf.return_from_call_condiional_on_z;
        jmptable[0xC9] = &cf.return_from_call;
        jmptable[0xCA] = &cf.jump_if_zero_a16;
        //jmptable[0xCB] = &cf.cb_extended;
        jmptable[0xCC] = &cf.call_if_zero;
        jmptable[0xCD] = &cf.call16;
        jmptable[0xD0] = &cf.retun_if_no_carry;
        jmptable[0xD1] = &cf.pop_de;
        jmptable[0xD2] = &cf.jmp_absolute_not_carry;
        jmptable[0xD5] = &cf.push_de;
        jmptable[0xD6] = &cf.sub_d8;
        jmptable[0xD8] = &cf.return_if_carry;
        jmptable[0xD9] = &cf.return_enable_interupt;
        jmptable[0xDA] = &cf.jmp_absolute_if_carry;
        jmptable[0xE0] = &cf.load_a_to_indirect8;
        jmptable[0xE1] = &cf.pop_to_HL;
        jmptable[0xE2] = &cf.store_a_to_indirect_c;
        jmptable[0xE5] = &cf.push_hl;
        jmptable[0xE6] = &cf.and_d8_to_a;
        jmptable[0xE9] = &cf.jmp_hl;
        jmptable[0xEA] = &cf.load_a_to_indirect16;
        jmptable[0xEE] = &cf.xor_d8_to_a;
        jmptable[0xF0] = &cf.load_indirect8_to_a;
        jmptable[0xF1] = &cf.pop_af;
        jmptable[0xF3] = &cf.disable_interrupts;
        jmptable[0xF5] = &cf.push_af;
        jmptable[0xF6] = &cf.or_d8;
        jmptable[0xF8] = &cf.add_sp_s8_to_hl;
        jmptable[0xF9] = &cf.load_hl_to_sp;
        jmptable[0xFA] = &cf.load_indirect16_to_a;
        jmptable[0xFB] = &cf.enable_interrupts;
        jmptable[0xFE] = &cf.compare_immediate8_ra;


        var extended_opcodetable: [256]OpCodeInfo = undefined;
        var extended_jmptable: [256]opFunc = undefined;
        init_tables(&extended_opcodetable, &extended_jmptable);

        cpu_opcode_matadata_gen.get_extopcodes_table(&extended_opcodetable);

        extended_jmptable[0x0e] = &cf.rotate_right_indirect_HL;
        extended_jmptable[0x11] = &cf.rotate_left_c;
        extended_jmptable[0x12] = &cf.rotate_left_d;
        extended_jmptable[0x1A] = &cf.rotate_right_d;
        extended_jmptable[0x1B] = &cf.rotate_right_e;
        extended_jmptable[0x20] = &cf.shift_left_B;
        extended_jmptable[0x23] = &cf.shift_left_e;
        extended_jmptable[0x27] = &cf.shift_left_a;
        extended_jmptable[0x2A] = &cf.shift_right_d;
        extended_jmptable[0x36] = &cf.swap_indirect_hl;
        extended_jmptable[0x37] = &cf.swap_a;
        extended_jmptable[0x3f] = &cf.shift_right_a;
        extended_jmptable[0x42] = &cf.copy_compl_dbit0_to_z;
        extended_jmptable[0x46] = &cf.copy_compl_indirect_hl_bit0_to_z;
        extended_jmptable[0x47] = &cf.copy_compl_abit0_to_z;
        extended_jmptable[0x4e] = &cf.copy_compl_indirect_hl_bit1_to_z;
        extended_jmptable[0x4f] = &cf.copy_compl_abit1_to_z;
        extended_jmptable[0x56] = &cf.copy_compl_indirect_hl_bit2_to_z;
        extended_jmptable[0x57] = &cf.copy_compl_abit2_to_z;
        extended_jmptable[0x5E] = &cf.copy_compl_indirect_hl_bit3_to_z;
        extended_jmptable[0x66] = &cf.copy_compl_indirect_hl_bit4_to_z;
        extended_jmptable[0x6f] = &cf.copy_compl_abit5_to_z;
        extended_jmptable[0x76] = &cf.copy_compl_indirect_hl_bit6_to_z;
        extended_jmptable[0x77] = &cf.copy_compl_abit6_to_z;
        extended_jmptable[0x7c] = &cf.copy_compl_hbit7_to_z;
        extended_jmptable[0x7f] = &cf.copy_compl_abit7_to_z;
        extended_jmptable[0x86] = &cf.reset_indirect_hl_bit0;
        extended_jmptable[0x87] = &cf.reset_a_bit0;
        extended_jmptable[0x8F] = &cf.reset_a_bit1;
        extended_jmptable[0x96] = &cf.reset_indirect_hl_bit2;
        extended_jmptable[0x97] = &cf.reset_a_bit2;
        extended_jmptable[0x9E] = &cf.reset_indirect_hl_bit3;
        extended_jmptable[0xA6] = &cf.reset_indirecthl_bit4;
        extended_jmptable[0xAE] = &cf.reset_indirecthl_bit5;
        extended_jmptable[0xAF] = &cf.reset_a_bit5;
        extended_jmptable[0xD6] = &cf.set_indirect_hl_bit2;
        extended_jmptable[0xDE] = &cf.set_indirect_hl_bit3;
        extended_jmptable[0xF6] = &cf.set_indirect_hl_bit6;
        extended_jmptable[0xFF] = &cf.set_a_bit7;

        //const opcodetable, const jmptable = process_opcodetable(&opcodesInfo, &opcodesFunc);
        //const extended_opcodetable, const extended_jmptable = process_opcodetable(&extended_opcodesInfo, &extended_opcodesFunc);

        return Cpu{
            .boot_rom = boot_rom,
            .cycles_counter = 0,
            .disable_boot_rom = 0,
            .bus = bus,
            .r = Registers.init(),
            .sp = 0x0,
            .pc = 0x0,
            .halted = false,
            .enable_trace = false,
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
            .timer = .{
                .modulo = 0,
                .control = .{
                    .clock_select = 0,
                    .timer_running = false,
                    ._ = undefined,
                },
                .divider_register = 0,
                .counter = 0,
            },
            .joypad = .{
                .P10_Right_or_A = JoypadButtonFlagState.NotPressed,
                .P11_Left_or_B = JoypadButtonFlagState.NotPressed,
                .P12_Up_or_Select = JoypadButtonFlagState.NotPressed,
                .P13_Down_or_Start = JoypadButtonFlagState.NotPressed,
                .P14_Select_Direction = JoypadSelectState.NotSelected,
                .P15_Select_Button = JoypadSelectState.NotSelected,
                ._ = 0,
            },
            .dma = .{
                .requested = false,
                .source = 0x00,
                .cycles_remaining = 0,
            },
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

    pub fn load(self: *Cpu, address: u16) u8 {
        if (self.disable_boot_rom == 0 and address < 0x0100) {
            return self.boot_rom[address];
        }
        switch (address) {
            0xFF00 => {
                return @bitCast(self.joypad);
            },
            0xFF04 => {
                return @truncate(self.timer.divider_register);
            },
            0xFF10...0xFF25 => {
                //No-Impl Sound related I/O ops
                return 0;
            },
            0xFFFF => {
                return @bitCast(self.interrupt.interrupt_enabled);
            },
            else => {
                return self.bus.read(address);
            },
        }
    }

    pub fn load16(self: *Cpu, address: u16) u16 {
        var result: u16 = 0;
        result += self.load(address);
        result += @as(u16, self.load(address + 1)) << 8;
        return result;
    }

    pub fn store(self: *Cpu, address: u16, value: u8) void {
        switch (address) {
            0xFF00 => {
                //Only bit 5 and 4 are actually writable
                const currentVal: u8 = @bitCast(self.joypad);
                const newVal: u8 = currentVal | (value & 0b00110000);
                self.joypad = @bitCast(newVal);
            },
            0xFF01 => {
                self.serial_data_transfer.data = value;
            },
            0xFF02 => {
                //Serial Data Transfer? ignore for now
                self.serial_data_transfer.control = @bitCast(value);
            },
            0xFF04 => {
                self.timer.divider_register = 0;
            },
            0xFF06 => {
                self.timer.modulo = value;
            },
            0xFF07 => {
                self.timer.control = @bitCast(value);
            },
            0xFF10...0xFF25 => {
                //No-Impl Sound related I/O ops
            },
            0xFF26 => {
                self.sound_flags = @bitCast(value);
            },
            0xFF46 => {
                self.request_dma_transfer(value);
            },
            0xFF50 => {
                self.disable_boot_rom = value;
            },
            0xFF0F => {
                self.interrupt.interrupt_flag = @bitCast(value);
            },
            0xFFFF => {
                self.interrupt.interrupt_enabled = @bitCast(value);
            },
            else => {
                self.bus.write(address, value);
            },
        }
    }

    fn request_dma_transfer(self: *Cpu, addr_base_req: u8) void {
        self.dma.requested = true;
        var addr_base = addr_base_req;
        if (addr_base == 0xfe) addr_base = 0xde;
        if (addr_base == 0xff) addr_base = 0xdf;
        self.dma.source = addr_base;
        self.dma.source = self.dma.source << 8;
        self.dma.cycles_remaining = 160;
    }

    fn handle_dma(self: *Cpu, cycles_elapsed: mcycles) void {
        if (self.dma.requested == false) return;
        for (0x00..0x9F + 1) |value| {
            const value16: u16 = @intCast(value);
            const source: u16 = self.dma.source + value16;
            const dest: u16 = 0xFE00 + value16;
            self.bus.write(dest, self.bus.read(source));
        }
        if (self.dma.cycles_remaining < cycles_elapsed) {
            self.dma.cycles_remaining = 0;
            self.dma.requested = false;
        } else {
            self.dma.cycles_remaining -= @intCast(cycles_elapsed);
        }
    }

    fn tick_timer(self: *Cpu, cycles_elapsed: mcycles) void {
        //main clock = 4194304 hz in t-cycles

        //timer_clock_0 = 1 -> 4096hz   in t-cycles, 1024 times slower
        //timer_clock_1 = 1 -> 262144hz in t-cycles, 16   times slower
        //timer_clock_2 = 1 -> 65536hz  in t-cycles, 64   times slower
        //timer_clock_3 = 1 -> 16384hz  in t-cycles, 256  times slower

        const start_divider_val = self.timer.divider_register;
        self.timer.divider_register +%= @intCast(cycles_elapsed);

        if (self.timer.control.timer_running) {
            var counter_increase: u8 = 0;
            switch (self.timer.control.clock_select) {
                0 => {
                    const timer4bit = (start_divider_val & 0b1111111111) + @as(u16, @intCast(cycles_elapsed));
                    counter_increase = @intCast(timer4bit % 1024);
                },
                1 => {
                    const timer16bit = (start_divider_val & 0b1111) + @as(u16, @intCast(cycles_elapsed));
                    counter_increase = @intCast(timer16bit % 16);
                },
                2 => {
                    const timer64bit = (start_divider_val & 0b111111) + @as(u16, @intCast(cycles_elapsed));
                    counter_increase = @intCast(timer64bit % 64);
                },
                3 => {
                    const timer256bit = (start_divider_val & 0xFF) + @as(u16, @intCast(cycles_elapsed));
                    counter_increase = @intCast(timer256bit % 256);
                },
            }
            self.timer.counter, const overflow = @addWithOverflow(self.timer.counter, counter_increase);
            if (overflow == 1) {
                self.timer.counter = self.timer.modulo;
                self.raise_interrupt(Interrup.Timer);
            }
        }
    }

    pub fn fetch(self: *Cpu) u8 {
        const result = self.load(self.pc);
        self.pc += 1;
        return result;
    }

    pub fn fetch16(self: *Cpu) u16 {
        const result: u16 = self.load16(self.pc);
        self.pc += 2;
        return result;
    }

    pub fn push16(self: *Cpu, value: u16) void {
        if (value == 0x60ed or value == 0x60e0 or value == 0x60dd or value == 0x60ca) {
            //@breakpoint();
        }
        self.sp -= 1;
        self.store(self.sp, @intCast(value >> 8));
        self.sp -= 1;
        self.store(self.sp, @intCast(value & 0xFF));
    }

    pub fn pop16(self: *Cpu) u16 {
        const low = self.load(self.sp);
        self.sp += 1;
        const high = self.load(self.sp);
        self.sp += 1;
        return @as(u16, high) << 8 | low;
    }

    fn decode_and_execute(self: *Cpu) mcycles {
        {
            const watched_pcs = [_]u16{
                0x0000,
                //0x0100,
                //0x60a7,
                //0x6155,
                //0x0171,

                //0x1dd1,
                //0x4e4b,
                //0x59d8,
                //0x55d6,
                //0x4086,
                //0x5219,
                //0x58de,
                //0x565f,
            };
            //const watched_pcs = [_]u16{};
            //const watched_pc = 0xFFFF;
            if (contains(u16, &watched_pcs, self.pc) == true)
                self.enable_trace = true;

            if (self.enable_trace)
                self.print_trace();
        }
        // if (self.pc == 0x53cd) {
        //     @breakpoint();
        // }

        const instruction = self.fetch();
        var cycles: mcycles = 0;

        if (instruction == 0xCB) {
            const extended_instruction = self.fetch();
            if (extended_instruction == 124 and self.disable_boot_rom == 1) {
                //@breakpoint();
            }
            const func = self.extended_jmptable[extended_instruction];
            cycles = func(self) catch {
                std.debug.panic("Error decoding and executing ext opcode 0xCB, 0x{x:02}\n", .{extended_instruction});
            };
        } else {
            cycles = self.jmptable[instruction](self) catch {
                std.debug.panic("Error decoding and executing opcode 0x{x:02}\n", .{instruction});
            };
        }

        return cycles;
    }

    pub fn step(self: *Cpu) mcycles {
        const zone = tracy.beginZone(@src(), .{ .name = "cpu step" });
        defer zone.end();

        if (self.halted) return 1;

        var clocks = execute_interrupts_if_enabled(self);
        clocks += self.decode_and_execute();
        self.handle_dma(clocks);
        self.tick_timer(clocks);
        self.cycles_counter += clocks;
        return clocks;
    }

    fn contains(comptime T: type, haystack: []const T, needle: T) bool {
        for (haystack) |item| {
            if (item == needle) {
                return true;
            }
        }
        return false;
    }

    fn execute_interrupt(self: *Cpu, interrupt_address: u16) mcycles {
        Logger.log("Interrupt 0x{x}\n", .{interrupt_address});
        self.push16(self.pc);
        self.pc = interrupt_address;
        return 5;
    }

    pub const Interrup = enum(u8) {
        VBlank = 0b00000001,
        LCDStat = 0b00000010,
        Timer = 0b00000100,
        Serial = 0b00001000,
        Joypad = 0b00010000,
    };

    pub fn raise_interrupt(self: *Cpu, interrupt: Interrup) void {
        const interrupt_bit_mask: u8 = @intFromEnum(interrupt);
        const current_interrupts: u8 = @bitCast(self.interrupt.interrupt_flag);
        const new_bitmask = interrupt_bit_mask | current_interrupts;
        self.interrupt.interrupt_flag = @bitCast(new_bitmask);

        if (@as(u8, @bitCast(self.interrupt.interrupt_enabled)) & interrupt_bit_mask != 0) {
            self.halted = false;
        }
    }

    fn execute_interrupts_if_enabled(self: *Cpu) mcycles {
        if (!self.interrupt.enabled) {
            return 0;
        }
        const bitMaskToInterrupt = [_]struct { u8, u16 }{
            .{ @intFromEnum(Interrup.VBlank), 0x0040 },
            .{ @intFromEnum(Interrup.LCDStat), 0x0048 },
            .{ @intFromEnum(Interrup.Timer), 0x0050 },
            .{ @intFromEnum(Interrup.Serial), 0x0058 },
            .{ @intFromEnum(Interrup.Joypad), 0x0060 },
        };

        for (bitMaskToInterrupt) |mask| {
            const enabled_interrupts_bitfield: u8 = @bitCast(self.interrupt.interrupt_enabled);
            const current_interrupts_bitfield: u8 = @bitCast(self.interrupt.interrupt_flag);
            const interrupts_to_execute_bitfield: u8 = enabled_interrupts_bitfield & current_interrupts_bitfield;
            if (interrupts_to_execute_bitfield & mask[0] != 0) {
                self.interrupt.enabled = false;
                self.interrupt.interrupt_flag = @bitCast(current_interrupts_bitfield & ~mask[0]);
                return self.execute_interrupt(mask[1]);
            }
        }
        return 0;
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
        const arg = opInfo.arg;
        var args_str: [8:0]u8 = undefined;
        @memset(args_str[0..], ' ');

        switch (arg) {
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
        Logger.log("[CPU] 0x{x:04} 0x{x:02} {s: <12}{s} AF:0x{x:04} BC:0x{x:04} DE:0x{x:04} HL:0x{x:04} SP:0x{x:04} {s}\n", .{ self.pc, opInfo.code, opInfo.name, args_str, self.r.f.AF, self.r.f.BC, self.r.f.DE, self.r.f.HL, self.sp, self.r.debug_flag_str() });
    }
};

const std = @import("std");
const tracy = @import("tracy");
const bus_import = @import("bus.zig");
const cpu_utils = @import("cpu_utils.zig");
const cpu_opcode_matadata_gen = @import("cpu_opcode_matadata_gen");
const Logger = @import("logger.zig");

const Bus = bus_import.Bus;
const OpCodeInfo = cpu_utils.OpCodeInfo;
