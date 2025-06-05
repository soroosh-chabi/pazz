const std = @import("std");

const Self = @This();
const cipher = std.crypto.stream.chacha.ChaCha20With64BitNonce;
Prng: std.Random = undefined,
Key: [cipher.key_length]u8 = undefined,

pub fn init(key: [cipher.key_length]u8) Self {
    var xoshiro_prng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    return .{ .Prng = xoshiro_prng.random(), .Key = key };
}

pub fn encrypt(self: Self, src: std.io.AnyReader, dst: std.io.AnyWriter) !void {
    var nonce: [cipher.nonce_length]u8 = undefined;
    self.Prng.bytes(&nonce);
    try dst.writeAll(&nonce);
    try self.transform(src, dst, nonce);
}

pub fn decrypt(self: Self, src: std.io.AnyReader, dst: std.io.AnyWriter) !void {
    var nonce: [cipher.nonce_length]u8 = undefined;
    try src.readNoEof(&nonce);
    try self.transform(src, dst, nonce);
}

fn transform(self: Self, src: std.io.AnyReader, dst: std.io.AnyWriter, nonce: [cipher.nonce_length]u8) !void {
    var src_buffer: [cipher.block_length]u8 = undefined;
    var dst_buffer: [cipher.block_length]u8 = undefined;
    var i: usize = cipher.block_length;
    var counter: u64 = 0;
    while (i == cipher.block_length) : (counter += 1) {
        i = try src.readAll(&src_buffer);
        cipher.xor(dst_buffer[0..i], src_buffer[0..i], counter, self.Key, nonce);
        try dst.writeAll(dst_buffer[0..i]);
    }
}

test "blackbox" {
    var plain_buffer = std.io.fixedBufferStream("hello" ** 60);
    var cipher_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer cipher_buffer.deinit();
    var decrypted_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer decrypted_buffer.deinit();
    const key = [1]u8{0} ** cipher.key_length;
    const crypto = init(key);
    try crypto.encrypt(plain_buffer.reader().any(), cipher_buffer.writer().any());
    var cipher_buffer_stream = std.io.fixedBufferStream(cipher_buffer.items);
    try crypto.decrypt(cipher_buffer_stream.reader().any(), decrypted_buffer.writer().any());
    try std.testing.expectEqualStrings(plain_buffer.buffer, decrypted_buffer.items);
}
