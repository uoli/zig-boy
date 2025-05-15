const main = @import("main.zig");
const Cpu = main.Cpu;
const mcycles = main.mcycles;
const opFunc = main.opFunc;

pub fn nop(_: *Cpu) !mcycles {
    return 1;
}

pub fn NotImplemented(_: *Cpu) !mcycles {
    return error.NotImplemented;
}

fn dec_8(cpu: *Cpu, reg: *u8) !mcycles {
    reg.* -%= 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.b & 0b1000_0000) == 1) 1 else 0;
    return 1;
}

fn dec_16(cpu: *Cpu, reg: *u16) !mcycles {
    reg.* -%= 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((reg.* & 0x0f) == 0x0f) 1 else 0;
    return 1;
}

fn inc_8(cpu: *Cpu, reg: *u8) !mcycles {
    reg.* +%= 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((reg.* & 0xFF) == 0) 1 else 0; //verify this
    return 1;
}

fn inc_u16(cpu: *Cpu, reg: *u16) !mcycles {
    reg.* +%= 1;
    cpu.r.s.f.z = if (reg.* == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((reg.* & 0xFF) == 0) 1 else 0; //verify this
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

pub fn or_r1_with_r2(cpu: *Cpu, r1: *u8, r2: *u8) !mcycles {
    r2.* |= r1.*;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = 0;
    return 1;
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

pub fn load_d8_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.fetch();
    return 2;
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

pub fn inc_de(cpu: *Cpu) !mcycles {
    cpu.r.f.DE +%= 1;
    return 2;
}

pub fn dec_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d -%= 1;
    return 1;
}

pub fn load_d8_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.d = cpu.fetch();
    return 2;
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

pub fn load_a_to_b(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.a;
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

pub fn load_a_to_h(cpu: *Cpu) !mcycles {
    cpu.r.s.h = cpu.r.s.a;
    return 1;
}

pub fn load_e_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.r.s.e;
    return 1;
}

pub fn load_a_to_l(cpu: *Cpu) !mcycles {
    cpu.r.s.l = cpu.r.s.a;
    return 1;
}

pub fn store_c_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.c);
    return 2;
}

pub fn store_a_to_indirectHL(cpu: *Cpu) !mcycles {
    cpu.store(cpu.r.f.HL, cpu.r.s.a);
    return 2;
}

pub fn load_b_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.r.s.b;
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

pub fn add_a_to_e(cpu: *Cpu) !mcycles {
    cpu.r.s.a, cpu.r.s.f.c = @addWithOverflow(cpu.r.s.a, cpu.r.s.e);
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) + (cpu.r.s.e & 0x0F) > 0xF) 1 else 0; //TODO: find simpler way?
    return 1;
}

pub fn add_a_to_hl_indirect(cpu: *Cpu) !mcycles {
    const val = cpu.load(cpu.r.f.HL);
    cpu.r.s.a, cpu.r.s.f.c = @addWithOverflow(cpu.r.s.a, val);
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) + (val & 0x0F) > 0xF) 1 else 0; //TODO: find simpler way?

    return 2;
}

pub fn add_a_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a, cpu.r.s.f.c = @addWithOverflow(cpu.r.s.a, cpu.r.s.a);
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) + (cpu.r.s.a & 0x0F) > 0xF) 1 else 0; //TODO: find simpler way?
    return 1;
}

pub fn subtract_l_from_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a -= cpu.r.s.l;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) < (cpu.r.s.l & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (cpu.r.s.a < cpu.r.s.l) 1 else 0;
    return 1;
}

pub fn subtract_b_from_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a -= cpu.r.s.b;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 1;
    cpu.r.s.f.h = if ((cpu.r.s.a & 0x0F) < (cpu.r.s.b & 0x0F)) 1 else 0;
    cpu.r.s.f.c = if (cpu.r.s.a < cpu.r.s.b) 1 else 0;
    return 1;
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

pub fn dec_a(cpu: *Cpu) !mcycles {
    return dec_8(cpu, &cpu.r.s.a);
}

pub fn load_d8_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = Cpu.fetch(cpu);
    return 2;
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

