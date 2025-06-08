const std = @import("std");

const Store = @This();

pub const StoreError = error{
    ItemTooLarge,
};
max_item_size: usize = 1_000_000,
allocator: std.mem.Allocator,
/// `directory` must be absolute and should not be released as long as the returned object is around.
directory: []const u8,

/// The caller owns the returned value
fn pathFor(self: Store, name: []const u8) ![]u8 {
    return try std.fs.path.join(self.allocator, &[_][]const u8{ self.directory, name });
}

/// Returns `StoreError.ItemTooLarge` error if item is longer than `max_item_size`.
pub fn put(self: Store, name: []const u8, item: []const u8) !void {
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
pub fn getAlloc(self: Store, allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    const file = try self.openFileForGet(name) orelse return null;
    defer file.close();
    if (file.readToEndAlloc(allocator, self.max_item_size)) |item| {
        return item;
    } else |err| {
        return if (err == error.FileTooBig) StoreError.ItemTooLarge else err;
    }
}

pub fn get(self: Store, name: []const u8, item: []u8) !?usize {
    const file = try self.openFileForGet(name) orelse return null;
    defer file.close();
    return try file.readAll(item);
}

fn openFileForGet(self: Store, name: []const u8) !?std.fs.File {
    const path = try self.pathFor(name);
    defer self.allocator.free(path);
    if (std.fs.openFileAbsolute(path, .{})) |f| {
        return f;
    } else |err| {
        return if (err == std.fs.File.OpenError.FileNotFound) null else err;
    }
}

pub fn remove(self: Store, name: []const u8) !void {
    const path = try self.pathFor(name);
    defer self.allocator.free(path);
    try std.fs.deleteFileAbsolute(path);
}

pub fn exists(self: Store, name: []const u8) !bool {
    const path = try self.pathFor(name);
    defer self.allocator.free(path);
    if (std.fs.accessAbsolute(path, .{})) |_| {
        return true;
    } else |err| {
        return if (err == std.fs.Dir.AccessError.FileNotFound) false else err;
    }
}

test Store {
    const path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "store");
    defer std.testing.allocator.free(path);
    try std.fs.deleteTreeAbsolute(path);
    try std.fs.makeDirAbsolute(path);
    var store = Store{ .allocator = std.testing.allocator, .directory = path };
    {
        const name = "name1";
        const item = "item1";
        {
            try std.testing.expect(try store.getAlloc(std.testing.allocator, name) == null);
            try std.testing.expectEqual(null, try store.get(name, &[0]u8{}));
            try std.testing.expect(!try store.exists(name));
        }
        try store.put(name, item);
        {
            try std.testing.expect(try store.exists(name));
        }
        {
            const retrieved_item_alloc = (try store.getAlloc(std.testing.allocator, name)).?;
            defer std.testing.allocator.free(retrieved_item_alloc);
            try std.testing.expectEqualStrings(item, retrieved_item_alloc);
        }
        {
            var retrieved_item: [item.len]u8 = undefined;
            try std.testing.expectEqual(item.len, (try store.get(name, &retrieved_item)).?);
            try std.testing.expectEqualStrings(item, &retrieved_item);
        }
        {
            const item2 = "item2";
            try store.put(name, item2);
            const retrieved_item = (try store.getAlloc(std.testing.allocator, name)).?;
            defer std.testing.allocator.free(retrieved_item);
            try std.testing.expectEqualStrings(item2, retrieved_item);
        }
        {
            try store.remove(name);
            try std.testing.expect(try store.getAlloc(std.testing.allocator, name) == null);
            try std.testing.expectEqual(null, try store.get(name, &[0]u8{}));
            try std.testing.expect(!try store.exists(name));
        }
    }
    {
        const item = "long item";
        store.max_item_size = item.len - 1;
        const name = "name";
        try std.testing.expectError(StoreError.ItemTooLarge, store.put(name, item));
        store.max_item_size = item.len;
        try store.put(name, item);
        store.max_item_size = item.len - 1;
        try std.testing.expectError(StoreError.ItemTooLarge, store.getAlloc(std.testing.allocator, name));
    }
}
