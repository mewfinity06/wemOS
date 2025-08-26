
# Documentation

This document provides automatically generated documentation for the functions in the `src` directory.

## `src/bytecode/instruction.zig`

### `to_u8(i: Inst) u8`

Converts an `Inst` enum to its `u8` representation.

### `u8_to_inst(n: u8) !Inst`

Converts a `u8` to its `Inst` enum representation.

## `src/bytecode/syscall.zig`

### `Syscall(sys: u8, args: []const u8, args_count: usize, execute: *const fn (self: Call, machine: *Machine) CallError!void) Call`

Creates a new `Call` struct.

### `write(self: Call, machine: *Machine) CallError!void`

Handles the `write` syscall.

## `src/lexer.zig`

### `new(machine: *Machine, content: []u8) Self`

Creates a new `Lexer`.

### `deinit(self: *Self) void`

Deinitializes the `Lexer`.

### `next(self: *Self) !?u8`

Returns the next token from the input.

### `data(self: *Self) !?u8`

Handles tokenizing data sections.

### `isInteger(str: []const u8) bool`

Checks if a string is an integer.

## `src/machine.zig`

### `from_file(allocator: std.mem.Allocator, file_path: []const u8) !Self`

Creates a new `Machine` from a file.

### `deinit(self: *Self) void`

Deinitializes the `Machine`.

### `print(self: *Self) !void`

Prints the current state of the `Machine`.

### `display(self: *Self) !void`

Displays the program and data in the `Machine`.

### `step(self: *Self) !bool`

Executes the next instruction in the `Machine`.

### `run(self: *Self) !void`

Runs the program in the `Machine`.

### `u8_to_reg_name(v: u8) []const u8`

Converts a register's `u8` representation to its name.

### `u8_to_reg_value(self: *Self, v: u8) u8`

Gets the value of a register from its `u8` representation.

### `u8_to_reg_pointer(self: *Self, v: u8) *u8`

Gets a pointer to a register from its `u8` representation.

## `src/main.zig`

### `main() !void`

The entry point of the application.

## `src/root.zig`

### `usage() !void`

Prints the usage information.

### `seperator() void`

Prints a separator line.

### `err(comptime fmt: []const u8, args: anytype) !void`

Prints an error message.

### `info(comptime fmt: []const u8, args: anytype) !void`

Prints an info message.

### `debug(comptime fmt: []const u8, args: anytype) !void`

Prints a debug message.
