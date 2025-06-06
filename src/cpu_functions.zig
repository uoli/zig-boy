const cpu_import = @import("cpu.zig");
const Cpu = cpu_import.Cpu;

const mcycles = cpu_import.mcycles;
const opFunc = cpu_import.opFunc;

pub fn nop(_: *Cpu) !mcycles {
    return 1;
}

pub fn NotImplemented(_: *Cpu) !mcycles {
    return error.NotImplemented;
}

fn dec_8(cpu: *Cpu, reg: *u8) mcycles {
    reg.* -%= 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if (reg.* & 0xF == 0xF) 1 else 0;
    return 1;
}

fn dec_16(_: *Cpu, reg: *u16) mcycles {
    reg.* -%= 1;
    //cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    //cpu.r.s.f.n = 1;
    //cpu.r.s.f.h = if ((reg.* & 0x0f) == 0x0f) 1 else 0;
    return 2;
}

fn inc_8(cpu: *Cpu, reg: *u8) mcycles {
    reg.* +%= 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((reg.* & 0xF) == 0) 1 else 0; //verify this
    return 1;
}

fn inc_u16(_: *Cpu, reg: *u16) mcycles {
    reg.* +%= 1;
    //cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    // cpu.r.s.f.n = 0;
    // cpu.r.s.f.h = if ((reg.* & 0xFF) == 0) 1 else 0; //verify this
    return 2;
}

fn rotate_l(cpu: *Cpu, data: *u8) void {
    const carry: u1 = if (data.* & 0b1000_0000 != 0) 1 else 0;
    const shifted = (data.* << 1);
    const around = @as(u8, cpu.r.s.f.c);
    data.* = shifted | around;

    cpu.r.s.f.z = if (data.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = carry;
}

fn rotate_r(cpu: *Cpu, data: *u8) void {
    const carry: u1 = if (data.* & 0b0000_0001 != 0) 1 else 0;
    const shifted = (data.* >> 1);
    const around = @as(u8, cpu.r.s.f.c);
    data.* = around << 7 | shifted;

    cpu.r.s.f.z = if (data.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = carry;
}

fn rotate_right_carry(cpu: *Cpu, data: *u8) mcycles {
    const carry: u8 = data.* & 0b1;
    const shifted: u8 = (data.* >> 1);
    data.* = carry << 7 | shifted;

    cpu.r.s.f.z = 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = if (carry & 0b1 != 0) 1 else 0;
    return 1;
}

fn add16(cpu: *Cpu, rega: *u16, regb: *u16) !mcycles {
    rega.*, const overflow = @addWithOverflow(rega.*, regb.*);
    const calcH: u16 = (rega.* & 0b111111111111) + (regb.* & 0b111111111111);
    cpu.r.s.f.z = if (rega.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if (calcH > 0b111111111111) 1 else 0;
    cpu.r.s.f.c = overflow;
    return 2;
}

fn add16_rr_to_HL(cpu: *Cpu, regb: u16) !mcycles {
    cpu.r.f.HL, const overflow = @addWithOverflow(cpu.r.f.HL, regb);
    const calcH: u16 = (cpu.r.f.HL & 0b111111111111) + (regb & 0b111111111111);
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if (calcH > 0b111111111111) 1 else 0;
    cpu.r.s.f.c = overflow;
    return 2;
}

pub fn add8(cpu: *Cpu, dest: *u8, src: u8) !mcycles {
    const halfadd: u8 = (dest.* & 0x0F) + (src & 0x0F);
    dest.*, cpu.r.s.f.c = @addWithOverflow(dest.*, src);
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if (halfadd > 0xF) 1 else 0; //TODO: find simpler way?
    return 1;
}

pub fn sub8(cpu: *Cpu, dest: *u8, src: u8) mcycles {
    const halfsub = (dest.* & 0x0F) -% (src & 0x0F);
    const original_val = dest.*;
    dest.* -%= src;
    cpu.r.s.f.z = if (dest.* == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if (halfsub > 0x0F) 1 else 0;
    cpu.r.s.f.c = if (original_val < src) 1 else 0;
    return 1;
}

pub fn or_r1_with_r2(cpu: *Cpu, r1: u8, r2: *u8) mcycles {
    r2.* |= r1;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = 0;
    return 1;
}

pub fn or_d8(cpu: *Cpu) !mcycles {
    return 1 + or_r1_with_r2(cpu, cpu.fetch(), &cpu.r.s.a);
}

pub fn load_d16_to_bc(cpu: *Cpu) !mcycles {
    cpu.r.f.BC = cpu.fetch16();
    return 3;
}

pub fn inc_b(cpu: *Cpu) !mcycles {
    return inc_8(cpu, &cpu.r.s.b);
}

pub fn dec_b(cpu: *Cpu) !mcycles {
    return dec_8(cpu, &cpu.r.s.b);
}

pub fn dec_bc(cpu: *Cpu) !mcycles {
    return dec_16(cpu, &cpu.r.f.BC);
}

pub fn inc_l(cpu: *Cpu) !mcycles {
    return inc_8(cpu, &cpu.r.s.l);
}

pub fn load_d8_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.fetch();
    return 2;
}

pub fn add_HL_BC(cpu: *Cpu) !mcycles {
    return add16_rr_to_HL(cpu, cpu.r.f.BC);
}

pub fn add_hl_hl(cpu: *Cpu) !mcycles {
    return add16_rr_to_HL(cpu, cpu.r.f.HL);
}

pub fn inc_c(cpu: *Cpu) !mcycles {
    return inc_8(cpu, &cpu.r.s.c);
}

pub fn dec_c(cpu: *Cpu) !mcycles {
    return dec_8(cpu, &cpu.r.s.c);
}

pub fn load_d8_to_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c = cpu.fetch();
    return 2;
}

pub fn dec_de(cpu: *Cpu) !mcycles {
    return dec_16(cpu, &cpu.r.f.DE);
}

pub fn load_d16_to_de(cpu: *Cpu) !mcycles {
    cpu.r.f.DE = cpu.fetch16();
    return 3;
}

pub fn store_a_to_indirectDE(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.DE, cpu.r.s.a);
    return 2;
}

pub fn inc_indirect_hl(cpu: *Cpu) !mcycles {
    var data = cpu.load(cpu.r.f.HL);
    const cycles = inc_8(cpu, &data);
    cpu.store(cpu.r.f.HL, data);
    return 2 + cycles;
}

pub fn dec_indirect_hl(cpu: *Cpu) !mcycles {
    var data = cpu.load(cpu.r.f.HL);
    const cycles = dec_8(cpu, &data);
    cpu.store(cpu.r.f.HL, data);
    return 2 + cycles;
}

pub fn inc_de(cpu: *Cpu) !mcycles {
    cpu.r.f.DE +%= 1;
    return 2;
}

pub fn inc_d(cpu: *Cpu) !mcycles {
    return inc_8(cpu, &cpu.r.s.d);
}

pub fn dec_d(cpu: *Cpu) !mcycles {
    return dec_8(cpu, &cpu.r.s.d);
}

pub fn load_d8_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.fetch();
    return 2;
}

