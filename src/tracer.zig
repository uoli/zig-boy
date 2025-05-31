pub const Tracer = struct {
    enabled: bool,
    enable_trace: bool,

    pub fn init() Tracer {
        return Tracer{
            .enabled = false,
            .enable_trace = false,
        };
    }

    pub fn gpu_mode_trace(self: *Tracer, gpu: Gpu) void {
        if (!self.enabled) return;

        Logger.log("mode {d}\n", .{gpu.lcd_status.mode});
    }

    pub fn gpu_ly_trace(self: *Tracer, gpu: Gpu) void {
        if (!self.enabled) return;

        Logger.log("status.ly {d}\n", .{gpu.ly});
    }

    pub fn trace(self: *Tracer, cpu: Cpu) void {
        if (!self.enabled) return;

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
        if (contains(u16, &watched_pcs, cpu.pc) == true)
            self.enable_trace = true;

        if (self.enable_trace)
            Tracer.print_trace(cpu);
    }

    fn print_trace(cpu: Cpu) void {
        const zone = tracy.beginZone(@src(), .{ .name = "cpu print_trace" });
        defer zone.end();
        var tmp_ip = cpu.pc;
        var opcode = cpu.load(tmp_ip);
        tmp_ip += 1;
        const is_extopcode = opcode == 0xCB;
        if (is_extopcode) {
            opcode = cpu.load(tmp_ip);
            tmp_ip += 1;
        }
        const opInfo = if (is_extopcode)
            cpu.extended_opcodetable[opcode]
        else
            cpu.opcodetable[opcode];
        const arg = opInfo.arg;
        var args_str: [8:0]u8 = undefined;
        @memset(args_str[0..], ' ');

        switch (arg) {
            .U8 => {
                _ = std.fmt.bufPrint(&args_str, " 0x{x:02}", .{cpu.load(tmp_ip)}) catch unreachable;
                tmp_ip += 1;
            },
            .U16 => {
                _ = std.fmt.bufPrint(&args_str, " 0x{x:04}", .{cpu.load16(tmp_ip)}) catch unreachable;
                tmp_ip += 2;
            },
            .None => {},
        }
        Logger.log("[CPU] 0x{x:04} 0x{x:02} {s: <12}{s} AF:0x{x:04} BC:0x{x:04} DE:0x{x:04} HL:0x{x:04} SP:0x{x:04} {s} {d}\n", .{ cpu.pc, opInfo.code, opInfo.name, args_str, cpu.r.f.AF, cpu.r.f.BC, cpu.r.f.DE, cpu.r.f.HL, cpu.sp, cpu.r.debug_flag_str(), cpu.cycles_counter });
    }
};

fn contains(comptime T: type, haystack: []const T, needle: T) bool {
    for (haystack) |item| {
        if (item == needle) {
            return true;
        }
    }
    return false;
}

const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Gpu = @import("gpu.zig").Gpu;
const tracy = @import("tracy");
const Logger = @import("logger.zig");
