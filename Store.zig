const std = @import("std");

pub const StoreError = error{
    ItemTooLarge,
};
max_item_size: usize = 1_000_000,
allocator: std.mem.Allocator,
directory: []const u8,

/// `directory` must be absolute.
pub fn init(allocator: std.mem.Allocator, directory: []const u8) !@This() {
    return .{
        .allocator = allocator,
        .directory = try allocator.dupe(u8, directory),
    };
}

pub fn deinit(self: @This()) void {
    self.allocator.free(self.directory);
}

/// The caller owns the returned value
fn pathFor(self: @This(), name: []const u8) ![]u8 {
    return try std.fs.path.join(self.allocator, &[_][]const u8{ self.directory, name });
}

/// Returns `StoreError.ItemTooLarge` error if item is longer than `max_item_size`.
pub fn put(self: @This(), name: []const u8, item: []const u8) !void {
    if (item.len > self.max_item_size) {
        return StoreError.ItemTooLarge;
    }
    const path = try self.pathFor(name);
    defer self.allocator.free(path);
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(item);
}

/// The returned item is owned by the caller. Returns `StoreError.ItemTooLarge` error if item is longer than `max_item_size`.
pub fn getAlloc(self: @This(), allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    const file = try self.openFileForGet(name) orelse return null;
    defer file.close();
    if (file.readToEndAlloc(allocator, self.max_item_size)) |item| {
        return item;
    } else |err| {
        return if (err == error.FileTooBig) StoreError.ItemTooLarge else err;
    }
}

pub fn get(self: @This(), name: []const u8, item: []u8) !?usize {
    const file = try self.openFileForGet(name) orelse return null;
    defer file.close();
    return try file.readAll(item);
}

fn openFileForGet(self: @This(), name: []const u8) !?std.fs.File {
    const path = try self.pathFor(name);
    defer self.allocator.free(path);
    if (std.fs.openFileAbsolute(path, .{})) |f| {
        return f;
    } else |err| {
        return if (err == std.fs.File.OpenError.FileNotFound) null else err;
    }
}

pub fn remove(self: @This(), name: []const u8) !void {
    const path = try self.pathFor(name);
    defer self.allocator.free(path);
    try std.fs.deleteFileAbsolute(path);
}

pub fn exists(self: @This(), name: []const u8) !bool {
    const path = try self.pathFor(name);
    defer self.allocator.free(path);
    if (std.fs.accessAbsolute(path, .{})) |_| {
        return true;
    } else |err| {
        return if (err == std.fs.Dir.AccessError.FileNotFound) false else err;
    }
}

pub fn setupTest() !@This() {
    const path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "store");
    defer std.testing.allocator.free(path);
    try std.fs.deleteTreeAbsolute(path);
    try std.fs.makeDirAbsolute(path);
    return init(std.testing.allocator, path);
}

test "put then get and exists" {
    var store = try setupTest();
    defer store.deinit();
    const name = "site";
    const item = "pass";
    try store.put(name, item);
    const retrieved_item_alloc = (try store.getAlloc(std.testing.allocator, name)).?;
    defer std.testing.allocator.free(retrieved_item_alloc);
    try std.testing.expectEqualStrings(item, retrieved_item_alloc);
    var retrieved_item: [item.len]u8 = undefined;
    try std.testing.expectEqual(item.len, (try store.get(name, &retrieved_item)).?);
    try std.testing.expectEqualStrings(item, &retrieved_item);
    try std.testing.expect(try store.exists(name));
}

test "non-existent" {
    var store = try setupTest();
    defer store.deinit();
    try std.testing.expect(try store.getAlloc(std.testing.allocator, "site") == null);
    try std.testing.expect(!try store.exists("site"));
}

test "overwrite" {
    var store = try setupTest();
    defer store.deinit();
    const name = "site";
    const item = "pass2";
    try store.put(name, "pass1");
    try store.put(name, item);
    const retrieved_item = (try store.getAlloc(std.testing.allocator, name)).?;
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
    try std.testing.expect(try store.getAlloc(std.testing.allocator, name) == null);
}

test "item too large" {
    var store = try setupTest();
    defer store.deinit();
    const item = "long item";
    store.max_item_size = item.len - 1;
    const name = "site";
    try std.testing.expectError(StoreError.ItemTooLarge, store.put(name, item));
    store.max_item_size = item.len;
    try store.put(name, item);
    store.max_item_size = item.len - 1;
    try std.testing.expectError(StoreError.ItemTooLarge, store.getAlloc(std.testing.allocator, name));
}