pub fn rotate_left_carry_a(cpu: *Cpu) !mcycles {
    const carry: u1 = if (cpu.r.s.a & 0b1000_0000 != 0) 1 else 0;
    const shifted = (cpu.r.s.a << 1);
    cpu.r.s.a = shifted | carry;

    cpu.r.s.f.z = 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = carry;
    return 1;
}

pub fn rotate_right_carry_a(cpu: *Cpu) !mcycles {
    return rotate_right_carry(cpu, &cpu.r.s.a);
}

pub fn rotate_left_a(cpu: *Cpu) !mcycles {
    rotate_l(cpu, &cpu.r.s.a);
    cpu.r.s.f.z = 0;
    return 1;
}

pub fn load_d_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.d;
    return 1;
}

pub fn load_c_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.c;
    return 1;
}

pub fn load_h_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.h;
    return 1;
}

pub fn load_a_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.a;
    return 1;
}

pub fn load_d_to_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c = cpu.r.s.d;
    return 1;
}

pub fn load_l_to_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c = cpu.r.s.l;
    return 1;
}

pub fn load_a_to_c(cpu: *Cpu) !mcycles {
    cpu.r.s.c = cpu.r.s.a;
    return 1;
}

pub fn load_b_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.r.s.b;
    return 1;
}

pub fn load_c_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.r.s.c;
    return 1;
}

pub fn load_h_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.r.s.h;
    return 1;
}

pub fn load_a_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.r.s.a;
    return 1;
}

pub fn load_l_to_e(cpu: *Cpu) !mcycles {
    cpu.r.s.e = cpu.r.s.l;
    return 1;
}

