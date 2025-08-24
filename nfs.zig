const std = @import("std");
const builtin = @import("builtin");
const sys_libc = @import("sys-libc");

pub const Dir = @import("./Dir.zig");
pub const File = @import("./File.zig");

pub const Handle = switch (builtin.target.os.tag) {
    .linux,
    => enum(c_int) { _ },
    else => @compileError("TODO"),
};

pub fn cwd() Dir {
    return .{ .fd = @enumFromInt(sys_libc.AT.FDCWD) };
}
