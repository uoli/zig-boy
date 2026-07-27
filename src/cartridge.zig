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

const BankingMode = enum(u1) {
    ROM = 0,
    RAM = 1,
};

const RealTimeElapsed = packed struct {
    seconds: u8,
    minutes: u8,
    hours: u8,
    days: packed struct {
        low: u8,
        high: packed struct {
            day_bit_8: u1,
            unused: u5,
            halt: u1,
            day_counter_carry_flag: u1,
        },
    },
};

fn realtimeElapsedSince(start: std.time.Instant) RealTimeElapsed {
    const now = std.time.Instant.now() catch unreachable;
    const elapsed = now.since(start);
    const total_seconds: u64 = elapsed / 1_000_000_000;
    const seconds: u8 = @intCast(total_seconds % 60);
    const minutes: u8 = @intCast((total_seconds / 60) % 60);
    const hours: u8 = @intCast((total_seconds / 3600) % 24);
    const days: u16 = @intCast(total_seconds / 86400);

    return RealTimeElapsed{
        .seconds = seconds,
        .minutes = minutes,
        .hours = hours,
        .days = .{
            .low = @intCast(days & 0xFF),
            .high = .{
                .day_bit_8 = @intCast((days >> 8) & 0x01),
                .unused = 0,
                .halt = 0,
                .day_counter_carry_flag = if (days > 511) 1 else 0,
            },
        },
    };
}

pub const Cartridge = struct {
    rom: []const u8,
    cartridge_type: CartridgeType,
    rom_bank_number: u8,
    ram_enabled: bool = false,
    ram_bank_selected: u2 = 0,
    banking_mode: BankingMode = BankingMode.ROM,
    latch_clock_data: u2 = 0,
    external_ram: []u8 = undefined,
    rtc_start: std.time.Instant,
    latched_rtc: RealTimeElapsed = undefined,

    pub fn init(rom: []const u8, external_ram: []u8) Cartridge {
        const cartridge_type = CartridgeTypeMap[rom[0x147]];
        std.debug.assert(cartridge_type.? == CartridgeType.MBC3_RAM_BATTERY or cartridge_type.? == CartridgeType.ROM_ONLY);
        const rtc_start = std.time.Instant.now() catch unreachable;
        return Cartridge{
            .rom = rom,
            .cartridge_type = cartridge_type.?,
            .rom_bank_number = 1,
            .ram_enabled = false,
            .ram_bank_selected = 0,
            .external_ram = external_ram,
            .rtc_start = rtc_start,
        };
    }

    fn translate_address_to_external_ram(self: *const Cartridge, address: u16) usize {
        //TODO: can we use ram_bank_selected even if banking_mode is ROM? I think so, but need to check
        return @as(usize, address - 0xA000) + (@as(usize, self.ram_bank_selected) * 0x2000);
    }

    pub fn read(self: Cartridge, address: u16) u8 {
        switch (address) {
            0x0000...0x3FFF => {
                var bank_selected: u8 = 0;
                if (self.cartridge_type == CartridgeType.MBC1 and self.banking_mode == BankingMode.RAM) {
                    bank_selected += @as(u8, self.ram_bank_selected & 0b11) << 5;
                }
                const addr_delta = @as(usize, bank_selected) * 0x4000 + @as(usize, address);
                return self.rom[addr_delta];
            },
            0x4000...0x7FFF => {
                var addr_delta: usize = address - 0x4000;
                var bank_selected = self.rom_bank_number;
                if (self.cartridge_type == CartridgeType.MBC1) {
                    bank_selected += @as(u8, self.ram_bank_selected & 0b11) << 5;
                }
                addr_delta += @as(usize, bank_selected) * 0x4000;
                return self.rom[addr_delta];
            },
            0xA000...0xBFFF => {
                if (self.ram_enabled) {
                    // Write to external RAM if enabled
                    const ram_address = self.translate_address_to_external_ram(address);
                    return self.external_ram[ram_address];
                }
            },
            else => std.debug.panic("unhandled cartridge read address 0x{x}", .{address}),
        }
        return self.rom[address];
    }

    pub fn write(self: *Cartridge, address: u16, value: u8) void {
        switch (address) {
            0x0000...0x1FFF => {
                if (value & 0x0F == 0x0A) {
                    self.ram_enabled = true;
                } else {
                    self.ram_enabled = false;
                }
            },
            0x2000...0x3FFF => {
                self.rom_bank_number = if (value == 0) 1 else value;
            },
            0x4000...0x5FFF => {
                // handle bank switching for RAM or other purposes
                if (value > 0x03) {
                    std.debug.panic("Invalid RAM bank selection value: 0x{x}", .{value});
                }
                self.ram_bank_selected = @intCast(value & 0x03); // Only the lower 2 bits are used for RAM bank selection
            },
            0x6000...0x7FFF => {
                if (self.cartridge_type == CartridgeType.MBC1) {
                    self.banking_mode = if (value & 0x01 == 0) BankingMode.ROM else BankingMode.RAM;
                } else if (self.cartridge_type == CartridgeType.MBC3_TIMER_BATTERY or self.cartridge_type == CartridgeType.MBC3_TIMER_RAM_BATTERY) {
                    const newValue = value & 0x01;
                    if (self.latch_clock_data == 0x00 and newValue == 0x01) {
                        self.latch_rtc();
                    }
                    self.latch_clock_data = @intCast(newValue);
                } else if (self.cartridge_type == CartridgeType.MBC3_RAM_BATTERY) {
                    //NOOP
                } else {
                    std.debug.panic("Unhandled banking mode write for cartridge type: {d}", .{self.cartridge_type});
                }
            },
            0xA000...0xBFFF => {
                if (self.ram_enabled) {
                    // Write to external RAM if enabled
                    const ram_address = self.translate_address_to_external_ram(address);
                    self.external_ram[ram_address] = value;
                }
            },
            else => std.debug.panic("unhandled cartridge write address 0x{x}", .{address}),
        }
    }

    pub fn latch_rtc(self: *Cartridge) void {
        const elapsed = realtimeElapsedSince(self.rtc_start);
        self.latched_rtc = elapsed;
    }
};

const std = @import("std");