pub fn load_a_to_e(cpu: *Cpu) !mcycles {
    cpu.r.s.e = cpu.r.s.a;
    return 1;
}

pub fn load_d_to_h(cpu: *Cpu) !mcycles {
    cpu.r.s.h = cpu.r.s.d;
    return 1;
}

pub fn load_a_to_h(cpu: *Cpu) !mcycles {
    cpu.r.s.h = cpu.r.s.a;
    return 1;
}

pub fn load_b_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.r.s.b;
    return 1;
}

pub fn load_e_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.r.s.e;
    return 1;
}

pub fn load_indirect_hl_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.load(cpu.r.f.HL);
    return 2;
}

pub fn load_a_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.r.s.a;
    return 1;
}

pub fn store_b_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.b);
    return 2;
}

pub fn store_c_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.c);
    return 2;
}

pub fn store_d_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.d);
    return 2;
}

pub fn store_e_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.e);
    return 2;
}

pub fn halt(cpu: *Cpu) !mcycles {
    cpu.halted = true;
    return 1;
}

pub fn store_a_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    return 2;
}

pub fn load_b_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.b;
    return 1;
}

pub fn load_c_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.c;
    return 1;
}

pub fn load_d_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.d;
    return 1;
}

pub fn load_e_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.e;
    return 1;
}

pub fn load_h_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.h;
    return 1;
}

pub fn load_l_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.l;
    return 1;
}

pub fn load_hl_indirect_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.load(cpu.r.f.HL);
    return 2;
}

pub fn load_indirect_hl_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.load(cpu.r.f.HL);
    return 2;
}

pub fn load_indirect_hl_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.load(cpu.r.f.HL);
    return 2;
}

pub fn load_indirect_hl_to_e(cpu: *Cpu) !mcycles {
    cpu.r.s.e = cpu.load(cpu.r.f.HL);
    return 2;
}

pub fn add_a_to_b(cpu: *Cpu) !mcycles {
    return add8(cpu, &cpu.r.s.a, cpu.r.s.b);
}

pub fn add_a_to_c(cpu: *Cpu) !mcycles {
    return add8(cpu, &cpu.r.s.a, cpu.r.s.c);
}

pub fn add_a_to_d(cpu: *Cpu) !mcycles {
    return add8(cpu, &cpu.r.s.a, cpu.r.s.d);
}

pub fn add_a_to_e(cpu: *Cpu) !mcycles {
    return add8(cpu, &cpu.r.s.a, cpu.r.s.e);
}

pub fn add_a_to_l(cpu: *Cpu) !mcycles {
    return add8(cpu, &cpu.r.s.a, cpu.r.s.l);
}

pub fn add_a_d8(cpu: *Cpu) !mcycles {
    return add8(cpu, &cpu.r.s.a, cpu.fetch());
}

pub fn add_a_to_hl_indirect(cpu: *Cpu) !mcycles {
    const val = cpu.load(cpu.r.f.HL);
    const halfadd = (cpu.r.s.a & 0x0F) + (val & 0x0F);
    cpu.r.s.a, cpu.r.s.f.c = @addWithOverflow(cpu.r.s.a, val);
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if (halfadd > 0xF) 1 else 0; //TODO: find simpler way?

    return 2;
}

pub fn add_a_to_a(cpu: *Cpu) !mcycles {
    return add8(cpu, &cpu.r.s.a, cpu.r.s.a);
}

pub fn add_b_cy_a_to_a(cpu: *Cpu) !mcycles {
    var val, const overflow1 = @addWithOverflow(cpu.r.s.a, cpu.r.s.b);
    val, const overflow2 = @addWithOverflow(val, cpu.r.s.f.c);
    const halfadd = (cpu.r.s.a & 0x0F) + (cpu.r.s.b & 0x0F) + cpu.r.s.f.c; //TODO: find simpler way?
    cpu.r.s.a = val;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if (halfadd > 0xF) 1 else 0;
    cpu.r.s.f.c = overflow1 | overflow2;
    return 1;
}

pub fn sub_d8(cpu: *Cpu) !mcycles {
    return 1 + sub8(cpu, &cpu.r.s.a, cpu.fetch());
}

pub fn subtract_l_from_a(cpu: *Cpu) !mcycles {
    return sub8(cpu, &cpu.r.s.a, cpu.r.s.l);
}

