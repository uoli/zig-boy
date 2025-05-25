const std = @import("std");
const expect = std.testing.expect;

const Allocator = std.mem.Allocator;

pub fn main() !void {
    const trace_path_mine = "F:\\Projects\\game-boy-emu-zig\\trace-001.log";
    const trace_path_higan = "F:\\tmp\\Logs\\Game Boy\\event-20250524_174917.log";
    _ = try compare_traces(trace_path_mine[0..], trace_path_higan[0..]);
}

pub fn compare_traces(path_a: []const u8, path_b: []const u8) !bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("leak?");
    }
    //const allocator = gpa.allocator();

    var file_a = try std.fs.openFileAbsolute(path_a, .{});
    defer file_a.close();

    var file_b = try std.fs.openFileAbsolute(path_b, .{});
    defer file_b.close();

    //var reader_a = file_a.reader();
    //var reader_b = file_b.reader();
    var buf_reader_a = std.io.bufferedReader(file_a.reader());
    var buf_reader_b = std.io.bufferedReader(file_b.reader());
    const reader_a = buf_reader_a.reader();
    const reader_b = buf_reader_b.reader();

    var buf_a: [1024]u8 = undefined;
    var buf_b: [1024]u8 = undefined;
    var current_line_number_a: usize = 0;
    var current_line_number_b: usize = 0;
    const ignored_lines = [_]usize{2368868, 2368869, 2368870, 2368871, 2368872, 2368873, 2368874, 2368875, 2368876, 2368877, 2368878, 2368879, 2368884, 2368885, 2368886, 2368887, 2368888,};
    const start_line_a = 2449218; //2437182; //2425148; //2413124; //2401089; //2389053; //2377019; //2376657; //2211599; //
    const start_line_b = 2449218; //2437182; //2425148; //2413124; //2401089; //2389053; //2377019; //2376703; //2211598; //

    while(current_line_number_a < start_line_a){ 
        _ = try reader_a.readUntilDelimiterOrEof(buf_a[0..], '\n');
        current_line_number_a += 1;
    }
    while(current_line_number_b < start_line_b){ 
        _ = try reader_b.readUntilDelimiterOrEof(buf_b[0..], '\n');
        current_line_number_b += 1;
    }

    while (true) {
        const trace_data_a, const line_a = try read_line_until_parse_or_eof(reader_a, buf_a[0..], &extract_trace_mine, &current_line_number_a);
        const trace_data_b, const line_b = try read_line_until_parse_or_eof(reader_b, buf_b[0..], &extract_trace_higan, &current_line_number_b);
        //var line_a = try reader_a.readUntilDelimiterAlloc(allocator, '\n', 1024);
        //var line_b = try reader_b.readUntilDelimiterAlloc(allocator, '\n', 1024);

        if (!compare_lines(trace_data_a, trace_data_b)) {
            std.debug.print(
                \\Lines do not matach:
                \\[{d}] {s}
                \\[{d}] {s}
                \\
                \\
            , .{ current_line_number_a, line_a, current_line_number_b, line_b });
            if (contains(usize, &ignored_lines, current_line_number_a)) {
                continue;
            }
            return false;
        }
    }
    return true;
}

fn contains(comptime T: type, haystack: []const T, needle: T) bool {
    for (haystack) |item| {
        if (item == needle) {
            return true;
        }
    }
    return false;
}

fn read_line_until_parse_or_eof(reader: anytype, buf: []u8, fn_extract_trace: *const fn (line: []const u8) ParsedTraceData, current_line_number: *usize) !struct { TraceData, []u8 } {
    while (true) {
        const line = try reader.readUntilDelimiterOrEof(buf, '\n');
        current_line_number.* += 1;

        const line_def: []u8 = line.?;
        //std.debug.print("{*} , {d} {s}\n", .{ line_def.ptr, line_def.len, line_def });
        const result = fn_extract_trace(line_def);
        switch (result) {
            .Ok => return .{ result.Ok, line_def },
            .Error => continue,
        }
    }
}

fn compare_lines(trace_data_a: TraceData, trace_data_b: TraceData) bool {
    if (trace_data_a.pc_address != trace_data_b.pc_address) {
        std.debug.print("PC: 0x{x} != 0x{x}\n", .{ trace_data_a.pc_address, trace_data_b.pc_address });
        return false;
    }
    if (trace_data_a.AF != trace_data_b.AF) {
        std.debug.print("AF: 0x{x} != 0x{x}\n", .{ trace_data_a.AF, trace_data_b.AF });
        return false;
    }
    if (trace_data_a.BC != trace_data_b.BC) {
        std.debug.print("BC: 0x{x} != 0x{x}\n", .{ trace_data_a.BC, trace_data_b.BC });
        return false;
    }
    if (trace_data_a.DE != trace_data_b.DE) {
        std.debug.print("DE: 0x{x} != 0x{x}\n", .{ trace_data_a.DE, trace_data_b.DE });
        return false;
    }
    if (trace_data_a.HL != trace_data_b.HL) {
        std.debug.print("HL: 0x{x} != 0x{x}\n", .{ trace_data_a.HL, trace_data_b.HL });
        return false;
    }
    if (trace_data_a.SP != trace_data_b.SP) {
        std.debug.print("SP: 0x{x} != 0x{x}\n", .{ trace_data_a.SP, trace_data_b.SP });
        return false;
    }
    return true;
}

