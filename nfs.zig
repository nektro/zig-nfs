const std = @import("std");
const builtin = @import("builtin");
const sys_linux = @import("sys-linux");

pub const Dir = @import("./Dir.zig");
pub const File = @import("./File.zig");

const os = builtin.target.os.tag;

pub const Handle = switch (os) {
    .linux,
    => enum(c_int) { _ },
    else => @compileError("TODO"),
};

pub fn cwd() Dir {
    if (os == .linux)
        return .{ .fd = @enumFromInt(sys_linux.AT.FDCWD) };
}

pub fn stdin() File {
    if (os == .linux)
        return .{ .fd = @enumFromInt(0) };
}

pub fn stdout() File {
    if (os == .linux)
        return .{ .fd = @enumFromInt(1) };
}

pub fn stderr() File {
    if (os == .linux)
        return .{ .fd = @enumFromInt(2) };
}
