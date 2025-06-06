const std = @import("std");
const Crypto = @import("Crypto.zig");

const Store = @This();
const max_password_size: usize = 1_000_000;
allocator: std.mem.Allocator,
crypto: Crypto,
directory: []const u8,

/// `directory` must be absolute. It stores a copy.
pub fn init(allocator: std.mem.Allocator, crypto: Crypto, directory: []const u8) !Store {
    return .{
        .allocator = allocator,
        .crypto = crypto,
        .directory = try allocator.dupe(u8, directory),
    };
}

pub fn deinit(self: Store) void {
    self.allocator.free(self.directory);
}

pub fn put(self: Store, name: []const u8, password: []const u8) !void {
    const encrypted_password = try self.allocator.alloc(u8, password.len + Crypto.overhead);
    defer self.allocator.free(encrypted_password);
    self.crypto.encrypt(password, encrypted_password);
    const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.directory, name });
    defer self.allocator.free(path);
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(encrypted_password);
}

/// The returned password is owned by the caller.
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
    const encrypted_password = try file.readToEndAlloc(self.allocator, max_password_size);
    defer self.allocator.free(encrypted_password);
    const password = try allocator.alloc(u8, encrypted_password.len - Crypto.overhead);
    self.crypto.decrypt(encrypted_password, password);
    return password;
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
    return init(std.testing.allocator, Crypto.init([1]u8{0} ** Crypto.key_length), path);
}

test "put then get" {
    var store = try setupTest();
    defer store.deinit();
    const name = "site";
    const password = "pass";
    try store.put(name, password);
    const retrieved_password = (try store.get(std.testing.allocator, name)).?;
    defer std.testing.allocator.free(retrieved_password);
    try std.testing.expectEqualStrings(password, retrieved_password);
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
    const password = "pass2";
    try store.put(name, "pass1");
    try store.put(name, password);
    const retrieved_password = (try store.get(std.testing.allocator, name)).?;
    defer std.testing.allocator.free(retrieved_password);
    try std.testing.expectEqualStrings(password, retrieved_password);
}

test "put then remove then get" {
    var store = try setupTest();
    defer store.deinit();
    const name = "site";
    const password = "pass";
    try store.put(name, password);
    try store.remove(name);
    try std.testing.expect(try store.get(std.testing.allocator, name) == null);
}