pub fn subtract_a_b_cf(cpu: *Cpu) !mcycles {
    var val, const overflow1 = @subWithOverflow(cpu.r.s.a, cpu.r.s.b);
    val, const overflow2 = @subWithOverflow(val, cpu.r.s.f.c);
    cpu.r.s.a = val;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((val & 0x0F) < (val)) 1 else 0;
    cpu.r.s.f.c = overflow1 | overflow2;
    return 1;
}

pub fn subtract_b_from_a(cpu: *Cpu) !mcycles {
    return sub8(cpu, &cpu.r.s.a, cpu.r.s.b);
}

pub fn subtract_d_from_a(cpu: *Cpu) !mcycles {
    return sub8(cpu, &cpu.r.s.a, cpu.r.s.d);
}

pub fn load_d16_to_sp(cpu: *Cpu) !mcycles {
    cpu.sp = cpu.fetch16();
    return 3;
}

pub fn store_a_to_indirectHL_dec(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    cpu.r.f.HL -= 1;
    return 2;
}

pub fn store_d8_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.fetch());
    return 3;
}

pub fn set_carry_flag(cpu: *Cpu) !mcycles {
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = 1;
    return 1;
}

pub fn load_indirectHL_dec_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.load(cpu.r.f.HL);
    cpu.r.f.HL -= 1;
    return 2;
}

pub fn inc_a(cpu: *Cpu) !mcycles {
    return inc_8(cpu, &cpu.r.s.a);
}

pub fn dec_a(cpu: *Cpu) !mcycles {
    return dec_8(cpu, &cpu.r.s.a);
}

pub fn load_d8_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = Cpu.fetch(cpu);
    return 2;
}

pub fn flip_carry_flag(cpu: *Cpu) !mcycles {
    cpu.r.s.f.c = ~cpu.r.s.f.c;
    return 1;
}

pub fn load_indirect16_to_a(cpu: *Cpu) !mcycles {
    const addr = Cpu.fetch16(cpu);
    cpu.r.s.a = cpu.load(addr);
    return 4;
}

pub fn load_a_to_indirect16(cpu: *Cpu) !mcycles {
    const addr = Cpu.fetch16(cpu);
    cpu.store(addr, cpu.r.s.a);
    return 4;
}

pub fn load_indirect8_to_a(cpu: *Cpu) !mcycles {
    const addr: u16 = 0xFF00 + @as(u16, Cpu.fetch(cpu));
    cpu.r.s.a = cpu.load(addr);
    return 3;
}

pub fn load_a_to_indirect8(cpu: *Cpu) !mcycles {
    const addr: u16 = 0xFF00 + @as(u16, Cpu.fetch(cpu));

    cpu.store(addr, cpu.r.s.a);
    return 3;
}

pub fn pop_to_HL(cpu: *Cpu) !mcycles {
    cpu.r.f.HL = cpu.pop16();
    return 3;
}

pub fn store_a_to_indirect_c(cpu: *Cpu) !mcycles {
    cpu.store(0xFF00 + @as(u16, cpu.r.s.c), cpu.r.s.a);
    return 2;
}

pub fn push_hl(cpu: *Cpu) !mcycles {
    cpu.push16(cpu.r.f.HL);
    return 4;
}

pub fn and_d8_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= cpu.fetch();
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
    cpu.r.s.f.c = 0;
    return 2;
}

pub fn jmp_hl(cpu: *Cpu) !mcycles {
    cpu.pc = cpu.r.f.HL;
    return 1;
}

pub fn add_u8_as_signed_to_u16(dest: u8, pc: u16) struct { u16, bool } {
    const signed_dest: i16 = @intCast(@as(i8, @bitCast(dest)));
    const pc_signed: i32 = @intCast(pc);
    const new_pc_singed: i32 = pc_signed + signed_dest;
    const overflow = new_pc_singed > 0xFFFF or new_pc_singed < 0;
    return .{ @intCast(new_pc_singed), overflow };
}

pub fn pop_bc(cpu: *Cpu) !mcycles {
    cpu.r.f.BC = cpu.pop16();
    return 3;
}

pub fn return_if_not_zero(cpu: *Cpu) !mcycles {
    if (cpu.r.s.f.z == 0) {
        return 1 + try return_from_call(cpu);
    }
    return 2;
}

