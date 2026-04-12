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
    return sys.close(@intFromEnum(self.fd)) catch {};
}

pub fn openFile(self: Dir, sub_path: [:0]const u8, flags: OpenFileFlags) !File {
    _ = flags;
    return .{ .fd = @enumFromInt(try sys.openat(@intFromEnum(self.fd), sub_path.ptr, sys.O.RDONLY)) };
}

pub const OpenFileFlags = packed struct {
    //
};

pub fn openDir(self: Dir, sub_path: [:0]const u8, flags: OpenDirFlags) !Dir {
    const oflag: c_int = sys.O.RDONLY | sys.O.DIRECTORY;
    _ = flags;
    return .{ .fd = @enumFromInt(try sys.openat(@intFromEnum(self.fd), sub_path.ptr, oflag)) };
}
pub fn openDirC(self: Dir, sub_path: []const u8, flags: OpenDirFlags) !Dir {
    std.debug.assert(sub_path.len <= sys.NAME_MAX);
    var buf: [sys.NAME_MAX + 1]u8 = undefined;
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
    try sys.mkdirat(@intFromEnum(self.fd), sub_path, 0o755);
}

pub fn statFile(self: Dir, sub_path: [:0]const u8) !File.Stat {
    return .fromPosix(try sys.fstatat(@intFromEnum(self.fd), sub_path, 0));
}

pub fn makePath(self: Dir, sub_path: [:0]const u8) !void {
    var it = try std.fs.path.componentIterator(sub_path);
    var component = it.last() orelse return;
    var zuffer: [sys.NAME_MAX + 1]u8 = undefined;
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

pub fn iterate(self: Dir) Iterator {
    return .{
        .dir = self,
        .buf = undefined,
        .idx = 0,
        .len = 0,
    };
}

pub const Iterator = struct {
    dir: Dir,
    buf: [1024]u8,
    idx: usize,
    len: usize,

    pub fn next(iter: *Iterator) !?Entry {
        if (iter.idx == iter.len) {
            const len = try sys.getdents(@intFromEnum(iter.dir.fd), &iter.buf);
            if (len == 0) return null;
            iter.idx = 0;
            iter.len = len;
        }
        const ent: *align(1) sys.struct_dirent = @ptrCast(&iter.buf[iter.idx]);
        iter.idx += ent.reclen;
        const name_nidx = std.mem.indexOfScalar(u8, &ent.name, 0).?;
        const name = ent.name[0..name_nidx :0];
        if (std.mem.eql(u8, name, ".")) return next(iter);
        if (std.mem.eql(u8, name, "..")) return next(iter);
        return .{
            .name = name,
            .type = ent.type,
        };
    }

    pub const Entry = struct {
        name: [:0]const u8,
        type: sys.DT,
    };
};

pub fn walk(self: Dir, allocator: std.mem.Allocator) !Walker {
    var stack: std.ArrayListUnmanaged(Walker.StackItem) = .empty;

    try stack.append(allocator, .{
        .iter = self.iterate(),
        .dirname_len = 0,
    });

    return .{
        .allocator = allocator,
        .stack = stack,
        .name_buffer = .empty,
    };
}

pub const Walker = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayListUnmanaged(StackItem),
    name_buffer: std.ArrayListUnmanaged(u8),

    pub const Entry = struct {
        dir: Dir,
        basename: [:0]const u8,
        path: [:0]const u8,
        type: sys.DT,
    };

    const StackItem = struct {
        iter: Dir.Iterator,
        dirname_len: usize,
    };

    pub fn next(self: *Walker) !?Walker.Entry {
        const gpa = self.allocator;
        while (self.stack.items.len != 0) {
            var top = &self.stack.items[self.stack.items.len - 1];
            var containing = top;
            var dirname_len = top.dirname_len;
            if (top.iter.next() catch |err| {
                var item = self.stack.pop().?;
                if (self.stack.items.len != 0) item.iter.dir.close();
                return err;
            }) |base| {
                self.name_buffer.shrinkRetainingCapacity(dirname_len);
                if (self.name_buffer.items.len != 0) {
                    try self.name_buffer.append(gpa, std.fs.path.sep);
                    dirname_len += 1;
                }
                try self.name_buffer.ensureUnusedCapacity(gpa, base.name.len + 1);
                self.name_buffer.appendSliceAssumeCapacity(base.name);
                self.name_buffer.appendAssumeCapacity(0);
                if (base.type == .DIR) {
                    var new_dir = top.iter.dir.openDir(base.name, .{}) catch |err| switch (err) {
                        error.ENAMETOOLONG => unreachable, // no path sep in base.name
                        else => |e| return e,
                    };
                    {
                        errdefer new_dir.close();
                        try self.stack.append(gpa, .{
                            .iter = new_dir.iterate(), // was iterateAssumeFirstIteration
                            .dirname_len = self.name_buffer.items.len - 1,
                        });
                        top = &self.stack.items[self.stack.items.len - 1];
                        containing = &self.stack.items[self.stack.items.len - 2];
                    }
                }
                return .{
                    .dir = containing.iter.dir,
                    .basename = self.name_buffer.items[dirname_len .. self.name_buffer.items.len - 1 :0],
                    .path = self.name_buffer.items[0 .. self.name_buffer.items.len - 1 :0],
                    .type = base.type,
                };
            } else {
                var item = self.stack.pop().?;
                if (self.stack.items.len != 0) item.iter.dir.close();
            }
        }
        return null;
    }

    pub fn deinit(self: *Walker) void {
        const gpa = self.allocator;
        // Close any remaining directories except the initial one (which is always at index 0)
        if (self.stack.items.len > 1) {
            for (self.stack.items[1..]) |*item| {
                item.iter.dir.close();
            }
        }
        self.stack.deinit(gpa);
        self.name_buffer.deinit(gpa);
    }
};

pub fn rename(self: Dir, old: [:0]const u8, new: [:0]const u8) !void {
    return sys.renameat(@intFromEnum(self.fd), old.ptr, @intFromEnum(self.fd), new.ptr);
}
pub fn renameC(self: Dir, old: []const u8, new: []const u8) !void {
    std.debug.assert(old.len <= sys.NAME_MAX);
    std.debug.assert(new.len <= sys.NAME_MAX);
    var old_buf: [sys.NAME_MAX + 1]u8 = undefined;
    var new_buf: [sys.NAME_MAX + 1]u8 = undefined;
    @memcpy(old_buf[0..old.len], old);
    @memcpy(new_buf[0..new.len], new);
    old_buf[old.len] = 0;
    new_buf[new.len] = 0;
    return rename(self, old_buf[0..old.len :0], new_buf[0..new.len :0]);
}
