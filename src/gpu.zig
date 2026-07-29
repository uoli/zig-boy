const SpriteAttribute = packed struct {
    y: u8,
    x: u8,
    tile_index: u8,
    flags: packed struct {
        cpalette: u3, //(CGB only)
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
        const row_high = self.pattern[y * 2 + 1];
        const row_low = self.pattern[y * 2];

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
    ram: []u8,
    bus: *Bus,
    tracer: *Tracer,
    framebuffer: [RESOLUTION_WIDTH * RESOLUTION_HEIGHT]u8,
    dbgTileFramebuffer: [16 * 8 * 24 * 8]u8,
    state: State,

    pub const State = struct {
        dbg_frame_count: u32,
        mode_clocks: usize,
        ly: u8,
        lyc: u8,
        scroll_x: u8,
        scroll_y: u8,
        window_x: u8,
        window_y: u8,
        wly: u8,
        initializing_extra_steps: u8,
        lcd_display_initialization_pending: bool,
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
        dma: struct {
            requested: bool,
            source: u16,
            cycles_remaining: u8,
        },

        visibleSprites: [10]SpriteAttribute,
        visibleSpritesCount: usize,
        frame_ready: bool,
        stat_line: bool,
    };

    pub fn init(bus: *Bus, ram: []u8, tracer: *Tracer) Gpu {
        return Gpu{
            .ram = ram,
            .bus = bus,
            .tracer = tracer,
            .framebuffer = [_]u8{0} ** (RESOLUTION_WIDTH * RESOLUTION_HEIGHT),
            .dbgTileFramebuffer = [_]u8{0} ** (TILEDEBUG_WIDTH * TILEDEBUG_HEIGHT),

            .state = State{
                .dbg_frame_count = 0,
                .mode_clocks = 0,
                .ly = 0,
                .lyc = 0,
                .visibleSprites = [_]SpriteAttribute{undefined} ** 10,
                .visibleSpritesCount = 0,
                .frame_ready = false,
                .scroll_x = 0,
                .scroll_y = 0,
                .window_x = 0,
                .window_y = 0,
                .wly = 0,
                .lcd_status = .{ .mode = 2, .coincidence = false, .mode0_hblank_interrupt = false, .mode_1_vblank_interrupt = false, .mode2_oam_interrupt = false, .coincidence_interrupt = false, ._ = undefined },
                .initializing_extra_steps = 0,
                .lcd_display_initialization_pending = true,
                //.lcd_control = @bitCast(@as(u8, 0x91)),
                .lcd_control = @bitCast(@as(u8, 0x0)),
                .background_palette = .{ .color0 = 0, .color1 = 0, .color2 = 0, .color3 = 0 },
                .object_palette = .{ .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 }, .{ ._ = 0, .color1 = 0, .color2 = 0, .color3 = 0 } },
                .dma = .{
                    .requested = false,
                    .source = 0x00,
                    .cycles_remaining = 0,
                },
                .stat_line = false,
            },
        };
    }

    pub fn set_lyc(self: *Gpu, value: u8) void {
        self.state.lyc = value;
        self.check_lyc();
    }

    pub fn set_lcdc(self: *Gpu, value: u8) void {
        const intialStatus = self.state.lcd_control.lcd_display_enable;
        self.state.lcd_control = @bitCast(value);
        if (intialStatus != self.state.lcd_control.lcd_display_enable) {
            self.state.lcd_display_initialization_pending = true;
            self.state.initializing_extra_steps = 4;
            self.state.mode_clocks = 0;
            self.state.wly = 0;
            Logger.log("lcdc enable={} ticks {d}\n", .{ self.state.lcd_control.lcd_display_enable, self.bus.cpu.state.ticks_emitted });
        }
    }

    pub fn set_lcdc_Status(self: *Gpu, value: u8) void {
        const current: u8 = @bitCast(self.state.lcd_status);
        self.state.lcd_status = @bitCast((current & 0b1000_0111) | (value & 0b0111_1000));
        self.update_stat_line();
    }

    pub fn request_dma_transfer(self: *Gpu, addr_base_req: u8) void {
        self.state.dma.requested = true;
        var addr_base = addr_base_req;
        if (addr_base == 0xfe) addr_base = 0xde;
        if (addr_base == 0xff) addr_base = 0xdf;
        self.state.dma.source = addr_base;
        self.state.dma.source = self.state.dma.source << 8;
        self.state.dma.cycles_remaining = 160;
    }

    fn handle_dma(self: *Gpu, cycles_elapsed: mcycles) void {
        if (self.state.dma.requested == false) return;
        for (0x00..0x9F + 1) |value| {
            const value16: u16 = @intCast(value);
            const source: u16 = self.state.dma.source + value16;
            const dest: u16 = 0xFE00 + value16;
            self.bus.write(dest, self.bus.read(source));
        }
        if (self.state.dma.cycles_remaining < cycles_elapsed) {
            self.state.dma.cycles_remaining = 0;
            self.state.dma.requested = false;
        } else {
            self.state.dma.cycles_remaining -= @intCast(cycles_elapsed);
        }
    }

    fn update_stat_line(self: *Gpu) void {
        const line =
            (self.state.lcd_status.mode0_hblank_interrupt and self.state.lcd_status.mode == 0) or
            (self.state.lcd_status.mode_1_vblank_interrupt and self.state.lcd_status.mode == 1) or
            (self.state.lcd_status.mode2_oam_interrupt and self.state.lcd_status.mode == 2) or
            (self.state.lcd_status.coincidence_interrupt and self.state.lcd_status.coincidence);
        if (line and !self.state.stat_line) self.bus.raise_cpu_interrupt(Cpu.Interrup.LCDStat);
        self.state.stat_line = line;
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

        self.handle_dma(cpuClocks);

        if (!self.state.lcd_control.lcd_display_enable) return GpuStepResult.Disabled;

        // if (self.state.lcd_display_initialization_pending) {
        //     self.state.lcd_display_initialization_pending = false;
        //     self.state.ly = 0;
        //     self.state.lcd_status.mode = 2;
        //     self.dbg_mode();
        //     self.state.mode_clocks = 0;
        //     // if (self.state.lcd_control.lcd_display_enable) {
        //     //     self.state.initializing_extra_steps = 1;
        //     // }
        // }

        if (self.state.initializing_extra_steps > 0) {
            self.state.initializing_extra_steps = 0;
            self.state.ly = 0;
            self.state.wly = 0;
            self.state.lcd_status.mode = 2;
            //Start 1 cycle ahead: the first line after enabling the LCD is 4 dots
            //short on hardware. (No extra credit for the LCDC write cycle itself:
            //store ticks the bus before writing, so the PPU's first cycle already
            //lines up with the tick that follows the write.)
            self.state.mode_clocks = 1;
            self.tracer.gpu_mode_trace(self);
        }

        self.state.mode_clocks += cpuClocks;

        switch (self.state.lcd_status.mode) {
            0 => { //H-Blank
                if (self.state.mode_clocks >= HBLANK_CLOKS) {
                    self.state.mode_clocks %= HBLANK_CLOKS;
                    self.state.ly += 1;
                    self.tracer.gpu_ly_trace(self);

                    self.state.lcd_status.mode = if (self.state.ly < 144) 2 else 1;
                    self.check_lyc();
                    self.tracer.gpu_mode_trace(self);
                    if (self.state.lcd_status.mode == 1) { //Start V-Blank
                        Logger.log("start vblank frame {d}, cpu cycles {d}\n", .{ self.state.dbg_frame_count, self.bus.cpu.state.cycles_counter });
                        self.bus.raise_cpu_interrupt(Cpu.Interrup.VBlank);
                        self.state.dbg_frame_count += 1;
                        self.state.wly = 0;
                        self.state.frame_ready = true;
                        return GpuStepResult.FrameReady;
                    }
                }
            },
            1 => { //V-Blank
                if (self.state.mode_clocks >= VBLANK_LINE_CLOCKS) {
                    self.state.mode_clocks %= VBLANK_LINE_CLOCKS;
                    self.state.ly += 1;
                    self.tracer.gpu_ly_trace(self);

                    if (self.state.ly == 154) {
                        self.state.lcd_status.mode = 2;
                        self.tracer.gpu_mode_trace(self);

                        self.state.ly = 0;
                    }
                    self.check_lyc();
                }
            },
            2 => { //OAM
                if (self.state.mode_clocks >= OAM_CLOCKS) {
                    self.state.mode_clocks %= OAM_CLOCKS;
                    self.state.lcd_status.mode = 3;
                    self.tracer.gpu_mode_trace(self);
                    self.update_stat_line();

                    self.findVisibleSprites();
                }
            },
            3 => { //raster
                if (self.state.mode_clocks >= RASTER_CLOKS) {
                    self.state.mode_clocks %= RASTER_CLOKS;
                    self.state.lcd_status.mode = 0;
                    self.tracer.gpu_mode_trace(self);
                    self.update_stat_line();

                    self.drawscanline();
                }
            },
        }
        return GpuStepResult.Normal;
    }

    //Latched at the 143->144 transition, cleared when consumed, so each frame is
    //reported exactly once even though vblank lasts many cycles.
    pub fn consume_frame_ready(self: *Gpu) bool {
        const result = self.state.frame_ready;
        self.state.frame_ready = false;
        return result;
    }

    pub fn check_lyc(self: *Gpu) void {
        self.state.lcd_status.coincidence = self.state.ly == self.state.lyc;
        self.update_stat_line();
    }

    fn findVisibleSprites(self: *Gpu) void {
        const zone = tracy.beginZone(@src(), .{ .name = "gpu findVisibleSprites" });
        defer zone.end();
        const sprite_attrbiute_table_begin = 0xFE00;
        const sprite_attrbiute_table_end = 0xFEA0;
        const sprite_attrbiute_table = self.ram[sprite_attrbiute_table_begin..sprite_attrbiute_table_end];
        const sprite_aatribute = sliceCast(SpriteAttribute, sprite_attrbiute_table, 0, 40);

        //TODO: support 16 height as well
        const sprite_height: u8 = if (self.state.lcd_control.obj_size) 16 else 8;

        self.state.visibleSpritesCount = 0;
        for (sprite_aatribute) |value| {
            if (value.y == 0 or value.y >= 160) continue; //hidden objects
            const sprite_data_y: i16 = @intCast(value.y);
            const sprite_top: i16 = @intCast(sprite_data_y - 16);
            const sprite_bottom = sprite_top + sprite_height;

            if (sprite_top > self.state.ly) continue;
            if (sprite_bottom <= self.state.ly) continue;

            self.state.visibleSprites[self.state.visibleSpritesCount] = value;
            self.state.visibleSpritesCount += 1;
            if (self.state.visibleSpritesCount == self.state.visibleSprites.len) break;
        }

        //sort
        for (0..self.state.visibleSpritesCount) |i| {
            for (0..self.state.visibleSpritesCount - i - 1) |j| {
                if (self.state.visibleSprites[j].x > self.state.visibleSprites[j + 1].x) {
                    const temp = self.state.visibleSprites[j];
                    self.state.visibleSprites[j] = self.state.visibleSprites[j + 1];
                    self.state.visibleSprites[j + 1] = temp;
                }
            }
        }
    }

    inline fn getBackgroundColor(self: *Gpu, color_index: u2) u8 {
        switch (color_index) {
            0 => return self.state.background_palette.color0,
            1 => return self.state.background_palette.color1,
            2 => return self.state.background_palette.color2,
            3 => return self.state.background_palette.color3,
        }
    }

    fn drawscanline(self: *Gpu) void {
        const zone = tracy.beginZone(@src(), .{ .name = "gpu drawscanline" });
        defer zone.end();

        const tile_width = 8;
        const tile_height = 8;
        const shades = [_]u8{ 255, 128, 63, 0 };

        const bg_tile_data_vram = if (self.state.lcd_control.bg_and_window_tile_select) self.ram[0x8000..0x9000] else self.ram[0x8800..0x9800];
        const bg_tile_data = sliceCast(SpriteData, bg_tile_data_vram, 0, 0x100);

        var bg_color_index = [_]u2{0} ** RESOLUTION_WIDTH;

        //std.debug.assert(self.state.lcd_control.bg_and_window_tile_select == true);

        // for (0..RESOLUTION_WIDTH) |index| { //debugging, to remove
        //     const framebuffer_index: usize = (@as(usize, self.state.ly) * RESOLUTION_WIDTH) + index;
        //     self.framebuffer[framebuffer_index] = shades[3];
        // }

        //Draw BG
        if (self.state.lcd_control.bg_display == true) {
            //This code is horrible, I need to re-write it!
            const bg_map_1 = if (self.state.lcd_control.bg_tilemap_display_select == false) self.ram[0x9800..0x9C00] else self.ram[0x9C00..0xA000];
            for (bg_map_1, 0..) |tile_index, i| { //TODO: no need to iterate through all 256 tiles, just get the ones that are visible
                const tile_x = i % 32;
                const tile_y = i / 32;
                const tile_index_mapped = if (self.state.lcd_control.bg_and_window_tile_select) tile_index else (tile_index +% 0x80);
                const tile = bg_tile_data[tile_index_mapped];

                const scrolled_y = (self.state.ly +% self.state.scroll_y);

                if (tile_y * tile_height > scrolled_y or tile_y * tile_height + tile_height <= scrolled_y) continue; //TODO: optimize so we dont have to check and continue here
                //if (tile_x * tile_width > RESOLUTION_WIDTH) continue; //TODO: this should probably take scroll x into account

                const y: u8 = scrolled_y % tile_height;
                for (0..tile_width) |x| {
                    const bg_x = tile_x * 8 + x;
                    var screen_x: i16 = @as(i16, @intCast(bg_x)) - @as(i16, @intCast(self.state.scroll_x));

                    const wrapped, const overflow = @addWithOverflow(self.state.scroll_x, RESOLUTION_WIDTH);

                    if (screen_x < 0 and overflow == 1) { //deal with wrapped camera
                        //const wrapped = (self.state.scroll_x + RESOLUTION_WIDTH) % 256;
                        if (bg_x >= wrapped) continue;
                        screen_x += 256;
                    } else {
                        if (screen_x < 0 or screen_x >= RESOLUTION_WIDTH) continue;
                    }

                    const color_index = tile.get_pixel_color_index(@intCast(x), y);

                    //const palette_table = if (sprite.flags.pallete == 0) self.ram[0xFF48] else self.ram[0xFF49];
                    //const shade: u2 = @intCast((palette_table >> (color_index * 2)) & 0b11);
                    //if (shade == 0) continue; //transparency
                    const framebuffer_index: usize = (@as(usize, self.state.ly) * RESOLUTION_WIDTH) + @as(usize, @intCast(screen_x));
                    // if (framebuffer_index >= self.framebuffer.len)
                    //     break;
                    self.framebuffer[framebuffer_index] = shades[self.getBackgroundColor(color_index)];
                    bg_color_index[@as(usize, @intCast(screen_x))] = color_index;
                }
            }
        }

        //Draw Window
        if (self.state.lcd_control.window_display_enable == true and self.state.window_y <= self.state.ly) {
            const win_map = if (self.state.lcd_control.window_tilemap_display_select == false) self.ram[0x9800..0x9C00] else self.ram[0x9C00..0xA000];
            for (win_map, 0..) |tile_index, i| {
                const tile_x = i % 32;
                const tile_y = i / 32;
                const tile_index_mapped = if (self.state.lcd_control.bg_and_window_tile_select) tile_index else (tile_index +% 0x80);
                const tile = bg_tile_data[tile_index_mapped];
                const view_y = self.state.wly;

                if (tile_y * tile_height > view_y or tile_y * tile_height + tile_height <= view_y) continue; //TODO: optimize so we dont have to check and continue here

                const tile_x_start_screen: i16 = @as(i16, @intCast(tile_x * tile_width)) + (@as(i16, @intCast(self.state.window_x)) - 7); //window x is offset by 7 pixels
                if (tile_x_start_screen >= RESOLUTION_WIDTH) continue;
                if (tile_x_start_screen + tile_width <= 0) continue;

                const y: u8 = view_y % tile_height;

                for (0..tile_width) |x| {
                    const framebuffer_x: i16 = tile_x_start_screen + @as(i16, @intCast(x));
                    if (framebuffer_x < 0) continue;
                    if (framebuffer_x >= RESOLUTION_WIDTH) break;

                    const color_index = tile.get_pixel_color_index(@intCast(x), y);
                    const framebuffer_index: usize = (@as(usize, self.state.ly) * RESOLUTION_WIDTH) + @as(usize, @intCast(framebuffer_x));
                    if (framebuffer_index >= self.framebuffer.len)
                        break;
                    self.framebuffer[framebuffer_index] = shades[self.getBackgroundColor(color_index)];
                    bg_color_index[@as(usize, @intCast(framebuffer_x))] = color_index;
                }
            }
            if (self.state.window_x <= 166) self.state.wly += 1;
        }

        //draw sprites
        const tile_data_vram = self.ram[0x8000..0x9000];
        const tile_data = sliceCast(SpriteData, tile_data_vram, 0, 0x100);
        // if (self.state.dbg_frame_count == 1253 and self.state.visibleSpritesCount > 0) {
        //     @breakpoint();
        // }
        const sprite_width = 8;
        const sprite_height: u8 = if (self.state.lcd_control.obj_size) 16 else 8;
        for (0..RESOLUTION_WIDTH) |index| {
            const i: u8 = @intCast(index);
            //const scrolled_x = self.state.scroll_x + i % 255;
            //const scrolled_y = self.state.scroll_y + self.state.ly % 255;
            const screen_x = i;
            const screen_y = self.state.ly;

            for (0..self.state.visibleSpritesCount) |si| {
                const sprite = self.state.visibleSprites[si];
                //TODO: x-ordering
                const sprite_left_x: i16 = (@as(i16, @intCast(sprite.x)) - 8);
                const sprite_right = (sprite_left_x + sprite_width);
                if (sprite_left_x > screen_x or sprite_right <= screen_x) continue; //this is not fully correct

                var sprite_y: i16 = screen_y - (@as(i16, @intCast(sprite.y)) - 16);
                var sprite_x: u8 = @as(u8, @intCast(screen_x - sprite_left_x));
                if (sprite.flags.xflip == 1) {
                    sprite_x = (sprite_width - 1) - sprite_x;
                }
                if (sprite.flags.yflip == 1) {
                    sprite_y = (sprite_height - 1) - sprite_y;
                }

                var tile_index = sprite.tile_index;
                if (self.state.lcd_control.obj_size) {
                    tile_index = if (sprite_y >= 8) sprite.tile_index | 0x01 else sprite.tile_index & 0xFE;
                }

                const sprite_pattern = tile_data[tile_index];
                const color_index = sprite_pattern.get_pixel_color_index(sprite_x, @intCast(@mod(sprite_y, 8)));
                if (color_index == 0) continue; //transparent
                const palette_table = if (sprite.flags.pallete == 0) self.state.object_palette[0] else self.state.object_palette[1];

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

                const framebuffer_index: usize = (@as(usize, screen_y) * RESOLUTION_WIDTH) + index;
                if (sprite.flags.priority == 1 and bg_color_index[index] > 0) break; //this pixel is behind the background, but is the chosen sprite for this pixel, move on to the next pixel
                self.framebuffer[framebuffer_index] = shades[shade];
                break; //this is the chosen sprite for this pixel, move on to the next pixel
            }
        }
    }
    fn frameready(_: *Gpu) void {}

    pub fn snapshotTiles(self: *Gpu) []u8 {
        const sprite_width = 8;
        const sprite_height = 8;
        const tiles_colum = 16;
        const fb_width = tiles_colum * 8;

        const sprite_table = self.ram[0x8000..0x9800];
        const sprite_data = sliceCast(SpriteData, sprite_table, 0, 384);
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
    if (offset + count * @sizeOf(T) > buffer.len) unreachable;

    const ptr = @intFromPtr(buffer.ptr) + offset;
    const arrPtr: [*]T = @ptrFromInt(ptr);
    return arrPtr[0..count];
}

const std = @import("std");
const tracy = @import("tracy");
const cpu_import = @import("cpu.zig");
const bus_import = @import("bus.zig");
const Logger = @import("logger.zig");
const Tracer = @import("tracer.zig").Tracer;

const Cpu = cpu_import.Cpu;
const Bus = bus_import.Bus;
const mcycles = cpu_import.mcycles;
