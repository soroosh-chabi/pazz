const std = @import("std");

pub const overhead = cipher.nonce_length;
pub const key_metadata_length = salt_length + overhead + correct_password.len;
pub const KeyLoadError = error{
    WrongPassword,
};
const cipher = std.crypto.stream.chacha.ChaCha20With64BitNonce;
const correct_password = "correct password";
const salt_length = 64;
key: [cipher.key_length]u8 = undefined,

/// `dst` must be bigger than `src` by `overhead`
pub fn encrypt(self: @This(), src: []const u8, dst: []u8) void {
    var nonce: [cipher.nonce_length]u8 = undefined;
    std.crypto.random.bytes(&nonce);
    @memcpy(dst[0..overhead], &nonce);
    cipher.xor(dst[overhead..], src, 0, self.key, nonce);
}

/// `src` must be bigger than `dst` by `overhead`
pub fn decrypt(self: @This(), src: []const u8, dst: []u8) void {
    var nonce: [cipher.nonce_length]u8 = undefined;
    @memcpy(&nonce, src[0..overhead]);
    cipher.xor(dst, src[overhead..], 0, self.key, nonce);
}

pub fn loadKeyMetadata(self: *@This(), password: []const u8, key_metadata: [key_metadata_length]u8) KeyLoadError!void {
    self.setKey(password, key_metadata[0..salt_length]);
    var decrypted_metadata: [correct_password.len]u8 = undefined;
    self.decrypt(key_metadata[salt_length..], &decrypted_metadata);
    if (!std.mem.eql(u8, &decrypted_metadata, correct_password)) {
        return KeyLoadError.WrongPassword;
    }
}

/// `key_metadata` should be `key_metadata_length` long
pub fn generateKeyMetadata(self: *@This(), password: []const u8, key_metadata: *[key_metadata_length]u8) void {
    const salt = key_metadata[0..salt_length];
    std.crypto.random.bytes(salt);
    self.setKey(password, salt);
    self.encrypt(correct_password, key_metadata[salt_length..]);
}

fn setKey(self: *@This(), password: []const u8, salt: []const u8) void {
    const prk = std.crypto.kdf.hkdf.HkdfSha512.extract(salt, password);
    std.crypto.kdf.hkdf.HkdfSha512.expand(&self.key, &[0]u8{}, prk);
}

test "generate, encrypt and decrypt correctly" {
    const plain_buffer = "hello";
    var cipher_buffer: [plain_buffer.len + overhead]u8 = undefined;
    var decrypted_buffer: [plain_buffer.len]u8 = undefined;
    var crypto = @This(){};
    var key_metadata: [key_metadata_length]u8 = undefined;
    crypto.generateKeyMetadata("mousy", &key_metadata);
    crypto.encrypt(plain_buffer, &cipher_buffer);
    crypto.decrypt(&cipher_buffer, &decrypted_buffer);
    try std.testing.expectEqualStrings(plain_buffer, &decrypted_buffer);
}

test "generate and load key metadata correctly" {
    var key_metadata: [key_metadata_length]u8 = undefined;
    var enc_gen = @This(){};
    enc_gen.generateKeyMetadata("mousy", &key_metadata);
    const plain_buffer = "hello";
    var cipher_buffer: [plain_buffer.len + overhead]u8 = undefined;
    enc_gen.encrypt(plain_buffer, &cipher_buffer);
    var enc_load = @This(){};
    try enc_load.loadKeyMetadata("mousy", key_metadata);
    var decrypted_buffer: [plain_buffer.len]u8 = undefined;
    enc_load.decrypt(&cipher_buffer, &decrypted_buffer);
    try std.testing.expectEqualStrings(plain_buffer, &decrypted_buffer);
}

test "load wrong key metadata" {
    var key_metadata: [key_metadata_length]u8 = undefined;
    var enc_gen = @This(){};
    enc_gen.generateKeyMetadata("mousy", &key_metadata);
    var enc_load = @This(){};
    try std.testing.expectError(KeyLoadError.WrongPassword, enc_load.loadKeyMetadata("catty", key_metadata));
}
