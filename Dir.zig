const std = @import("std");
const sys_libc = @import("sys-libc");

const nfs = @import("./nfs.zig");
const File = nfs.File;
const Dir = @This();

fd: nfs.Handle,

pub fn close(self: Dir) void {
    sys_libc.close(@intFromEnum(self.fd)) catch {};
}

pub fn openFile(self: Dir, sub_path: [:0]const u8, flags: OpenFileFlags) !File {
    _ = flags;
    return .{ .fd = @enumFromInt(try sys_libc.openat(@intFromEnum(self.fd), sub_path.ptr, sys_libc.O.RDONLY)) };
}

pub const OpenFileFlags = packed struct {
    //
};

pub fn openDir(self: Dir, sub_path: [:0]const u8, flags: OpenDirFlags) !Dir {
    _ = flags;
    return .{ .fd = @enumFromInt(try sys_libc.openat(@intFromEnum(self.fd), sub_path.ptr, sys_libc.O.RDONLY | sys_libc.O.DIRECTORY)) };
}

pub const OpenDirFlags = packed struct {
    //
};

/// temporary method for interacting with other std apis we don't have our own version of
pub fn to_std(self: Dir) std.fs.Dir {
    return .{ .fd = @intFromEnum(self.fd) };
}

pub fn readFileAlloc(self: Dir, allocator: std.mem.Allocator, file_path: [:0]const u8, max_bytes: usize) ![:0]u8 {
    var file = try self.openFile(file_path, .{});
    defer file.close();
    const stat_size = std.math.cast(usize, try file.getEndPos()) orelse return error.FileTooBig;
    return file.readToEndAlloc(allocator, max_bytes, stat_size);
}
