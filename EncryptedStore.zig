const std = @import("std");
const Store = @import("Store.zig");
const Encryption = @import("Encryption.zig");

const EncryptedStore = @This();

const EncryptedStoreError = error{
    ForbiddenName,
};
const key_metadata_name = ".key";

enc: Encryption = .{},
store: Store,

pub fn initialized(self: EncryptedStore) !bool {
    return try self.store.exists(key_metadata_name);
}

pub fn initialize(self: *EncryptedStore, password: []const u8) !void {
    var key_metadata: [Encryption.key_metadata_length]u8 = undefined;
    self.enc.generateKeyMetadata(password, &key_metadata);
    try self.store.put(key_metadata_name, &key_metadata);
}

pub const UnlockError = error{
    CorruptData,
};

pub fn unlock(self: *EncryptedStore, password: []const u8) !void {
    var key_metadata: [Encryption.key_metadata_length + 1]u8 = undefined;
    if (try self.store.get(key_metadata_name, &key_metadata) != Encryption.key_metadata_length) {
        return UnlockError.CorruptData;
    }
    try self.enc.loadKeyMetadata(password, key_metadata[0..Encryption.key_metadata_length].*);
}

fn validateName(name: []const u8) !void {
    if (std.mem.eql(u8, key_metadata_name, name)) {
        return EncryptedStoreError.ForbiddenName;
    }
}

pub fn put(self: EncryptedStore, allocator: std.mem.Allocator, name: []const u8, item: []const u8) !void {
    try validateName(name);
    const enc_item = try allocator.alloc(u8, item.len + Encryption.overhead);
    defer allocator.free(enc_item);
    self.enc.encrypt(item, enc_item);
    try self.store.put(name, enc_item);
}

/// The returned item is owned by the caller.
pub fn get(self: EncryptedStore, allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    try validateName(name);
    const enc_item = try self.store.getAlloc(allocator, name) orelse return null;
    defer allocator.free(enc_item);
    const item = try allocator.alloc(u8, enc_item.len - Encryption.overhead);
    self.enc.decrypt(enc_item, item);
    return item;
}

pub fn remove(self: EncryptedStore, name: []const u8) !void {
    try validateName(name);
    try self.store.remove(name);
}

pub fn exists(self: EncryptedStore, name: []const u8) !bool {
    try validateName(name);
    return try self.store.exists(name);
}

test EncryptedStore {
    var tmpDir = std.testing.tmpDir(.{});
    defer tmpDir.cleanup();
    const password = "password";
    var enc_store = EncryptedStore{ .store = .{ .directory = tmpDir.dir } };
    try std.testing.expect(!try enc_store.initialized());
    try enc_store.initialize(password);
    try std.testing.expect(try enc_store.initialized());
    try std.testing.expectError(Encryption.KeyLoadError.WrongPassword, enc_store.unlock(password ** 2));
    try enc_store.unlock(password);
}