pub fn jmp_if_not_zero(cpu: *Cpu) !mcycles {
    const dest = Cpu.fetch16(cpu);
    var timing: mcycles = 3;
    if (cpu.r.s.f.z == 0) {
        cpu.pc = dest;
        timing += 1;
    }
    return timing;
}

pub fn jmp(cpu: *Cpu) !mcycles {
    const dest = Cpu.fetch16(cpu);
    cpu.pc = dest;
    return 4;
}

pub fn push_bc(cpu: *Cpu) !mcycles {
    cpu.push16(cpu.r.f.BC);
    return 4;
}

pub fn return_from_call_condiional_on_z(cpu: *Cpu) !mcycles {
    if (cpu.r.s.f.z == 1) {
        return 1 + try return_from_call(cpu);
    }
    return 2;
}

pub fn return_from_call(cpu: *Cpu) !mcycles {
    cpu.pc = cpu.pop16();
    return 4;
}

pub fn jump_if_zero_a16(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch16();
    var timing: mcycles = 3;
    if (cpu.r.s.f.z == 1) {
        cpu.pc = dest;
        timing += 1;
    }
    return timing;
}

pub fn jmp_s8(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    cpu.pc, _ = add_u8_as_signed_to_u16(dest, cpu.pc);
    return 3;
}

pub fn jump_s8_if_carry(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    var timing: mcycles = 2;
    if (cpu.r.s.f.c == 1) {
        cpu.pc, _ = add_u8_as_signed_to_u16(dest, cpu.pc);
        timing += 1;
    }
    return timing;
}

pub fn jmp_absolute_if_carry(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch16();
    var timing: mcycles = 3;
    if (cpu.r.s.f.c == 1) {
        cpu.pc = dest;
        timing += 1;
    }
    return timing;
}

pub fn jmp_absolute_not_carry(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch16();
    var timing: mcycles = 3;
    if (cpu.r.s.f.c == 0) {
        cpu.pc = dest;
        timing += 1;
    }
    return timing;
}

pub fn add_de_to_hl(cpu: *Cpu) !mcycles {
    return add16_rr_to_HL(cpu, cpu.r.f.DE);
}

pub fn load_indirectDE_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.load(cpu.r.f.DE);
    return 2;
}

pub fn inc_e(cpu: *Cpu) !mcycles {
    return inc_8(cpu, &cpu.r.s.e);
}

pub fn dec_e(cpu: *Cpu) !mcycles {
    return dec_8(cpu, &cpu.r.s.e);
}

pub fn load_d8_to_e(cpu: *Cpu) !mcycles {
    cpu.r.s.e = cpu.fetch();
    return 2;
}

pub fn jmp_nz_s8(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    var timing: mcycles = 2;
    if (cpu.r.s.f.z == 0) {
        cpu.pc, _ = add_u8_as_signed_to_u16(dest, cpu.pc);
        timing += 1;
    }
    return timing;
}

pub fn load_d16_to_HL(cpu: *Cpu) !mcycles {
    cpu.r.f.HL = Cpu.fetch16(cpu);
    return 3;
}

pub fn store_a_to_IndirectHL_inc(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    cpu.r.f.HL += 1;
    return 2;
}

pub fn inc_HL(cpu: *Cpu) !mcycles {
    return inc_u16(cpu, &cpu.r.f.HL);
}

pub fn inc_H(cpu: *Cpu) !mcycles {
    return inc_8(cpu, &cpu.r.s.h);
}

pub fn load_d8_to_h(cpu: *Cpu) !mcycles {
    cpu.r.s.h = cpu.fetch();
    return 2;
}

pub fn jmp_if_zero(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    var timing: mcycles = 2;
    if (cpu.r.s.f.z == 1) {
        cpu.pc, _ = add_u8_as_signed_to_u16(dest, cpu.pc);
        timing += 1;
    }
    return timing;
}

pub fn load_HL_indirect_inc_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.load(cpu.r.f.HL);
    cpu.r.f.HL += 1;
    return 2;
}

pub fn load_bc_indirect_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.load(cpu.r.f.BC);
    return 2;
}

pub fn load_d8_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.fetch();
    return 2;
}

pub fn compl_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = ~cpu.r.s.a;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = 1;
    return 1;
}

pub fn jump_not_carry_s8(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    var timing: mcycles = 2;
    if (cpu.r.s.f.c == 0) {
        cpu.pc, _ = add_u8_as_signed_to_u16(dest, cpu.pc);
        timing += 1;
    }
    return timing;
}

