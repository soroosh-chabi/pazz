const std = @import("std");

const Crypto = @This();
const cipher = std.crypto.stream.chacha.ChaCha20With64BitNonce;
pub const key_length = cipher.key_length;
pub const overhead = cipher.nonce_length;
key: [key_length]u8,

pub fn init(key: [key_length]u8) Crypto {
    return .{ .key = key };
}

/// `dst` must be bigger than `src` by `overhead`
pub fn encrypt(self: Crypto, src: []const u8, dst: []u8) void {
    var nonce: [cipher.nonce_length]u8 = undefined;
    std.crypto.random.bytes(&nonce);
    @memcpy(dst[0..overhead], &nonce);
    cipher.xor(dst[overhead..], src, 0, self.key, nonce);
}

/// `src` must be bigger than `dst` by `overhead`
pub fn decrypt(self: Crypto, src: []const u8, dst: []u8) void {
    var nonce: [cipher.nonce_length]u8 = undefined;
    @memcpy(&nonce, src[0..overhead]);
    cipher.xor(dst, src[overhead..], 0, self.key, nonce);
}

test "blackbox" {
    const plain_buffer = "hello" ** 60;
    var cipher_buffer: [plain_buffer.len + Crypto.overhead]u8 = undefined;
    var decrypted_buffer: [plain_buffer.len]u8 = undefined;
    const key = [1]u8{0} ** Crypto.key_length;
    var crypto = init(key);
    crypto.encrypt(plain_buffer, &cipher_buffer);
    crypto.decrypt(&cipher_buffer, &decrypted_buffer);
    try std.testing.expectEqualStrings(plain_buffer, &decrypted_buffer);
}
