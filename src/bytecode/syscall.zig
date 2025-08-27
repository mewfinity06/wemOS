const std = @import("std");
const wemVM = @import("wemVM");

const Machine = @import("../machine.zig");

// |--------------------------------------|
// |            SYSCALL TABLE             |
// |--------------------------------------|
// | syscall # | r0 | r1 |    r2   |  r3  | Notes:
// |--------------------------------------|
// | write (0) | 0  | fd | *buffer | size | fd(0) -> stdout, fd(1) -> stderr
// |--------------------------------------|

/// Represents an error that can occur during a syscall.
pub const CallError = error{
    InvalidCall,
    InvalidArg,
} || std.fs.File.WriteError;

/// Represents a syscall.
pub const Call = struct {
    sys: u8,
    args: []const u8,
    args_count: usize,
    execute: *const fn (self: Call, machine: *Machine) CallError!void,
};

/// Creates a new syscall.
pub fn Syscall(
    sys: u8,
    args: []const u8,
    args_count: usize,
    execute: *const fn (self: Call, machine: *Machine) CallError!void,
) Call {
    return .{
        .sys = sys,
        .args = args,
        .args_count = args_count,
        .execute = execute,
    };
}

/// The `write` syscall.
pub fn write(self: Call, machine: *Machine) CallError!void {
    // check if write call
    if (self.sys != 0x0) return error.InvalidCall;
    const fd = self.args[0];
    const bf = self.args[1];
    const size = self.args[2];

    const file = switch (fd) {
        0x0 => std.fs.File.stdout(),
        0x1 => std.fs.File.stderr(),
        else => @panic("Unhandled file descriptor"),
    };

    var buffer: [1024]u8 = undefined;

    for (machine.data.items[bf .. bf + size], 0..) |t, i| {
        buffer[i] = t.literal;
    }

    // wemVM.debug("Write buffer: {any}\n", .{buffer}) catch {};

    _ = try file.write(&buffer);
}
