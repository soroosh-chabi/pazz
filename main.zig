const std = @import("std");
const Store = @import("Store.zig");
const EncryptedStore = @import("EncryptedStore.zig");
const cmd = @import("cmd.zig");
const tcgetattr = std.os.linux.tcgetattr;
const tcsetattr = std.os.linux.tcsetattr;

fn getStoreDir(allocator: std.mem.Allocator) !std.fs.Dir {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
        std.debug.print("Error: Could not get HOME directory: {}\n", .{err});
        return error.HomeDirNotFound;
    };
    defer allocator.free(home);

    const store_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".pazz" });
    defer allocator.free(store_path);

    // Try to open the directory first
    if (std.fs.openDirAbsolute(store_path, .{})) |dir| {
        return dir;
    } else |err| switch (err) {
        error.FileNotFound => {
            // Create the directory if it doesn't exist
            try std.fs.makeDirAbsolute(store_path);
            return try std.fs.openDirAbsolute(store_path, .{});
        },
        else => return err,
    }
}

fn readPassword(allocator: std.mem.Allocator) ![]const u8 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Enter password: ", .{});

    // Save current terminal settings
    var original_termios: std.os.linux.termios = undefined;
    _ = tcgetattr(std.io.getStdIn().handle, &original_termios);
    var new_termios = original_termios;
    new_termios.lflag.ECHO = false;
    _ = tcsetattr(std.io.getStdIn().handle, std.os.linux.TCSA.FLUSH, &new_termios);
    defer _ = tcsetattr(std.io.getStdIn().handle, std.os.linux.TCSA.FLUSH, &original_termios);

    var password = std.ArrayList(u8).init(allocator);
    defer password.deinit();

    while (true) {
        const byte = stdin.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (byte == '\n') break;
        try password.append(byte);
    }

    try stdout.writeByte('\n');
    return password.toOwnedSlice();
}

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
    var store_dir = try getStoreDir(allocator);
    defer store_dir.close();
    const store = Store{ .directory = store_dir };
    var enc_store = EncryptedStore{ .store = store };

    // Get password from stdin
    const password = try readPassword(allocator);
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
    }
}
