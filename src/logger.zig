const std = @import("std");

var instance: Logger = undefined;

const Logger = struct {
    file: std.fs.File,

    pub fn init() Logger {
        const file = std.fs.cwd().createFile(
            "trace-001.log",
            .{ .read = false, .truncate = true },
        ) catch unreachable;

        return Logger{
            .file = file,
        };
    }

    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        var args_str: [1024:0]u8 = undefined;
        const str = std.fmt.bufPrint(&args_str, fmt, args) catch unreachable;
        _ = self.file.writer().write(str) catch unreachable;
    }

    pub fn deinit(self: *Logger) void {
        self.file.close();
    }
};

pub fn init() void {
    instance = Logger.init();
}

pub fn log(comptime fmt: []const u8, args: anytype) void {
    instance.log(fmt, args);
}

pub fn deinit() void {
    instance.deinit();
    instance = undefined;
}