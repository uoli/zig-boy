const CartridgeType = enum(u8) {
    ROM_ONLY,
    MBC1,
    MBC1_RAM,
    MBC1_RAM_BATTERY,
    //??
    MBC2,
    MBC2_BATTERY,
    //??
    ROM_RAM,
    ROM_RAM_BATTERY,
    //??
    MM01,
    MM01_RAM,
    MM01_RAM_BATTERY,
    //??
    MBC3_TIMER_BATTERY,
    MBC3_TIMER_RAM_BATTERY,
    MBC3,
    MBC3_RAM,
    MBC3_RAM_BATTERY,
    //??
    MBC4,
    MBC4_RAM,
    MBC4_RAM_BATTERY,
    //??
    MBC5,
    MBC5_RAM,
    MBC5_RAM_BATTERY,
    MBC5_RUMBLE,
    MBC5_RUMBLE_RAM,
    MBC5_RUMBLE_RAM_BATTERY,
    _,
};

const CartridgeTypeMap = [_]?CartridgeType{
    CartridgeType.ROM_ONLY,
    CartridgeType.MBC1,
    CartridgeType.MBC1_RAM,
    CartridgeType.MBC1_RAM_BATTERY,
    null,
    CartridgeType.MBC2,
    CartridgeType.MBC2_BATTERY,
    null,
    CartridgeType.ROM_RAM,
    CartridgeType.ROM_RAM_BATTERY,
    null,
    CartridgeType.MM01,
    CartridgeType.MM01_RAM,
    CartridgeType.MM01_RAM_BATTERY,
    null,
    CartridgeType.MBC3_TIMER_BATTERY,
    CartridgeType.MBC3_TIMER_RAM_BATTERY,
    CartridgeType.MBC3,
    CartridgeType.MBC3_RAM,
    CartridgeType.MBC3_RAM_BATTERY,
    null,
    CartridgeType.MBC4,
    CartridgeType.MBC4_RAM,
    CartridgeType.MBC4_RAM_BATTERY,
    null,
    CartridgeType.MBC5,
    CartridgeType.MBC5_RAM,
    CartridgeType.MBC5_RAM_BATTERY,
    CartridgeType.MBC5_RUMBLE,
    CartridgeType.MBC5_RUMBLE_RAM,
    CartridgeType.MBC5_RUMBLE_RAM_BATTERY,
};

pub const Cartridge = struct {
    rom: []const u8,
    cartridge_type: CartridgeType,
    bank_selected: u8,
    pub fn init(rom: []const u8) Cartridge {
        const cartridge_type = CartridgeTypeMap[rom[0x147]];
        std.debug.assert(cartridge_type.? == CartridgeType.MBC3_RAM_BATTERY or cartridge_type.? == CartridgeType.ROM_ONLY);
        return Cartridge{
            .rom = rom,
            .cartridge_type = cartridge_type.?,
            .bank_selected = 1,
        };
    }

    pub fn read(self: Cartridge, address: u16) u8 {
        switch (address) {
            0x0000...0x3FFF => return self.rom[address],
            0x4000...0x7FFF => {
                var addr_delta: usize = address - 0x4000;
                addr_delta += @as(usize, self.bank_selected) * 0x4000;
                return self.rom[addr_delta];
            },
            else => std.debug.panic("unhandled cartridge read address 0x{x}", .{address}),
        }
        return self.rom[address];
    }

    pub fn write(self: *Cartridge, address: u16, value: u8) void {
        switch (address) {
            0x2000...0x3FFF => {
                self.bank_selected = if (value == 0) 1 else value;
            },
            else => std.debug.panic("unhandled cartridge write address 0x{x}", .{address}),
        }
    }
};

const std = @import("std");