pub fn call_if_zero(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch16();
    var timing: mcycles = 3;
    if (cpu.r.s.f.z == 1) {
        cpu.push16(cpu.pc);
        cpu.pc = dest;
        timing += 3;
    }
    return timing;
}

pub fn call16(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch16();
    cpu.push16(cpu.pc);
    cpu.pc = dest;
    return 6;
}

pub fn retun_if_no_carry(cpu: *Cpu) !mcycles {
    var timing: mcycles = 2;
    if (cpu.r.s.f.c == 0) {
        cpu.pc = cpu.pop16();
        timing += 3;
    }
    return timing;
}

pub fn pop_de(cpu: *Cpu) !mcycles {
    cpu.r.f.DE = cpu.pop16();
    return 3;
}

pub fn push_de(cpu: *Cpu) !mcycles {
    cpu.push16(cpu.r.f.DE);
    return 4;
}

pub fn return_if_carry(cpu: *Cpu) !mcycles {
    var timing: mcycles = 2;
    if (cpu.r.s.f.c == 1) {
        cpu.pc = cpu.pop16();
        timing += 3;
    }
    return timing;
}

pub fn return_enable_interupt(cpu: *Cpu) !mcycles {
    _ = try return_from_call(cpu);
    _ = try enable_interrupts(cpu);
    return 4;
}

pub fn compare_immediate8_ra(cpu: *Cpu) !mcycles {
    const immediate = Cpu.fetch(cpu);
    cpu.r.s.f.z = if (cpu.r.s.a == immediate) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) < (immediate & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (cpu.r.s.a < immediate) 1 else 0;
    return 2;
}

fn and_r_with_r(cpu: *Cpu, r1: u8, r2: *u8) mcycles {
    r2.* &= r1;
    cpu.r.s.f.z = if (r2.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
    cpu.r.s.f.c = 0;
    return 1;
}

pub fn and_b_with_a(cpu: *Cpu) !mcycles {
    return and_r_with_r(cpu, cpu.r.s.b, &cpu.r.s.a);
}

pub fn and_e_with_a(cpu: *Cpu) !mcycles {
    return and_r_with_r(cpu, cpu.r.s.e, &cpu.r.s.a);
}

pub fn and_indirect_hl_a(cpu: *Cpu) !mcycles {
    return 1 + and_r_with_r(cpu, cpu.load(cpu.r.f.HL), &cpu.r.s.a);
}

pub fn and_a_with_a(cpu: *Cpu) !mcycles {
    return and_r_with_r(cpu, cpu.r.s.a, &cpu.r.s.a);
}

fn xor_r1_with_r2(cpu: *Cpu, r1: u8, r2: *u8) mcycles {
    r2.* ^= r1;
    cpu.r.s.f.z = if (r2.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = 0;
    return 1;
}

pub fn xor_b_with_a(cpu: *Cpu) !mcycles {
    return xor_r1_with_r2(cpu, cpu.r.s.b, &cpu.r.s.a);
}

pub fn xor_a_with_a(cpu: *Cpu) !mcycles {
    return xor_r1_with_r2(cpu, cpu.r.s.a, &cpu.r.s.a);
}

pub fn xor_d8_to_a(cpu: *Cpu) !mcycles {
    return 1 + xor_r1_with_r2(cpu, cpu.fetch(), &cpu.r.s.a);
}

pub fn or_c_with_a(cpu: *Cpu) !mcycles {
    return or_r1_with_r2(cpu, cpu.r.s.c, &cpu.r.s.a);
}

pub fn or_d_with_a(cpu: *Cpu) !mcycles {
    return or_r1_with_r2(cpu, cpu.r.s.d, &cpu.r.s.a);
}

pub fn or_b_with_a(cpu: *Cpu) !mcycles {
    return or_r1_with_r2(cpu, cpu.r.s.b, &cpu.r.s.a);
}

pub fn or_e_with_a(cpu: *Cpu) !mcycles {
    return or_r1_with_r2(cpu, cpu.r.s.e, &cpu.r.s.a);
}

pub fn or_indirect_hl_with_a(cpu: *Cpu) !mcycles {
    const hl_content = cpu.load(cpu.r.f.HL);
    return 1 + or_r1_with_r2(cpu, hl_content, &cpu.r.s.a);
}

pub fn compare_b_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.f.z = if (cpu.r.s.a == cpu.r.s.b) 1 else 0;
    return 1;
}

pub fn compare_c_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.f.z = if (cpu.r.s.a == cpu.r.s.c) 1 else 0;
    return 1;
}

