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

pub fn getEndPos(self: File) !u64 {
    return (try self.stat()).size;
}

pub fn readToEndAlloc(self: File, allocator: std.mem.Allocator, max_bytes: usize, size_hint: ?usize) ![:0]u8 {
    var array_list = try std.ArrayList(u8).initCapacity(allocator, @min(size_hint orelse 1023, max_bytes) + 1);
    defer array_list.deinit();
    self.readAllArrayList(&array_list, max_bytes) catch |err| switch (err) {
        error.StreamTooLong => return error.FileTooBig,
        else => |e| return e,
    };
    return try array_list.toOwnedSliceSentinel(0);
}

pub fn readAllArrayList(self: File, array_list: *std.ArrayList(u8), max_append_size: usize) anyerror!void {
    try array_list.ensureTotalCapacity(@min(max_append_size, 4096));
    const original_len = array_list.items.len;
    var start_index: usize = original_len;
    while (true) {
        array_list.expandToCapacity();
        const dest_slice = array_list.items[start_index..];
        const bytes_read = try self.readAll(dest_slice);
        start_index += bytes_read;

        if (start_index - original_len > max_append_size) {
            array_list.shrinkAndFree(original_len + max_append_size);
            return error.StreamTooLong;
        }
        if (bytes_read != dest_slice.len) {
            array_list.shrinkAndFree(start_index);
            return;
        }
        // This will trigger ArrayList to expand superlinearly at whatever its growth rate is.
        try array_list.ensureTotalCapacity(start_index + 1);
    }
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
