const std = @import("std");
const Store = @import("Store.zig");
const cmd = @import("cmd.zig");

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
    var store = Store{ .directory = store_dir };

    switch (operation.op_type) {
        .get => {
            if (try store.getAlloc(allocator, operation.name)) |value| {
                defer allocator.free(value);
                std.debug.print("{s}\n", .{value});
            } else {
                std.debug.print("Item not found\n", .{});
            }
        },
        .put => {
            try store.put(operation.name, operation.value.?);
        },
        .remove => {
            try store.remove(operation.name);
        },
        .exists => {
            const exists = try store.exists(operation.name);
            std.debug.print("{}\n", .{exists});
        },
    }
}
