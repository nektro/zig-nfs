const std = @import("std");
const builtin = @import("builtin");
const sys_linux = @import("sys-linux");

pub const Dir = @import("./Dir.zig");
pub const File = @import("./File.zig");

const os = builtin.target.os.tag;

const sys = switch (os) {
    .linux => sys_linux,
    else => unreachable,
};

pub const Handle = switch (os) {
    .linux => enum(c_int) { _ },
    else => unreachable,
};

pub fn cwd() Dir {
    return .{ .fd = @enumFromInt(sys.AT.FDCWD) };
}

pub fn stdin() File {
    return .{ .fd = @enumFromInt(0) };
}

pub fn stdout() File {
    return .{ .fd = @enumFromInt(1) };
}

pub fn stderr() File {
    return .{ .fd = @enumFromInt(2) };
}

pub fn memfd_create(name: [*:0]const u8, flags: c_uint) !File {
    return .{ .fd = @enumFromInt(try sys.memfd_create(name, flags)) };
}
