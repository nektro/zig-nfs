const std = @import("std");
const builtin = @import("builtin");
const sys_libc = @import("sys-libc");
const nio = @import("nio");
const errno = @import("errno");
const time = @import("time");

const nfs = @import("./nfs.zig");
const Dir = nfs.Dir;
const File = @This();

fd: nfs.Handle,

pub fn close(self: File) void {
    sys_libc.close(@intFromEnum(self.fd)) catch {};
}

pub const ReadError = switch (builtin.target.os.tag) {
    .linux,
    => errno.Error,
    else => @compileError("TODO"),
};
pub usingnamespace nio.Readable(@This(), ._bare);
pub fn read(self: File, buffer: []u8) ReadError!usize {
    return sys_libc.read(@intFromEnum(self.fd), buffer);
}

pub fn anyReadable(self: File) nio.AnyReadable {
    const S = struct {
        fn foo(s: *allowzero anyopaque, buffer: []u8) anyerror!usize {
            const fd: nfs.Handle = @enumFromInt(@intFromPtr(s));
            const f: File = .{ .fd = fd };
            return f.read(buffer);
        }
    };
    return .{
        .readFn = S.foo,
        .state = @ptrFromInt(@as(usize, @bitCast(@as(isize, @intCast(@intFromEnum(self.fd)))))),
    };
}

pub fn stat(self: File) !Stat {
    const st = try sys_libc.fstat(@intFromEnum(self.fd));
    return .{
        .inode = st.ino,
        .size = @bitCast(st.size),
        .mode = st.mode,
        .kind = {},
        .atime = @as(i128, st.atim.sec) * time.ns_per_s + st.atim.nsec,
        .mtime = @as(i128, st.mtim.sec) * time.ns_per_s + st.mtim.nsec,
        .ctime = @as(i128, st.ctim.sec) * time.ns_per_s + st.ctim.nsec,
    };
}

pub const Stat = struct {
    inode: INode,
    size: u64,
    mode: Mode,
    kind: void, //Kind,
    /// Last access time in nanoseconds, relative to UTC 1970-01-01.
    atime: i128,
    /// Last modification time in nanoseconds, relative to UTC 1970-01-01.
    mtime: i128,
    /// Last status/metadata change time in nanoseconds, relative to UTC 1970-01-01.
    ctime: i128,
};

pub const INode = switch (builtin.target.os.tag) {
    .linux,
    => sys_libc.ino_t,
    else => |v| @compileError("TODO: " ++ @tagName(v)),
};

pub const Mode = switch (builtin.target.os.tag) {
    .linux,
    => sys_libc.mode_t,
    else => |v| @compileError("TODO: " ++ @tagName(v)),
};

pub const Kind = enum {
    //
};
