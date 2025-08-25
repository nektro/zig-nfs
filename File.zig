const std = @import("std");
const builtin = @import("builtin");
const sys_libc = @import("sys-libc");
const nio = @import("nio");
const errno = @import("errno");

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
        fn foo(s: *anyopaque, buffer: []u8) anyerror!usize {
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
