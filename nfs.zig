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

pub const Error = sys.errno.Error;
pub const PATH_MAX = sys.PATH_MAX;
pub const NAME_MAX = sys.NAME_MAX;

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

/// Free a region of memory allocated with mmap.
/// Any error calling munmap is ignored.
pub fn munmap(region: []const u8) void {
    return sys.munmap(region.ptr, region.len) catch {};
}

pub fn mkdtemp() !Dir {
    var template = "/tmp/tmp.XXXXXXXXXX\x00".*;
    const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var buf: [10]u8 = @splat(0);
    const rand = try sys.getrandom(&buf, 0);
    if (rand.len != 10) return error.EAGAIN;
    for (template[9..][0..10], rand) |*a, b| a.* = letters[b % 62];
    const path = template[0 .. template.len - 1 :0];
    return cwd().makeOpenPath(path, .{});
}

pub fn mktemp(flags: Dir.CreateFlags) !File {
    var template = "/tmp/tmp.XXXXXXXXXX\x00".*;
    const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var buf: [10]u8 = @splat(0);
    const rand = try sys.getrandom(&buf, 0);
    if (rand.len != 10) return error.EAGAIN;
    for (template[9..][0..10], rand) |*a, b| a.* = letters[b % 62];
    const path = template[0 .. template.len - 1 :0];
    return cwd().createFile(path, flags);
}
