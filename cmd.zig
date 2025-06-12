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
