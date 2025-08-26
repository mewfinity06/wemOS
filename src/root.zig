const std = @import("std");

const ESC: []const u8 = "\x1b[";
const ERROR: []const u8 = ESC ++ "91m" ++ ESC ++ "100m";
const INFO: []const u8 = ESC ++ "92m" ++ ESC ++ "100m";
const DEBUG: []const u8 = ESC ++ "94m" ++ ESC ++ "100m";
const RESET: []const u8 = ESC ++ "0m";

/// Prints the usage of the program.
pub fn usage() !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &writer.interface;

    try stderr.print("{s}[USAGE]{s} wemVM <FILE>\n", .{ INFO, RESET });
    try stderr.flush();
}

/// Prints a seperator.
pub fn seperator() void {
    std.debug.print("--------------------------------------\n", .{});
}

/// Prints an error message.
pub fn err(comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &writer.interface;

    try stderr.print("{s}[ERROR]{s} ", .{ ERROR, RESET });
    try stderr.print(fmt, args);
    try stderr.flush();
}

/// Prints an info message.
pub fn info(comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &writer.interface;

    try stderr.print("{s}[INFO]{s} ", .{ INFO, RESET });
    try stderr.print(fmt, args);
    try stderr.flush();
}

/// Prints a debug message.
pub fn debug(comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &writer.interface;

    try stderr.print("{s}[DEBUG]{s} ", .{ DEBUG, RESET });
    try stderr.print(fmt, args);
    try stderr.flush();
}
