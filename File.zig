const std = @import("std");
const builtin = @import("builtin");
const nio = @import("nio");
const time = @import("time");

const nfs = @import("./nfs.zig");
const Dir = nfs.Dir;
const File = @This();

const os = builtin.target.os.tag;

const sys = switch (os) {
    .linux => @import("sys-linux"),
    .macos => @import("sys-darwin"),
    .freebsd => @import("sys-freebsd"),
    .netbsd => @import("sys-netbsd"),
    .openbsd => @import("sys-openbsd"),
    else => unreachable,
};

pub const stdin = nfs.stdin;
pub const stdout = nfs.stdout;
pub const stderr = nfs.stderr;

fd: nfs.Handle,

// Resource allocation may fail; resource deallocation must succeed.
pub fn close(self: File) void {
    sys.close(@intFromEnum(self.fd)) catch {};
}

const R = nio.Readable(@This(), ._bare);
pub const readAll = R.readAll;
pub const readAtLeast = R.readAtLeast;
pub const readNoEof = R.readNoEof;
pub const readAllAlloc = R.readAllAlloc;
pub const readArray = R.readArray;
pub const readByte = R.readByte;
pub const readUntilDelimiterArrayList = R.readUntilDelimiterArrayList;
pub const readUntilDelimiterAlloc = R.readUntilDelimiterAlloc;
pub const readUntilDelimiterOrEofAlloc = R.readUntilDelimiterOrEofAlloc;
pub const readUntilDelimitersBuf = R.readUntilDelimitersBuf;
pub const readUntilDelimitersArrayList = R.readUntilDelimitersArrayList;
pub const readAlloc = R.readAlloc;
pub const readInt = R.readInt;
pub const readUntilDelimitersAlloc = R.readUntilDelimitersAlloc;
pub const readUntilDelimiter = R.readUntilDelimiter;
pub const readUntilDelimiterOrEof = R.readUntilDelimiterOrEof;
pub const readExpected = R.readExpected;
pub const readType = R.readType;
pub const skipBytes = R.skipBytes;
pub const skipUntilDelimiterOrEof = R.skipUntilDelimiterOrEof;
pub const pipeTo = R.pipeTo;

pub const ReadError = sys.errno.Error;
pub fn read(self: File, buffer: []u8) ReadError!usize {
    return sys.read(@intFromEnum(self.fd), buffer);
}

pub fn anyReadable(self: File) nio.AnyReadable {
    const S = struct {
        fn read(s: *allowzero anyopaque, buffer: []u8) anyerror!usize {
            const fd: nfs.Handle = @enumFromInt(@intFromPtr(s));
            const f: File = .{ .fd = fd };
            return f.read(buffer);
        }
    };
    return .{
        .vtable = &.{ .read = S.read },
        .state = @ptrFromInt(@as(usize, @bitCast(@as(isize, @intCast(@intFromEnum(self.fd)))))),
    };
}

pub fn stat(self: File) !Stat {
    return .fromPosix(try sys.fstat(@intFromEnum(self.fd)));
}

pub fn getEndPos(self: File) !u64 {
    return (try self.stat()).size;
}

pub fn readToEndAlloc(self: File, allocator: std.mem.Allocator, max_bytes: usize, size_hint: ?usize) ![:0]u8 {
    var array_list = try std.array_list.Managed(u8).initCapacity(allocator, @min(size_hint orelse 1023, max_bytes) + 1);
    defer array_list.deinit();
    self.readAllArrayList(&array_list, max_bytes) catch |err| switch (err) {
        error.StreamTooLong => return error.FileTooBig,
        else => |e| return e,
    };
    return try array_list.toOwnedSliceSentinel(0);
}

