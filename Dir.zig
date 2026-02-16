const std = @import("std");
const builtin = @import("builtin");
const sys_linux = @import("sys-linux");

const nfs = @import("./nfs.zig");
const File = nfs.File;
const Dir = @This();

const os = builtin.target.os.tag;

const sys = switch (os) {
    .linux => sys_linux,
    else => unreachable,
};

fd: nfs.Handle,

// Resource allocation may fail; resource deallocation must succeed.
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
pub fn openDirC(self: Dir, sub_path: []const u8, flags: OpenDirFlags) !Dir {
    std.debug.assert(sub_path.len <= sys_linux.NAME_MAX);
    var buf: [sys_linux.NAME_MAX + 1]u8 = undefined;
    @memcpy(buf[0..sub_path.len], sub_path);
    buf[sub_path.len] = 0;
    return openDir(self, buf[0..sub_path.len :0], flags);
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

pub fn makeDir(self: Dir, sub_path: [:0]const u8) !void {
    if (os == .linux)
        try sys_linux.mkdirat(@intFromEnum(self.fd), sub_path, 0o755);
}

pub fn statFile(self: Dir, sub_path: [:0]const u8) !File.Stat {
    if (os == .linux)
        return .fromPosix(try sys_linux.fstatat(@intFromEnum(self.fd), sub_path, 0));
}

pub fn makePath(self: Dir, sub_path: [:0]const u8) !void {
    var it = try std.fs.path.componentIterator(sub_path);
    var component = it.last() orelse return;
    var zuffer: [sys_linux.NAME_MAX + 1]u8 = undefined;
    while (true) {
        @memcpy(zuffer[0..component.path.len], component.path);
        zuffer[component.path.len] = 0;
        self.makeDir(zuffer[0..component.path.len :0]) catch |err| switch (err) {
            error.EEXIST => {
                // stat the file and return an error if it's not a directory
                // this is important because otherwise a dangling symlink
                // could cause an infinite loop
                check_dir: {
                    // workaround for windows, see https://github.com/ziglang/zig/issues/16738
                    const fstat = self.statFile(zuffer[0..component.path.len :0]) catch |stat_err| switch (stat_err) {
                        error.EISDIR => break :check_dir,
                        else => |e| return e,
                    };
                    if (fstat.kind() != .directory) return error.NotDir;
                }
            },
            error.ENOENT => |e| {
                component = it.previous() orelse return e;
                continue;
            },
            else => |e| return e,
        };
        component = it.next() orelse return;
    }
}

pub fn makeOpenPath(self: Dir, sub_path: [:0]const u8, flags: OpenDirFlags) !Dir {
    return self.openDir(sub_path, flags) catch |err| switch (err) {
        error.ENOENT => {
            try self.makePath(sub_path);
            return self.openDir(sub_path, flags);
        },
        else => |e| return e,
    };
}

pub fn readlink(self: Dir, noalias sub_path: [:0]const u8, noalias buf: []u8) ![:0]u8 {
    return sys.readlinkat(@intFromEnum(self.fd), sub_path, buf);
}
