const std = @import("std");
const Store = @import("Store.zig");
const EncryptedStore = @import("EncryptedStore.zig");
const cmd = @import("cmd.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    const operation = try cmd.Operation.parse(&args);

    // Open store directory in user's home
    var store_dir = try cmd.getStoreDir(allocator);
    defer store_dir.close();
    const store = Store{ .directory = store_dir };
    var enc_store = EncryptedStore{ .store = store };

    // Get password from stdin
    const password = try cmd.readPassword(allocator);
    defer allocator.free(password);

    // Check if store is initialized
    if (!try enc_store.initialized()) {
        try enc_store.initialize(password);
        std.debug.print("Store initialized successfully\n", .{});
    }

    // Unlock the store
    enc_store.unlock(password) catch |err| {
        std.debug.print("Failed to unlock store: {}\n", .{err});
        return;
    };

    switch (operation.op_type) {
        .get => {
            if (try enc_store.get(allocator, operation.name)) |value| {
                defer allocator.free(value);
                std.debug.print("{s}\n", .{value});
            } else {
                std.debug.print("Item not found\n", .{});
            }
        },
        .put => {
            if (operation.value == null) {
                std.debug.print("Value required for put operation\n", .{});
                return;
            }
            try enc_store.put(allocator, operation.name, operation.value.?);
        },
        .remove => {
            try enc_store.remove(operation.name);
        },
        .exists => {
            const exists = try enc_store.exists(operation.name);
            std.debug.print("{}\n", .{exists});
        },
        .import => {
            @panic("Not implemented");
        },
    }
}