pub fn compare_indirectHL_to_a(cpu: *Cpu) !mcycles {
    const hl_content = cpu.load(cpu.r.f.HL);
    cpu.r.s.f.z = if (hl_content == cpu.r.s.a) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((hl_content & 0x0F) < (cpu.r.s.a & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (hl_content < cpu.r.s.a) 1 else 0;
    return 2;
}

pub fn push_af(cpu: *Cpu) !mcycles {
    cpu.push16(cpu.r.f.AF);
    return 4;
}

pub fn add_sp_s8_to_hl(cpu: *Cpu) !mcycles {
    const s8 = cpu.fetch();
    const hl = cpu.r.f.HL;
    const result, _ = add_u8_as_signed_to_u16(s8, cpu.sp);
    const hadd: u8 = @intCast((hl & 0x0F) + (s8 & 0x0F));
    const cadd: u16 = @intCast((hl & 0xFF) + (s8 & 0xFF));
    cpu.r.f.HL = result;
    cpu.r.s.f.c = if (cadd > 0xFF) 1 else 0;
    cpu.r.s.f.h = if (hadd > 0xF) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.z = 0;
    
    return 3;
}

pub fn load_hl_to_sp(cpu: *Cpu) !mcycles {
    cpu.sp = cpu.r.f.HL;
    return 2;
}

pub fn pop_af(cpu: *Cpu) !mcycles {
    cpu.r.f.AF = cpu.pop16();
    return 3;
}

pub fn disable_interrupts(cpu: *Cpu) !mcycles {
    cpu.interrupt.enabled = false;
    return 1;
}

pub fn enable_interrupts(cpu: *Cpu) !mcycles {
    //this needs to be delayed by 1 instruction
    cpu.interrupt.enabled = true;
    cpu.interrupt.enable_delay_instructons = 1;
    return 1;
}

fn copy_compl_rbitN_to_z(cpu: *Cpu, reg: u8, comptime N: u8) mcycles {
    cpu.r.s.f.z = if ((reg >> N) & 0b1 != 1) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
    return 2;
}

pub fn rotate_right_indirect_HL(cpu: *Cpu) !mcycles {
    var data = cpu.load(cpu.r.f.HL);
    rotate_r(cpu, &data);
    cpu.store(cpu.r.f.HL, data);
    return 4;
}

pub fn rotate_left_c(cpu: *Cpu) !mcycles {
    rotate_l(cpu, &cpu.r.s.c);
    return 2;
}

pub fn rotate_left_d(cpu: *Cpu) !mcycles {
    rotate_l(cpu, &cpu.r.s.d);
    return 2;
}

pub fn rotate_right_d(cpu: *Cpu) !mcycles {
    rotate_r(cpu, &cpu.r.s.d);
    return 2;
}

pub fn rotate_right_e(cpu: *Cpu) !mcycles {
    rotate_r(cpu, &cpu.r.s.e);
    return 2;
}

pub fn shift_register_left(cpu: *Cpu, reg: *u8) mcycles {
    const bit7 = reg.* & bitmasks[7];
    reg.* = reg.* << 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = if (bit7 != 0) 1 else 0;
    return 2;
}

pub fn shift_register_right_keep_bit_7(cpu: *Cpu, reg: *u8) mcycles {
    const bit0 = reg.* & 0b1;
    const bit7 = (reg.* & 0b10000000);
    reg.* = bit7 | reg.* >> 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = if (bit0 == 1) 1 else 0;
    return 2;
}

pub fn shift_left_a(cpu: *Cpu) !mcycles {
    return shift_register_left(cpu, &cpu.r.s.a);
}

pub fn shift_left_B(cpu: *Cpu) !mcycles {
    return shift_register_left(cpu, &cpu.r.s.b);
}

pub fn shift_left_e(cpu: *Cpu) !mcycles {
    return shift_register_left(cpu, &cpu.r.s.e);
}

pub fn shift_right_a(cpu: *Cpu) !mcycles {
    return shift_register_right_keep_bit_7(cpu, &cpu.r.s.a);
}

pub fn shift_right_d(cpu: *Cpu) !mcycles {
    return shift_register_right_keep_bit_7(cpu, &cpu.r.s.d);
}

fn swap(cpu: *Cpu, reg: *u8) mcycles {
    const a = reg.*;
    reg.* = (a & 0xF0) >> 4 | (a & 0x0F) << 4;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = 0;
    return 2;
}

pub fn swap_indirect_hl(cpu: *Cpu) !mcycles {
    var hl_content = cpu.load(cpu.r.f.HL);
    const cycles = swap(cpu, &hl_content);
    cpu.store(cpu.r.f.HL, hl_content);
    return 2 + cycles;
}

pub fn swap_a(cpu: *Cpu) !mcycles {
    return swap(cpu, &cpu.r.s.a);
}

pub fn copy_compl_dbit0_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.d, 0);
}

