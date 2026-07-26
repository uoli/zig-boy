const std = @import("std");

var instance: Logger = undefined;

const BufferedWriter = std.io.BufferedWriter(1 << 16, std.fs.File.Writer);

const Logger = struct {
    file: std.fs.File,
    buffered: BufferedWriter,

    pub fn init() Logger {
        const file = std.fs.cwd().createFile(
            "trace-001.log",
            .{ .read = false, .truncate = true },
        ) catch unreachable;

        return Logger{
            .file = file,
            .buffered = .{ .unbuffered_writer = file.writer() },
        };
    }

    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.buffered.writer().print(fmt, args) catch unreachable;
    }

    pub fn flush(self: *Logger) void {
        self.buffered.flush() catch unreachable;
    }

    pub fn deinit(self: *Logger) void {
        self.flush();
        self.file.close();
    }
};

pub fn init() void {
    instance = Logger.init();
}

pub fn log(comptime fmt: []const u8, args: anytype) void {
    instance.log(fmt, args);
}

pub fn flush() void {
    instance.flush();
}

pub fn deinit() void {
    instance.deinit();
    instance = undefined;
}
