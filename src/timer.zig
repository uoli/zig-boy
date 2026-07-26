pub const Timer = struct {
    bus: *Bus,
    modulo: u8,
    divider_register: u16,
    counter: u8,
    control: packed struct {
        clock_select: u2,
        timer_running: bool,
        _: u5,
    },

    pub fn init(bus: *Bus) Timer {
        return Timer{
            .bus = bus,
            .modulo = 0,
            .control = .{
                .clock_select = 0,
                .timer_running = false,
                ._ = undefined,
            },
            .divider_register = 0xffe6,
            .counter = 0,
        };
    }

    pub fn step(self: *Timer, cycles_elapsed: mcycles) void {
        //main clock = 4194304 hz in t-cycles

        //timer_clock_0 = 1 -> 4096hz   in t-cycles, 1024 times slower
        //timer_clock_1 = 1 -> 262144hz in t-cycles, 16   times slower
        //timer_clock_2 = 1 -> 65536hz  in t-cycles, 64   times slower
        //timer_clock_3 = 1 -> 16384hz  in t-cycles, 256  times slower

        const start_divider_val = self.divider_register;
        self.divider_register +%= @intCast(cycles_elapsed * 4);

        if (self.control.timer_running) {
            var counter_increase: u8 = 0;
            switch (self.control.clock_select) {
                0 => {
                    const timer4bit = (start_divider_val & 0b1111111111) + @as(u16, @intCast(cycles_elapsed * 4));
                    counter_increase = @intCast(timer4bit / 1024);
                },
                1 => {
                    const timer16bit = (start_divider_val & 0b1111) + @as(u16, @intCast(cycles_elapsed * 4));
                    counter_increase = @intCast(timer16bit / 16);
                },
                2 => {
                    const timer64bit = (start_divider_val & 0b111111) + @as(u16, @intCast(cycles_elapsed * 4));
                    counter_increase = @intCast(timer64bit / 64);
                },
                3 => {
                    const timer256bit = (start_divider_val & 0xFF) + @as(u16, @intCast(cycles_elapsed * 4));
                    counter_increase = @intCast(timer256bit / 256);
                },
            }
            self.counter, const overflow = @addWithOverflow(self.counter, counter_increase);
            if (overflow == 1) {
                self.counter = self.modulo;
                self.bus.raise_cpu_interrupt(Cpu.Interrup.Timer);
            }
        }
    }
};

const cpu_import = @import("cpu.zig");

const Bus = @import("bus.zig").Bus;
const Cpu = cpu_import.Cpu;
const mcycles = cpu_import.mcycles;
