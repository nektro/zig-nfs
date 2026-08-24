const std = @import("std");
const builtin = @import("builtin");
const sys_linux = @import("sys-linux");
const nio = @import("nio");

pub const Dir = @import("./Dir.zig");
pub const File = @import("./File.zig");

const os = builtin.target.os.tag;

const sys = switch (os) {
    .linux => sys_linux,
    .macos => @import("sys-darwin"),
    .freebsd => @import("sys-freebsd"),
    .netbsd => @import("sys-netbsd"),
    .openbsd => @import("sys-openbsd"),
    else => unreachable,
};

pub const Handle = enum(c_int) {
    _,
};

pub const Error = sys.errno.Error;
pub const PATH_MAX = sys.PATH_MAX;
pub const NAME_MAX = sys.NAME_MAX;

pub fn cwd() Dir {
    return .{ .fd = @enumFromInt(sys.AT.FDCWD) };
}

pub fn cwdpath(buf: []u8) ![:0]u8 {
    const ptr = try sys.getcwd(buf);
    const str = std.mem.sliceTo(ptr, 0);
    return str;
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

pub fn mktemp_buf() [19:0]u8 {
    var template: [19:0]u8 = "/tmp/tmp.XXXXXXXXXX".*;
    const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const rand = nio.randomBytes(10);
    for (template[9..][0..10], rand) |*a, b| a.* = letters[b % 62];
    return template;
}

pub fn mkdtemp() !Dir {
    const path = &mktemp_buf();
    return cwd().makeOpenPath(path, .{});
}

pub fn mktemp(flags: Dir.CreateFlags) !File {
    const path = &mktemp_buf();
    var _flags = flags;
    _flags.exclusive = true;
    return cwd().createFile(path, _flags);
}

pub fn pipe2(flag: c_int) ![2]File {
    const fds = try sys.pipe2(flag);
    return .{
        .{ .fd = @enumFromInt(fds[0]) },
        .{ .fd = @enumFromInt(fds[1]) },
    };
}

pub fn dup2(fd1: Handle, fd2: Handle) !void {
    return sys.dup2(@intFromEnum(fd1), @intFromEnum(fd2));
}

pub fn realdpath(fd: Handle, buf: *[sys.PATH_MAX]u8) ![:0]u8 {
    if (os == .linux) {
        var dbuf: [64]u8 = undefined;
        const str = nio.fmt.bufPrintZ(&dbuf, "/proc/self/fd/{d}", .{@intFromEnum(fd)}) catch unreachable;
        return sys.readlinkat(@intFromEnum(cwd().fd), str, buf);
    }
    if (os == .macos or os == .netbsd) {
        @memset(buf, 0);
        const rc = sys.libc.fcntl(@intFromEnum(fd), sys.F.GETPATH, buf.ptr);
        if (rc == -1) return sys.errno.fromInt(sys.errno.fromLibC());
        const idx = std.mem.indexOfScalar(u8, buf, 0).?;
        return buf[0..idx :0];
    }
    if (os == .freebsd) {
        // https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=198570
        comptime unreachable; // TODO
    }
    if (os == .openbsd) {
        comptime unreachable;
    }
}
