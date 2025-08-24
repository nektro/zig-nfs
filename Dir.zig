const std = @import("std");
const sys_libc = @import("sys-libc");

const nfs = @import("./nfs.zig");
const File = nfs.File;
const Dir = @This();

fd: nfs.Handle,

pub fn close(self: Dir) void {
    sys_libc.close(self.fd) catch {};
}

pub fn openFile(self: Dir, sub_path: [:0]const u8, flags: OpenFileFlags) !File {
    _ = flags;
    return .{ .fd = @enumFromInt(try sys_libc.openat(@intFromEnum(self.fd), sub_path.ptr, sys_libc.O.RDONLY)) };
}

pub const OpenFileFlags = packed struct {
    //
};