pub fn add_u8_as_signed_to_u16(dest: u8, pc: u16) u16 {
    const signed_dest: i16 = @intCast(@as(i8, @bitCast(dest)));
    const pc_signed: i16 = @intCast(pc);
    const new_pc_singed: i16 = pc_signed + signed_dest;
    return @intCast(new_pc_singed);
}

pub fn pop_bc(cpu: *Cpu) !mcycles {
    cpu.r.f.BC = cpu.pop16();
    return 3;
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
        return return_from_call(cpu);
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
    cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
    return 3;
}

pub fn add_de_to_hl(cpu: *Cpu) !mcycles {
    cpu.r.f.HL, cpu.r.s.f.c = @addWithOverflow(cpu.r.f.HL, cpu.r.f.DE);
    cpu.r.s.f.z = if (cpu.r.f.HL == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = if ((cpu.r.f.HL & 0x0F) + (cpu.r.f.DE & 0x0F) > 0x0F) 1 else 0;
    return 1;
}

pub fn load_indirectDE_to_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a = cpu.load(cpu.r.f.DE);
    return 2;
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
        cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
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
        cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
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

pub fn jump_not_carry_s8(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch();
    var timing: mcycles = 2;
    if (cpu.r.s.f.c == 0) {
        cpu.pc = add_u8_as_signed_to_u16(dest, cpu.pc);
        timing += 1;
    }
    return timing;
}

pub fn call16(cpu: *Cpu) !mcycles {
    const dest = cpu.fetch16();
    cpu.push16(cpu.pc);
    cpu.pc = dest;
    return 6;
}

pub fn pop_de(cpu: *Cpu) !mcycles {
    cpu.r.f.DE = cpu.pop16();
    return 3;
}

pub fn push_de(cpu: *Cpu) !mcycles {
    cpu.push16(cpu.r.f.DE);
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

pub fn and_a_with_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= cpu.r.s.a;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
    cpu.r.s.f.c = 0;
    return 1;
}

pub fn xor_a_with_a(cpu: *Cpu) !mcycles {
    cpu.r.s.a ^= cpu.r.s.a;
    cpu.r.s.f.z = if (cpu.r.s.a == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = 0;
    return 1;
}

pub fn or_c_with_a(cpu: *Cpu) !mcycles {
    return or_r1_with_r2(cpu, &cpu.r.s.c, &cpu.r.s.a);
}

pub fn or_e_with_a(cpu: *Cpu) !mcycles {
    return or_r1_with_r2(cpu, &cpu.r.s.e, &cpu.r.s.a);
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

pub fn disable_interrupts(cpu: *Cpu) !mcycles {
    cpu.interrupt.enabled = false;
    return 1;
}

pub fn enable_interrupts(cpu: *Cpu) !mcycles {
    cpu.interrupt.enabled = true;
    return 1;
}

pub fn rotate_left_c(cpu: *Cpu) !mcycles {
    rotate_l(cpu, &cpu.r.s.c);
    return 2;
}

pub fn rotate_right_d(cpu: *Cpu) !mcycles {
    rotate_r(cpu, &cpu.r.s.d);
    return 2;
}

pub fn shift_left_B(cpu: *Cpu) !mcycles {
    cpu.r.s.b = cpu.r.s.b << 1;
    cpu.r.s.f.z = if (cpu.r.s.b == 0) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 0;
    cpu.r.s.f.c = if ((cpu.r.s.b >> 7) == 1) 1 else 0;
    return 2;
}

pub fn copy_compl_bit0_to_d(cpu: *Cpu) !mcycles {
    cpu.r.s.f.z = if ((cpu.r.s.b >> 0) & 0b1 != 1) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
    return 2;
}

pub fn copy_compl_bit7_to_z(cpu: *Cpu) !mcycles {
    cpu.r.s.f.z = if ((cpu.r.s.h >> 7) != 1) 1 else 0;
    cpu.r.s.f.n = 0;
    cpu.r.s.f.h = 1;
    return 2;
}

pub fn reset_a_bit0(cpu: *Cpu) !mcycles {
    cpu.r.s.a &= 0xFE;
    return 2;
}
