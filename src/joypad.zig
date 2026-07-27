const JoypadSelectState = enum(u1) { Selected = 0, NotSelected = 1 };
const JoypadButtonFlagState = enum(u1) { Pressed = 0, NotPressed = 1 };

pub const Joypad = struct {
    bus: *Bus,
    registers: packed struct {
        P10_Right_or_A: JoypadButtonFlagState,
        P11_Left_or_B: JoypadButtonFlagState,
        P12_Up_or_Select: JoypadButtonFlagState,
        P13_Down_or_Start: JoypadButtonFlagState,
        P14_Select_Direction: JoypadSelectState,
        P15_Select_Button: JoypadSelectState,
        _: u2,
    },
    joypad_state: u8 = 0xFF,

    pub fn init(bus: *Bus) Joypad {
        return Joypad{
            .bus = bus,
            .registers = .{
                .P10_Right_or_A = JoypadButtonFlagState.NotPressed,
                .P11_Left_or_B = JoypadButtonFlagState.NotPressed,
                .P12_Up_or_Select = JoypadButtonFlagState.NotPressed,
                .P13_Down_or_Start = JoypadButtonFlagState.NotPressed,
                .P14_Select_Direction = JoypadSelectState.NotSelected,
                .P15_Select_Button = JoypadSelectState.NotSelected,
                ._ = 3,
            },
            .joypad_state = 0xFF,
        };
    }

    pub fn read(self: *Joypad) u8 {
        const joy_reg: u8 = @bitCast(self.registers);
        var result: u8 = 0xFF;

        if (self.registers.P14_Select_Direction == JoypadSelectState.Selected) {
            //Direction buttons

            const direction_buttons: u8 = self.joypad_state & 0b00001111;
            result = direction_buttons;
        }

        if (self.registers.P15_Select_Button == JoypadSelectState.Selected) {
            //Action buttons
            const action_buttons: u8 = (self.joypad_state >> 4) & 0b00001111;
            result &= action_buttons;
        }
        return (joy_reg & 0b00110000) | 0b11000000 | result; //No buttons selected, return all high
    }

    pub fn write(self: *Joypad, value: u8) void {
        //Only bit 5 and 4 are actually writable
        const currentVal: u8 = @bitCast(self.registers);
        const newVal: u8 = (currentVal & 0b11001111) | (value & 0b00110000);
        self.registers = @bitCast(newVal);
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
