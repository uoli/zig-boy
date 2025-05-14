pub const ArgInfo = enum { None, U8, U16 };

pub const OpCodeInfo = struct {
    name: []const u8,
    code: u8,
    args: [2]ArgInfo,
    pub fn init(code: u8, name: []const u8, args: [2]ArgInfo) OpCodeInfo {
        return OpCodeInfo{
            .name = name,
            .code = code,
            .args = args,
        };
    }
};

const std = @import("std");