const TraceData = struct {
    pc_address: u16,
    AF: u16,
    BC: u16,
    DE: u16,
    HL: u16,
    SP: u16,
};

const TraceDataTag = enum { Ok, Error };

const ParsedTraceData = union(TraceDataTag) {
    Ok: TraceData,
    Error: void,
};

fn extract_trace_mine(line: []const u8) ParsedTraceData {
    //std.debug.print("{*} , {d} {s}\n", .{ line.ptr, line.len, line });

    //[CPU] 0xff87 0x20 JR NZ, s8    0xfd    AF:0x0f40 BC:0x0005 DE:0x0000 HL:0xdfe7 SP:0xdfe7 zNhc
    var trace_data = TraceData{
        .pc_address = 0,
        .AF = 0,
        .BC = 0,
        .DE = 0,
        .HL = 0,
        .SP = 0,
    };

    if (line.len < 90) {
        return ParsedTraceData{ .Error = {} };
    }

    trace_data.pc_address = std.fmt.parseInt(u16, line[8..12], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.AF = std.fmt.parseInt(u16, line[44..48], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.BC = std.fmt.parseInt(u16, line[54..58], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.DE = std.fmt.parseInt(u16, line[64..68], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.HL = std.fmt.parseInt(u16, line[74..78], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.SP = std.fmt.parseInt(u16, line[84..88], 16) catch return ParsedTraceData{ .Error = {} };

    return ParsedTraceData{ .Ok = trace_data }; //
}

fn extract_trace_higan(line: []const u8) ParsedTraceData {
    //5695  add  hl,bc        AF:bb20 BC:0000 DE:1100 HL:5b93 SP:dfdb
    var trace_data = TraceData{
        .pc_address = 0,
        .AF = 0,
        .BC = 0,
        .DE = 0,
        .HL = 0,
        .SP = 0,
    };
    if (line.len < 62) {
        return ParsedTraceData{ .Error = {} };
    }

    trace_data.pc_address = std.fmt.parseInt(u16, line[0..4], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.AF = std.fmt.parseInt(u16, line[27..31], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.BC = std.fmt.parseInt(u16, line[35..39], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.DE = std.fmt.parseInt(u16, line[43..47], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.HL = std.fmt.parseInt(u16, line[51..55], 16) catch return ParsedTraceData{ .Error = {} };
    trace_data.SP = std.fmt.parseInt(u16, line[59..63], 16) catch return ParsedTraceData{ .Error = {} };

    return ParsedTraceData{ .Ok = trace_data }; //

}

test "extract_trace" {
    const line = "[CPU] 0xff87 0x20 JR NZ, s8    0xfd    AF:0x0f40 BC:0x0005 DE:0x0000 HL:0xdfe7 SP:0xdfe7 zNhc";
    const data = extract_trace_mine(line[0..]);
    const expected = TraceData{
        .pc_address = 0xff87,
        .AF = 0x0f40,
        .BC = 0x0005,
        .DE = 0x0000,
        .HL = 0xdfe7,
        .SP = 0xdfe7,
    };

    try std.testing.expectEqual(expected, data.Ok);
}

test "extract_trace_higan" {
    const line = "5695  add  hl,bc        AF:bb20 BC:0000 DE:1100 HL:5b93 SP:dfdb";
    const data = extract_trace_higan(line[0..]);
    const expected = TraceData{
        .pc_address = 0x5695,
        .AF = 0xbb20,
        .BC = 0x0000,
        .DE = 0x1100,
        .HL = 0x5b93,
        .SP = 0xdfdb,
    };

    try std.testing.expectEqual(expected, data.Ok);
}

test "compare_traces" {
    const trace_path_mine = "F:\\Projects\\game-boy-emu-zig\\trace-001.log";
    const trace_path_higan = "F:\\tmp\\Logs\\Game Boy\\event-20250523_224446.log";
    const result = compare_traces(trace_path_mine[0..], trace_path_higan[0..]);

    try std.testing.expectEqual(true, result);
}

test "24" {}
