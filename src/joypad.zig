pub const Joypad = struct {
    bus: *Bus,
    joypad_registers: u8 = 0xFF,
    joypad_state: u8 = 0xFF,

    pub fn init(bus: *Bus) Joypad {
        return Joypad{
            .bus = bus,
            .joypad_registers = 0xFF,
            .joypad_state = 0xFF,
        };
    }

    pub fn read(self: *Joypad) u8 {
        if (self.joypad_registers & 0b00100000 == 0) {
            //Direction buttons
            const direction_buttons: u8 = self.joypad_state & 0b00001111;
            return (self.joypad_registers & 0b11001111) | direction_buttons;
        } else if (self.joypad_registers & 0b00010000 == 0) {
            //Action buttons
            const action_buttons: u8 = (self.joypad_state >> 4) & 0b00001111;
            return (self.joypad_registers & 0b11001111) | action_buttons;
        }
        return self.joypad_registers & 0b11001111;
    }

    pub fn write(self: *Joypad, value: u8) void {
        //Only bit 5 and 4 are actually writable
        const currentVal: u8 = @bitCast(self.joypad_registers);
        const newVal: u8 = (currentVal & 0b11001111) | (value & 0b00110000);
        self.joypad_registers = @bitCast(newVal);
    }

    pub fn Press(self: *Joypad, button: Button) void {
        self.joypad_state &= ~@intFromEnum(button);
        self.bus.raise_cpu_interrupt(Cpu.Interrup.Joypad);
    }

    pub fn Release(self: *Joypad, button: Button) void {
        self.joypad_state |= @intFromEnum(button);
        //self.bus.raise_cpu_interrupt(Cpu.Interrup.Joypad);
    }

    pub const Button = enum(u8) {
        Right = 0b00000001,
        Left = 0b00000010,
        Up = 0b00000100,
        Down = 0b00001000,
        A = 0b00010000,
        B = 0b00100000,
        Select = 0b01000000,
        Start = 0b10000000,
    };
};

const Bus = @import("bus.zig").Bus;
const Cpu = @import("cpu.zig").Cpu;
