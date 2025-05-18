pub const Bus = struct {
    ram: []u8,
    cartridge: *Cartridge,
    gpu: *Gpu = undefined,
    cpu: *Cpu = undefined,

    pub fn init(ram: []u8, cartridge: *Cartridge) Bus {
        return Bus{
            .ram = ram,
            .cartridge = cartridge,
        };
    }

    pub fn connectGpu(self: *Bus, gpu: *Gpu) void {
        self.gpu = gpu;
    }

    pub fn connectCpu(self: *Bus, cpu: *Cpu) void {
        self.cpu = cpu;
    }

    pub fn raise_cpu_interrupt(self: *Bus, interrupt: Cpu.Interrup) void {
        self.cpu.raise_interrupt(interrupt);
    }

    pub fn read(self: Bus, address: u16) u8 {
        return switch (address) {
            0...0x7FFF => {
                return self.cartridge.read(address);
            },
            0x8000...0x9FFF => { //vram
                //TODO: do we need to split ram from vram?
                //if (address >= 0x8000 and address <= 0x97FF and self.cpu.disable_boot_rom == 1 and value != 0) {
                //    @breakpoint();
                //}
                return self.ram[address];
            },
            0xC000...0xCFFF => { //wram bank 0
                //TODO: do we need to split ram from wram?
                return self.ram[address];
            },
            0xD000...0xDFFF => { //wram bank 1
                //TODO: do we need to split ram from wram?
                return self.ram[address];
            },
            0xFF40 => {
                return @bitCast(self.gpu.lcd_control);
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
            0xFF48 => {
                return @bitCast(self.gpu.object_palette[0]);
            },
            0xFF49 => {
                return @bitCast(self.gpu.object_palette[1]);
            },
            0xFF80...0xFFFE => { // HRAM
                return self.ram[address];
            },
            else => {
                std.debug.panic("unhandled read address 0x{x}", .{address});
            },
        };
    }

    pub fn write(self: Bus, address: u16, value: u8) void {
        // if (address == 0xc056 and self.cpu.disable_boot_rom == 1 and value != 0) {
        //     @breakpoint();
        // }
        switch (address) {
            0...0x7FFF => {
                self.cartridge.write(address, value);
            },
            0x8000...0x9FFF => { //vram
                //TODO: do we need to split ram from vram?

                self.ram[address] = value;
            },
            0xC000...0xCFFF => { //wram bank 0
                //TODO: do we need to split ram from wram?
                self.ram[address] = value;
            },
            0xD000...0xDFFF => { //wram bank 1
                //TODO: do we need to split ram from wram?
                self.ram[address] = value;
            },
            0xFE00...0xFE9F => { //OAM
                //shouldn't be accessed during mode 2 or 3
                //std.debug.assert(self.gpu.mode != 2 and self.gpu.mode != 3);
                self.ram[address] = value;
            },
            0xFF30...0xFF3F => { //Wave Pattern RAM
                self.ram[address] = value;
            },
            0xFF40 => {
                const intialStatus = self.gpu.lcd_control.lcd_display_enable;
                self.gpu.lcd_control = @bitCast(value);
                if (intialStatus != self.gpu.lcd_control.lcd_display_enable and self.gpu.lcd_control.lcd_display_enable) {
                    self.gpu.ly = 0;
                    self.gpu.mode = 0;
                    self.gpu.mode_clocks = 0;
                }
            },
            0xFF41 => {
                self.gpu.lcd_status = @bitCast(value);
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
            0xFEA0...0xFEFF => { //Not usable
                std.debug.assert(false);
            },
            0xFF80...0xFFFE => { // HRAM
                self.ram[address] = value;
            },
            else => {
                std.debug.panic("unhandled write address 0x{x}", .{address});
            },
        }
    }
};

const std = @import("std");
const tracy = @import("tracy");
const cartridge_import = @import("cartridge.zig");
const cpu_import = @import("cpu.zig");
const gpu_import = @import("gpu.zig");

const Cpu = cpu_import.Cpu;
const Gpu = gpu_import.Gpu;
const Cartridge = cartridge_import.Cartridge;
