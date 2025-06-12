const std = @import("std");

pub const OperationType = enum {
    get,
    put,
    remove,
    exists,
    import,
    fn parseOperation(operation: []const u8) !OperationType {
        if (std.mem.eql(u8, operation, "get")) return .get;
        if (std.mem.eql(u8, operation, "put")) return .put;
        if (std.mem.eql(u8, operation, "remove")) return .remove;
        if (std.mem.eql(u8, operation, "exists")) return .exists;
        if (std.mem.eql(u8, operation, "import")) return .import;
        return error.InvalidOperation;
    }
};

pub const Operation = struct {
    op_type: OperationType,
    name: []const u8,
    value: ?[]const u8,

    pub fn parse(args: *std.process.ArgIterator) !Operation {
        const operation_str = args.next() orelse {
            std.debug.print("Usage: pazz <operation> <name> [value]\n", .{});
            std.debug.print("Operations: get, put, remove, exists, import\n", .{});
            return error.MissingOperation;
        };
        const op_type = try OperationType.parseOperation(operation_str);

        var name: []const u8 = "";
        var value: ?[]const u8 = null;

        if (op_type != .import) {
            name = args.next() orelse {
                std.debug.print("Error: Missing name argument\n", .{});
                return error.MissingName;
            };

            if (op_type == .put) {
                value = args.next() orelse {
                    std.debug.print("Error: Missing value argument for put operation\n", .{});
                    return error.MissingValue;
                };
            }
        }

        return Operation{
            .op_type = op_type,
            .name = name,
            .value = value,
        };
    }
};

pub fn readPassword(allocator: std.mem.Allocator) ![]const u8 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Enter password: ", .{});

    // Save current terminal settings
    var original_termios: std.os.linux.termios = undefined;
    _ = std.os.linux.tcgetattr(std.io.getStdIn().handle, &original_termios);
    var new_termios = original_termios;
    new_termios.lflag.ECHO = false;
    _ = std.os.linux.tcsetattr(std.io.getStdIn().handle, std.os.linux.TCSA.FLUSH, &new_termios);
    defer _ = std.os.linux.tcsetattr(std.io.getStdIn().handle, std.os.linux.TCSA.FLUSH, &original_termios);

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

pub fn getStoreDir(allocator: std.mem.Allocator) !std.fs.Dir {
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
