const SpriteAttribute = struct {
    y: u8,
    x: u8,
    tile_index: u8,
    flags: packed struct {
        cpalette: u2, //(CGB only)
        tile_vram: u1, //VRAM Bank (CGB only)
        pallete: u1,
        xflip: u1,
        yflip: u1,
        priority: u1,
    },
};

const SpriteData = struct {
    pattern: [16]u8,
    fn get_pixel_color_index(self: SpriteData, x: u8, y: u8) u2 {
        const row_high = self.pattern[y * 2];
        const row_low = self.pattern[y * 2 + 1];

        const pixel_low = std.math.shr(u8, row_low, (7 - x)) & 0b1;
        const pixel_high = std.math.shr(u8, row_high, (7 - x)) & 0b1;
        return @intCast((pixel_high << 1) | pixel_low);
    }
};

pub const GpuStepResult = enum {
    Normal,
    FrameReady,
    Disabled,
};

pub const Gpu = struct {
    mode: u2,
    mode_clocks: usize,
    //scanline: u8,
    ram: []u8,
    bus: *Bus,
    dbg_frame_count: u32,

    ly: u8,
    lyc: u8,
    scroll_x: u8,
    scroll_y: u8,
    window_x: u8,
    window_y: u8,
    lcd_status: packed struct {
        mode: u2,
        coincidence: bool,
        mode0_hblank_interrupt: bool,
        mode_1_vblank_interrupt: bool,
        mode2_oam_interrupt: bool,
        coincidence_interrupt: bool,
        _: u1,
    },
    lcd_control: packed struct {
        bg_display: bool,
        obj_display_enable: bool,
        obj_size: bool,
        bg_tilemap_display_select: bool,
        bg_and_window_tile_select: bool,
        window_display_enable: bool,
        window_tilemap_display_select: bool,
        lcd_display_enable: bool,
    },
    background_palette: packed struct {
        color0: u2,
        color1: u2,
        color2: u2,
        color3: u2,
    },
    object_palette: [2]packed struct {
        _: u2,
        color1: u2,
        color2: u2,
        color3: u2,
    },

    visibleSprites: [10]SpriteAttribute,
    visibleSpritesCount: usize,

    framebuffer: [RESOLUTION_WIDTH * RESOLUTION_HEIGHT]u8,
    dbgTileFramebuffer: [16 * 8 * 24 * 8]u8,

    pub fn init(bus: *Bus, ram: []u8) Gpu {
        return Gpu{
            .ram = ram,
            .bus = bus,
            .dbg_frame_count = 0,
            .mode = 2,
            .mode_clocks = 0,
            .ly = 0,
            .lyc = 0,
            .visibleSprites = [_]SpriteAttribute{undefined} ** 10,
            .visibleSpritesCount = 0,
            .framebuffer = [_]u8{0} ** (RESOLUTION_WIDTH * RESOLUTION_HEIGHT),
            .dbgTileFramebuffer = [_]u8{0} ** (TILEDEBUG_WIDTH * TILEDEBUG_HEIGHT),
            .scroll_x = 0,
            .scroll_y = 0,
            .window_x = 0,
            .window_y = 0,
            .lcd_status = .{ .mode = 2, .coincidence = false, .mode0_hblank_interrupt = false, .mode_1_vblank_interrupt = false, .mode2_oam_interrupt = false, .coincidence_interrupt = false, ._ = undefined },
            //.lcd_control = @bitCast(@as(u8, 0x91)),
            .lcd_control = @bitCast(@as(u8, 0x0)),
            .background_palette = .{ .color0 = 0, .color1 = 0, .color2 = 0, .color3 = 0 },
            .object_palette = .{ .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 }, .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 } },
        };
    }

    const OAM_CLOCKS = 20;
    const RASTER_CLOKS = 43;
    const HBLANK_CLOKS = 51;
    const VBLANK_LINE_CLOCKS = 114;
    pub const RESOLUTION_WIDTH = 160;
    pub const RESOLUTION_HEIGHT = 144;
    pub const TILEDEBUG_WIDTH = 16 * 8;
    pub const TILEDEBUG_HEIGHT = 24 * 8;

    pub fn step(self: *Gpu, cpuClocks: mcycles) GpuStepResult {
        const zone = tracy.beginZone(@src(), .{ .name = "gpu step" });
        defer zone.end();
        if (!self.lcd_control.lcd_display_enable) return GpuStepResult.Disabled;
        self.mode_clocks += cpuClocks;
        switch (self.lcd_status.mode) {
            0 => { //H-Blank
                if (self.mode_clocks >= HBLANK_CLOKS) {
                    self.mode_clocks %= HBLANK_CLOKS;
                    self.ly += 1;

                    self.lcd_status.mode = if (self.ly < 144) 2 else 1;
                    check_lyc(self);
                    if (self.lcd_status.mode == 1) { //Start V-Blank
                        Logger.log("start vblank frame {d}\n", .{self.dbg_frame_count});
                        self.bus.raise_cpu_interrupt(Cpu.Interrup.VBlank);
                        self.dbg_frame_count += 1;
                        return GpuStepResult.FrameReady;
                    }
                }
            },
            1 => { //V-Blank
                if (self.mode_clocks >= VBLANK_LINE_CLOCKS) {
                    self.mode_clocks %= VBLANK_LINE_CLOCKS;
                    self.ly += 1;
                    if (self.ly == 154) {
                        self.lcd_status.mode = 2;
                        self.ly = 0;
                    }
                    check_lyc(self);
                }
            },
            2 => { //OAM
                if (self.mode_clocks >= OAM_CLOCKS) {
                    self.mode_clocks %= OAM_CLOCKS;
                    self.lcd_status.mode = 3;
                    self.findVisibleSprites();
                }
            },
            3 => { //raster
                if (self.mode_clocks >= RASTER_CLOKS) {
                    self.mode_clocks %= RASTER_CLOKS;
                    self.lcd_status.mode = 0;
                    self.drawscanline();
                }
            },
        }
        return GpuStepResult.Normal;
    }

    fn check_lyc(self: *Gpu) void {
        if (self.ly == self.lyc) {
            self.lcd_status.coincidence = true;
            if (self.lcd_status.coincidence_interrupt)
                self.bus.raise_cpu_interrupt(Cpu.Interrup.LCDStat);
        }
    }

    fn findVisibleSprites(self: *Gpu) void {
        const zone = tracy.beginZone(@src(), .{ .name = "gpu findVisibleSprites" });
        defer zone.end();
        const sprite_attrbiute_table_begin = 0xFE00;
        const sprite_attrbiute_table_end = 0xFE9F;
        const sprite_attrbiute_table = self.ram[sprite_attrbiute_table_begin..sprite_attrbiute_table_end];
        const sprite_aatribute = sliceCast(SpriteAttribute, sprite_attrbiute_table, 0, 40);

        //TODO: support 16 height as well
        const sprite_height = 8;

        self.visibleSpritesCount = 0;
        for (sprite_aatribute) |value| {
            if (value.y == 0 or value.y >= 160) continue; //hidden objects
            const sprite_data_y: i16 = @intCast(value.y);
            const sprite_top: i16 = @intCast(sprite_data_y - 16);
            const sprite_bottom = sprite_top + sprite_height;

            if (sprite_top > self.ly) continue;
            if (sprite_bottom <= self.ly) continue;

            self.visibleSprites[self.visibleSpritesCount] = value;
            self.visibleSpritesCount += 1;
            if (self.visibleSpritesCount == self.visibleSprites.len) break;
        }

        //sort
        for (0..self.visibleSpritesCount) |i| {
            for (0..self.visibleSpritesCount - i - 1) |j| {
                if (self.visibleSprites[j].x > self.visibleSprites[j + 1].x) {
                    const temp = self.visibleSprites[j];
                    self.visibleSprites[j] = self.visibleSprites[j + 1];
                    self.visibleSprites[j + 1] = temp;
                }
            }
        }
    }

    inline fn getBackgroundColor(self: *Gpu, color_index: u2) u8 {
        switch (color_index) {
            0 => return self.background_palette.color0,
            1 => return self.background_palette.color1,
            2 => return self.background_palette.color2,
            3 => return self.background_palette.color3,
        }
    }

    fn drawscanline(self: *Gpu) void {
        const zone = tracy.beginZone(@src(), .{ .name = "gpu drawscanline" });
        defer zone.end();

        const tile_width = 8;
        const tile_height = 8;
        const shades = [_]u8{ 255, 128, 63, 0 };

        const bg_tile_data_vram = if (self.lcd_control.bg_and_window_tile_select) self.ram[0x8000..0x8FFF] else self.ram[0x8800..0x97FF];
        const bg_tile_data = sliceCast(SpriteData, bg_tile_data_vram, 0, 0xFFF);

        //std.debug.assert(self.lcd_control.bg_and_window_tile_select == true);

        // for (0..RESOLUTION_WIDTH) |index| { //debugging, to remove
        //     const framebuffer_index: usize = (@as(usize, self.ly) * RESOLUTION_WIDTH) + index;
        //     self.framebuffer[framebuffer_index] = shades[3];
        // }

        //Draw BG
        //This code is horrible, I need to re-write it!
        const bg_map_1 = if (self.lcd_control.bg_tilemap_display_select == false) self.ram[0x9800..0x9BFF] else self.ram[0x9C00..0x9FFF];
        for (bg_map_1, 0..) |tile_index, i| { //TODO: no need to iterate through all 256 tiles, just get the ones that are visible
            const tile_x = i % 32;
            const tile_y = i / 32;
            const tile_index_mapped = if (self.lcd_control.bg_and_window_tile_select) tile_index else (tile_index +% 0x80);
            const tile = bg_tile_data[tile_index_mapped];

            const scrolled_y = (self.ly +% self.scroll_y);

            if (tile_y * tile_height > scrolled_y or tile_y * tile_height + tile_height <= scrolled_y) continue; //TODO: optimize so we dont have to check and continue here
            //if (tile_x * tile_width > RESOLUTION_WIDTH) continue; //TODO: this should probably take scroll x into account

            const y: u8 = scrolled_y % tile_height;
            for (0..tile_width) |x| {
                const bg_x = tile_x * 8 + x;
                const screen_x: i16 = @as(i16, @intCast(bg_x)) - @as(i16, @intCast(self.scroll_x));

                if (screen_x < 0 and self.scroll_x + RESOLUTION_WIDTH > 256) { //deal with wrapped camera
                    const wrapped = self.scroll_x + RESOLUTION_WIDTH % 256;
                    if (screen_x >= wrapped) continue;
                } else {
                    if (screen_x < 0 or screen_x >= RESOLUTION_WIDTH) continue;
                }

                const color_index = tile.get_pixel_color_index(@intCast(x), y);

                //const palette_table = if (sprite.flags.pallete == 0) self.ram[0xFF48] else self.ram[0xFF49];
                //const shade: u2 = @intCast((palette_table >> (color_index * 2)) & 0b11);
                //if (shade == 0) continue; //transparency
                const framebuffer_index: usize = (@as(usize, self.ly) * RESOLUTION_WIDTH) + @as(usize, @intCast(screen_x));
                // if (framebuffer_index >= self.framebuffer.len)
                //     break;
                self.framebuffer[framebuffer_index] = shades[self.getBackgroundColor(color_index)];
            }
        }

        //Draw Window
        if (self.lcd_control.window_display_enable == true and self.window_y <= self.ly) {
            const win_map = if (self.lcd_control.window_tilemap_display_select == false) self.ram[0x9800..0x9BFF] else self.ram[0x9C00..0x9FFF];
            for (win_map, 0..) |tile_index, i| {
                const tile_x = i % 32;
                const tile_y = i / 32;
                const tile_index_mapped = if (self.lcd_control.bg_and_window_tile_select) tile_index else (tile_index +% 0x80);
                const tile = bg_tile_data[tile_index_mapped];
                const view_y = self.ly;

                if (tile_y * tile_height > view_y or tile_y * tile_height + tile_height <= view_y) continue; //TODO: optimize so we dont have to check and continue here
                if (tile_x * tile_width > RESOLUTION_WIDTH) continue;

                const y: u8 = view_y % tile_height;

                for (0..tile_width) |x| {
                    const framebuffer_x = tile_x * 8 + x;
                    if (framebuffer_x < 0 or framebuffer_x >= RESOLUTION_WIDTH) break;

                    const color_index = tile.get_pixel_color_index(@intCast(x), y);
                    const framebuffer_index: usize = (@as(usize, self.ly) * RESOLUTION_WIDTH) + @as(usize, @intCast(framebuffer_x));
                    if (framebuffer_index >= self.framebuffer.len)
                        break;
                    self.framebuffer[framebuffer_index] = shades[self.getBackgroundColor(color_index)];
                }
            }
        }

        //draw sprites
        const tile_data_vram = self.ram[0x8000..0x8FFF];
        const tile_data = sliceCast(SpriteData, tile_data_vram, 0, 0xFFF);
        // if (self.dbg_frame_count == 1253 and self.visibleSpritesCount > 0) {
        //     @breakpoint();
        // }
        const sprite_width = 8;
        for (0..RESOLUTION_WIDTH) |index| {
            const i: u8 = @intCast(index);
            //const scrolled_x = self.scroll_x + i % 255;
            //const scrolled_y = self.scroll_y + self.ly % 255;
            const screen_x = i;
            const screen_y = self.ly;

            //for (0..self.visibleSpritesCount) |si| {
            for (0..self.visibleSpritesCount) |si| {
                const sprite = self.visibleSprites[si];
                //TODO: handle flip, priority and x-ordering
                const sprite_left_x: i16 = (@as(i16, @intCast(sprite.x)) - 8);
                const sprite_right = (sprite_left_x + sprite_width);
                if (sprite_left_x > screen_x or sprite_right <= screen_x) continue; //this is not fully correct

                const sprite_y: i16 = screen_y - (@as(i16, @intCast(sprite.y)) - 16);
                const sprite_x: u8 = @as(u8, @intCast(screen_x - sprite_left_x));

                const sprite_pattern = tile_data[sprite.tile_index];
                const color_index = sprite_pattern.get_pixel_color_index(sprite_x, @as(u8, @intCast(sprite_y)));
                if (color_index == 0) continue; //transparent
                const palette_table = if (sprite.flags.pallete == 0) self.object_palette[0] else self.object_palette[1];

                var shade: u2 = 0;
                switch (color_index) {
                    0 => {
                        unreachable;
                    },
                    1 => {
                        shade = palette_table.color1;
                    },
                    2 => {
                        shade = palette_table.color2;
                    },
                    3 => {
                        shade = palette_table.color3;
                    },
                }

                //if (shade == 0) continue; //transparency
                const framebuffer_index: usize = (@as(usize, screen_y) * RESOLUTION_WIDTH) + index;
                self.framebuffer[framebuffer_index] = shades[shade];
            }
        }
    }
    fn frameready(_: *Gpu) void {}

    pub fn snapshotTiles(self: *Gpu) []u8 {
        const sprite_width = 8;
        const sprite_height = 8;
        const tiles_colum = 16;
        const fb_width = tiles_colum * 8;

        const sprite_table = self.ram[0x8000..0x97FF];
        const sprite_data = sliceCast(SpriteData, sprite_table, 0, 0x0180);
        const shades = [_]u8{ 255, 128, 63, 0 };
        for (sprite_data, 0..) |sprite, si| {
            const fbGrid_x = si % tiles_colum;
            const fbGrid_y = si / tiles_colum;
            for (0..sprite_width) |x| {
                for (0..sprite_height) |y| {
                    const color_index: u2 = sprite.get_pixel_color_index(@intCast(x), @intCast(y));
                    const framebuffer_y: usize = fbGrid_y * sprite_height + y;
                    const framebuffer_x: usize = fbGrid_x * sprite_width + x;
                    const framebuffer_index: usize = (framebuffer_y * fb_width) + framebuffer_x;
                    self.dbgTileFramebuffer[framebuffer_index] = shades[color_index];
                }
            }
        }
        return &self.dbgTileFramebuffer;
    }
};

fn sliceCast(comptime T: type, buffer: []const u8, offset: usize, count: usize) []T {
    if (offset + count * @sizeOf(type) > buffer.len) unreachable;

    const ptr = @intFromPtr(buffer.ptr) + offset;
    const arrPtr: [*]T = @ptrFromInt(ptr);
    return arrPtr[0..count];
}

const std = @import("std");
const tracy = @import("tracy");
const cpu_import = @import("cpu.zig");
const bus_import = @import("bus.zig");
const Logger = @import("logger.zig");


const Cpu = cpu_import.Cpu;
const Bus = bus_import.Bus;
const mcycles = cpu_import.mcycles;
