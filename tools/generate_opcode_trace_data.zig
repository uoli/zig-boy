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

    const s =
        \\fn get_opcodes_table() []OpCodeInfo {{
        \\  const NoArgs = [_]ArgInfo{{ .None, .None }};
        \\  const Single8Arg = [_]ArgInfo{{ .U8, .None }};
        \\  const Single16Arg = [_]ArgInfo{{ .U16, .None }};
        \\  return [_]OpCodeInfo {{
    ;
    try std.fmt.format(output_file.writer(), s, .{});

    for (parse_result.value.array.items[0..1]) |item| {
        // for (item.object.keys()) |value| {
        //     std.debug.print("{s}\n", .{value});
        // }
        const opcode = item.object.get("opCode").?.string;
        const mnemonic = item.object.get("mnemonic").?.string;

        //todo: d8, a8, s8, d16, a16,
        const d8Found = std.mem.indexOf(u8, mnemonic, "d8");

        const opargs = if (d8Found != null) "Single8Arg" else "NoArgs";

        try std.fmt.format(output_file.writer(), "OpCodeInfo.init(0x{s}, \"{s}\", {s}),", .{ opcode, mnemonic, opargs });
    }

    try std.fmt.format(output_file.writer(), "}};", .{});
    try std.fmt.format(output_file.writer(), "}}", .{});
}

const std = @import("std");
