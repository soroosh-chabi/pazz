const std = @import("std");

const Store = @This();
const max_item_size: usize = 1_000_000;
allocator: std.mem.Allocator,
directory: []const u8,

/// `directory` must be absolute.
pub fn init(allocator: std.mem.Allocator, directory: []const u8) !Store {
    return .{
        .allocator = allocator,
        .directory = try allocator.dupe(u8, directory),
    };
}

pub fn deinit(self: Store) void {
    self.allocator.free(self.directory);
}

pub fn put(self: Store, name: []const u8, item: []const u8) !void {
    const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.directory, name });
    defer self.allocator.free(path);
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(item);
}

/// The returned item is owned by the caller.
pub fn get(self: Store, allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.directory, name });
    defer self.allocator.free(path);
    const file = blk: {
        if (std.fs.openFileAbsolute(path, .{})) |f| {
            break :blk f;
        } else |err| {
            return if (err == std.fs.File.OpenError.FileNotFound) null else err;
        }
    };
    defer file.close();
    return try file.readToEndAlloc(allocator, max_item_size);
}

pub fn remove(self: Store, name: []const u8) !void {
    const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.directory, name });
    defer self.allocator.free(path);
    try std.fs.deleteFileAbsolute(path);
}

fn setupTest() !Store {
    const path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "store");
    defer std.testing.allocator.free(path);
    try std.fs.deleteTreeAbsolute(path);
    try std.fs.makeDirAbsolute(path);
    return init(std.testing.allocator, path);
}

test "put then get" {
    var store = try setupTest();
    defer store.deinit();
    const name = "site";
    const item = "pass";
    try store.put(name, item);
    const retrieved_item = (try store.get(std.testing.allocator, name)).?;
    defer std.testing.allocator.free(retrieved_item);
    try std.testing.expectEqualStrings(item, retrieved_item);
}

test "get non-existent" {
    var store = try setupTest();
    defer store.deinit();
    try std.testing.expect(try store.get(std.testing.allocator, "site") == null);
}

test "overwrite" {
    var store = try setupTest();
    defer store.deinit();
    const name = "site";
    const item = "pass2";
    try store.put(name, "pass1");
    try store.put(name, item);
    const retrieved_item = (try store.get(std.testing.allocator, name)).?;
    defer std.testing.allocator.free(retrieved_item);
    try std.testing.expectEqualStrings(item, retrieved_item);
}

test "put then remove then get" {
    var store = try setupTest();
    defer store.deinit();
    const name = "site";
    const item = "pass";
    try store.put(name, item);
    try store.remove(name);
    try std.testing.expect(try store.get(std.testing.allocator, name) == null);
}
