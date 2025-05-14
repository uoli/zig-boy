pub const ArgInfo = enum { None, U8, U16 };

pub const OpCodeInfo = struct {
    name: []const u8,
    code: u8,
    arg: ArgInfo,
    pub fn init(code: u8, name: []const u8, arg: ArgInfo) OpCodeInfo {
        return OpCodeInfo{
            .name = name,
            .code = code,
            .arg = arg,
        };
    }
};

const std = @import("std");
