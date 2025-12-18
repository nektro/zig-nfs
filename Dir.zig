const std = @import("std");
const builtin = @import("builtin");
const sys_linux = @import("sys-linux");

const nfs = @import("./nfs.zig");
const File = nfs.File;
const Dir = @This();

const os = builtin.target.os.tag;

fd: nfs.Handle,

pub fn close(self: Dir) void {
    if (os == .linux)
        sys_linux.close(@intFromEnum(self.fd)) catch {};
}

pub fn openFile(self: Dir, sub_path: [:0]const u8, flags: OpenFileFlags) !File {
    _ = flags;
    if (os == .linux)
        return .{ .fd = @enumFromInt(try sys_linux.openat(@intFromEnum(self.fd), sub_path.ptr, sys_linux.O.RDONLY)) };
}

pub const OpenFileFlags = packed struct {
    //
};

pub fn openDir(self: Dir, sub_path: [:0]const u8, flags: OpenDirFlags) !Dir {
    _ = flags;
    if (os == .linux)
        return .{ .fd = @enumFromInt(try sys_linux.openat(@intFromEnum(self.fd), sub_path.ptr, sys_linux.O.RDONLY | sys_linux.O.DIRECTORY)) };
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
