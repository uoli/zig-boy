pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 3) std.debug.panic("wrong number of arguments", .{});
    const input_json_file_path = args[1];
    const output_file_path = args[2];

    var input_file = std.fs.cwd().openFile(input_json_file_path, .{}) catch |err| {
        std.debug.panic("unable to open '{s}': {s}", .{ input_json_file_path, @errorName(err) });
    };
    defer input_file.close();

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.debug.panic("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    const json_txt = try input_file.readToEndAlloc(arena, std.math.maxInt(usize));

    var parse_result = try std.json.parseFromSlice(std.json.Value, arena, json_txt, .{});
    defer parse_result.deinit();

    // const opcodeArray = try std.json.parseFromTokenSource([]const OpCodeEntry, arena, &json_reader, .{
    //     .allocate = .alloc_if_needed,
    //     .max_value_len = 1000,
    // });
    // defer opcodeArray.deinit();

    var opmetadata = try std.ArrayList(struct { u16, []const u8 }).initCapacity(arena, 256);
    defer opmetadata.deinit();

    var extopmetadata = try std.ArrayList(struct { u16, []const u8 }).initCapacity(arena, 256);
    defer extopmetadata.deinit();

    for (parse_result.value.array.items) |item| {
        // for (item.object.keys()) |value| {
        //     std.debug.print("{s}\n", .{value});
        // }
        const opcode_str = item.object.get("opCode").?.string;
        const opcode = try std.fmt.parseInt(u16, opcode_str, 16);
        const mnemonic = item.object.get("mnemonic").?.string;
        if (opcode <= 0xFF) {
            try opmetadata.append(.{ opcode, mnemonic });
        } else {
            try extopmetadata.append(.{ opcode, mnemonic });
        }
    }
    const s =
        \\const std = @import("std");
        \\const main = @import("main");
        \\const cpu_utils = main.cpu_utils;
        \\const OpCodeInfo = cpu_utils.OpCodeInfo;
        \\const ArgInfo = cpu_utils.ArgInfo;
        \\
    ;
    try std.fmt.format(output_file.writer(), s, .{});

    try generate_opcode_func(output_file.writer(), "get_opcodes_table", opmetadata);
    try generate_opcode_func(output_file.writer(), "get_extopcodes_table", extopmetadata);
}

fn generate_opcode_func(writer: anytype, func_name: []const u8, opmetadata: std.ArrayList(struct { u16, []const u8 })) !void {
    const s =
        \\pub fn {s}() [256]OpCodeInfo {{
        \\ var result: [256]OpCodeInfo = undefined;
        \\
    ;
    try std.fmt.format(writer, s, .{func_name});

    for (opmetadata.items) |item| {
        const opcode = item[0] & 0xFF;
        const mnemonic = item[1];

        //todo: d8, a8, s8, d16, a16,
        const d8Found = std.mem.indexOf(u8, mnemonic, "d8");
        const a8Found = std.mem.indexOf(u8, mnemonic, "a8");
        const s8Found = std.mem.indexOf(u8, mnemonic, "s8");
        const a168Found = std.mem.indexOf(u8, mnemonic, "a16");
        const d168Found = std.mem.indexOf(u8, mnemonic, "d16");

        const opargs = if (d8Found != null or a8Found != null or s8Found != null) ".U8" else if (d168Found != null or a168Found != null) ".U16" else ".None";

        try std.fmt.format(writer, "result[0x{x:02}] = OpCodeInfo.init(0x{x:02}, \"{s}\", {s});\n", .{ opcode, opcode, mnemonic, opargs });
    }
    const s2 =
        \\  return result;
        \\}}
        \\
    ;
    try std.fmt.format(writer, s2, .{});
}

const std = @import("std");