pub fn copy_compl_abit0_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.a, 0);
}

pub fn copy_compl_abit1_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.a, 1);
}

pub fn copy_compl_abit2_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.a, 2);
}

pub fn copy_compl_abit5_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.a, 5);
}

pub fn copy_compl_abit6_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.a, 6);
}

pub fn copy_compl_hbit7_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.h, 7);
}

pub fn copy_compl_abit7_to_z(cpu: *Cpu) !mcycles {
    return copy_compl_rbitN_to_z(cpu, cpu.r.s.a, 7);
}

pub fn copy_compl_indirect_hl_bit0_to_z(cpu: *Cpu) !mcycles {
    const value = cpu.load(cpu.r.f.HL);
    return 1 + copy_compl_rbitN_to_z(cpu, value, 0);
}

pub fn copy_compl_indirect_hl_bit1_to_z(cpu: *Cpu) !mcycles {
    const value = cpu.load(cpu.r.f.HL);
    return 1 + copy_compl_rbitN_to_z(cpu, value, 1);
}

pub fn copy_compl_indirect_hl_bit2_to_z(cpu: *Cpu) !mcycles {
    const value = cpu.load(cpu.r.f.HL);
    return 1 + copy_compl_rbitN_to_z(cpu, value, 2);
}

pub fn copy_compl_indirect_hl_bit3_to_z(cpu: *Cpu) !mcycles {
    const value = cpu.load(cpu.r.f.HL);
    return 1 + copy_compl_rbitN_to_z(cpu, value, 3);
}

pub fn copy_compl_indirect_hl_bit4_to_z(cpu: *Cpu) !mcycles {
    const value = cpu.load(cpu.r.f.HL);
    return 1 + copy_compl_rbitN_to_z(cpu, value, 4);
}

pub fn copy_compl_indirect_hl_bit6_to_z(cpu: *Cpu) !mcycles {
    const value = cpu.load(cpu.r.f.HL);
    return 1 + copy_compl_rbitN_to_z(cpu, value, 6);
}

const bitmasks = [_]u8{
    0x01,
    0x02,
    0x04,
    0x08,
    0x10,
    0x20,
    0x40,
    0x80,
};
const inv_bitmasks = [_]u8{
    ~bitmasks[0],
    ~bitmasks[1],
    ~bitmasks[2],
    ~bitmasks[3],
    ~bitmasks[4],
    ~bitmasks[5],
    ~bitmasks[6],
    ~bitmasks[7],
};

pub fn reset_a_bit0(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= inv_bitmasks[0];
    return 2;
}

pub fn reset_a_bit1(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= inv_bitmasks[1];
    return 2;
}

pub fn reset_a_bit2(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= inv_bitmasks[2];
    return 2;
}

pub fn reset_indirect_hl_bit0(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) & inv_bitmasks[0];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn reset_indirect_hl_bit2(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) & inv_bitmasks[2];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn reset_indirect_hl_bit3(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) & inv_bitmasks[3];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn reset_indirecthl_bit4(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) & inv_bitmasks[4];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn reset_indirecthl_bit5(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) & inv_bitmasks[5];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn reset_a_bit5(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= inv_bitmasks[5];
    return 2;
}

pub fn set_indirect_hl_bit2(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) | bitmasks[2];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn set_indirect_hl_bit3(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) | bitmasks[3];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn set_indirect_hl_bit6(cpu: *Cpu) !mcycles {
    const new_val = cpu.load(cpu.r.f.HL) | bitmasks[6];
    cpu.store(cpu.r.f.HL, new_val);
    return 4;
}

pub fn set_a_bit7(cpu: *Cpu) !mcycles {
    cpu.r.s.a |= bitmasks[7];
    return 2;
}