pub fn readAllArrayList(self: File, array_list: *std.array_list.Managed(u8), max_append_size: usize) anyerror!void {
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

const W = nio.Writable(@This(), ._bare);
pub const writeAll = W.writeAll;
pub const writevAll = W.writevAll;
pub const writeByteNTimes = W.writeByteNTimes;
pub const writeNTimes = W.writeNTimes;
pub const writeInt = W.writeInt;
pub const writeStruct = W.writeStruct;
pub const writeIntPretty = W.writeIntPretty;
pub const print = W.print;

pub const WriteError = sys.errno.Error;
pub fn write(self: File, buffer: []const u8) WriteError!usize {
    return sys.write(@intFromEnum(self.fd), buffer);
}
pub fn writev(self: File, iovec: []const sys.struct_iovec) WriteError!usize {
    return sys.writev(@intFromEnum(self.fd), iovec);
}

pub const Stat = struct {
    inode: INode,
    size: u64,
    mode: Mode,
    /// Last access time in nanoseconds, relative to UTC 1970-01-01.
    atime: i128,
    /// Last modification time in nanoseconds, relative to UTC 1970-01-01.
    mtime: i128,
    /// Last status/metadata change time in nanoseconds, relative to UTC 1970-01-01.
    ctime: i128,

    pub fn fromPosix(st: sys.struct_stat) Stat {
        if (os == .macos) {
            return .{
                .inode = st.ino,
                .size = @bitCast(st.size),
                .mode = st.mode,
                .atime = @as(i128, st.atimespec.sec) * time.ns_per_s + st.atimespec.nsec,
                .mtime = @as(i128, st.mtimespec.sec) * time.ns_per_s + st.mtimespec.nsec,
                .ctime = @as(i128, st.ctimespec.sec) * time.ns_per_s + st.ctimespec.nsec,
            };
        }
        return .{
            .inode = st.ino,
            .size = @bitCast(st.size),
            .mode = st.mode,
            .atime = @as(i128, st.atim.sec) * time.ns_per_s + st.atim.nsec,
            .mtime = @as(i128, st.mtim.sec) * time.ns_per_s + st.mtim.nsec,
            .ctime = @as(i128, st.ctim.sec) * time.ns_per_s + st.ctim.nsec,
        };
    }

    pub fn kind(self: Stat) Kind {
        const m = self.mode & sys.S.IFMT;
        switch (m) {
            sys.S.IFBLK => return .block_device,
            sys.S.IFCHR => return .character_device,
            sys.S.IFIFO => return .named_pipe,
            sys.S.IFREG => return .file,
            sys.S.IFDIR => return .directory,
            sys.S.IFLNK => return .symlink,
            sys.S.IFSOCK => return .unix_socket,
            else => {},
        }
        return .unknown;
    }
};

pub const INode = sys.ino_t;

pub const Mode = sys.mode_t;

pub const Kind = enum {
    block_device,
    character_device,
    named_pipe,
    file,
    directory,
    symlink,
    unix_socket,
    unknown,
};

/// Maps entire file content into memory with a single syscall.
/// Release with `nfs.munmap`.
pub fn mmap(self: File) ![]const u8 {
    return mmapRegion(self, 0, (try self.stat()).size);
}

/// Maps file content into memory with a single syscall.
/// Release with `nfs.munmap`.
pub fn mmapRegion(self: File, offset: sys.off_t, len: usize) ![]const u8 {
    return sys.mmap(
        null,
        len,
        sys.PROT.READ,
        sys.MAP.PRIVATE,
        @intFromEnum(self.fd),
        offset,
    );
}

pub fn utime(self: File, times: [2]sys.struct_timespec) !void {
    return sys.futimens(@intFromEnum(self.fd), times);
}

pub fn isatty(self: File) bool {
    return sys.libc.isatty(@intFromEnum(self.fd)) == 1;
}

pub fn seekTo(self: File, pos: u64) !void {
    return sys.lseek(@intFromEnum(self.fd), @bitCast(pos), sys.SEEK.SET);
}

pub fn chmod(self: File, mode: Mode) !void {
    return sys.fchmod(@intFromEnum(self.fd), mode);
}

pub fn realpath(self: File, buf: *[sys.PATH_MAX]u8) ![:0]u8 {
    return nfs.realdpath(self.fd, buf);
}

pub fn realpathAlloc(self: File, allocator: std.mem.Allocator) ![:0]u8 {
    var buf: [sys.PATH_MAX]u8 = undefined;
    const actual = try self.realpath(&buf);
    return allocator.dupeZ(u8, actual);
}

pub fn dup(self: File) !File {
    return .{ .fd = @enumFromInt(try sys.dup(@intFromEnum(self.fd))) };
}
