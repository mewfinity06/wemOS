const std = @import("std");
const wemVM = @import("wemVM");

const Inst = @import("bytecode/instruction.zig").Inst;
const Machine = @import("machine.zig");

const Token = @import("token.zig").Token;

const isWhitespace = std.ascii.isWhitespace;
const parseInt = std.fmt.parseInt;
const eql = std.mem.eql;
const split = std.mem.splitAny;
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const trim = std.mem.trim;

machine: *Machine,
allocator: std.mem.Allocator,

content: []u8 = undefined,
cur: usize = 0,
pc: u8 = 0,

// flags
in_string: bool = false,
in_data_section: bool = false,

const Self = @This();

/// Creates a new lexer.
pub fn new(machine: *Machine, content: []u8) Self {
    return .{
        .machine = machine,
        .allocator = machine.allocator,
        .content = content,
    };
}

/// Deinitializes the lexer.
pub fn deinit(_: *Self) void {}

/// The main tokenizing function. It handles both instructions and data.
/// Returns the next token.
pub fn next(self: *Self) !?Token {
    defer self.pc += 1;
    errdefer self.machine.deinit();

    // Check if we are already in the data section
    if (self.in_data_section) {
        return self.data();
    }

    // Skip any leading whitespace and commas
    while (self.cur < self.content.len and (isWhitespace(self.content[self.cur]) or self.content[self.cur] == ',')) {
        self.cur += 1;
    }

    if (self.cur >= self.content.len) {
        return null;
    }

    // Handle instruction tokens
    var buffer: [256]u8 = .{0} ** 256;
    var i: usize = 0;

    while (self.cur < self.content.len and !isWhitespace(self.content[self.cur]) and self.content[self.cur] != ',') {
        buffer[i] = self.content[self.cur];
        self.cur += 1;
        i += 1;
    }

    if (i == 0) return null;

    // insts
    if (eql(u8, buffer[0..i], "halt")) return Token{ .instruction = Inst.halt };
    if (eql(u8, buffer[0..i], "nop")) return Token{ .instruction = Inst.nop };
    if (eql(u8, buffer[0..i], "push")) return Token{ .instruction = Inst.push };
    if (eql(u8, buffer[0..i], "pushr")) return Token{ .instruction = Inst.pushr };
    if (eql(u8, buffer[0..i], "pop")) return Token{ .instruction = Inst.pop };
    if (eql(u8, buffer[0..i], "popr")) return Token{ .instruction = Inst.popr };

    if (eql(u8, buffer[0..i], "add")) return Token{ .instruction = Inst.add };
    if (eql(u8, buffer[0..i], "sub")) return Token{ .instruction = Inst.sub };
    if (eql(u8, buffer[0..i], "mul")) return Token{ .instruction = Inst.mul };
    if (eql(u8, buffer[0..i], "div")) return Token{ .instruction = Inst.div };

    if (eql(u8, buffer[0..i], "mov")) return Token{ .instruction = Inst.mov };
    if (eql(u8, buffer[0..i], "set")) return Token{ .instruction = Inst.set };
    if (eql(u8, buffer[0..i], "syscall")) return Token{ .instruction = Inst.syscall };
    if (eql(u8, buffer[0..i], "goto")) return Token{ .instruction = Inst.goto };

    // general purpose registers
    if (eql(u8, buffer[0..i], "r0")) return Token{ .register = 0x10 };
    if (eql(u8, buffer[0..i], "r1")) return Token{ .register = 0x11 };
    if (eql(u8, buffer[0..i], "r2")) return Token{ .register = 0x12 };
    if (eql(u8, buffer[0..i], "r3")) return Token{ .register = 0x13 };

    // special purpose registers
    if (eql(u8, buffer[0..i], "rpop")) return Token{ .register = 0x20 };
    if (eql(u8, buffer[0..i], "rmath")) return Token{ .register = 0x21 };
    if (eql(u8, buffer[0..i], "rret")) return Token{ .register = 0x22 };
    if (eql(u8, buffer[0..i], "rflag")) return Token{ .register = 0x23 };

    // get label decls
    if (endsWith(u8, buffer[0..i], ":")) {
        // try wemVM.debug("Label decl: {s}, i: {}\n", .{ buffer[0..i], i });

        const label_buffer = try self.allocator.alloc(u8, i);
        for (label_buffer[0..i], buffer[0..i]) |*d, s| d.* = s;

        return Token{ .label_definition = .{ label_buffer, null } };
    }

    // get label call
    if (startsWith(u8, buffer[0..i], ":")) {
        // try wemVM.debug("Label call: {s}, i: {}\n", .{ buffer[0..i], i });

        const label_buffer = try self.allocator.alloc(u8, i);
        for (label_buffer[0..i], buffer[0..i]) |*d, s| d.* = s;

        return Token{ .label_reference = .{ label_buffer, null } };
    }

    // Get section
    if (eql(u8, buffer[0..i], ".section")) {
        self.cur += 1;
        i = 0;
        while (self.cur < self.content.len and !isWhitespace(self.content[self.cur]) and self.content[self.cur] != ',') {
            buffer[i] = self.content[self.cur];
            self.cur += 1;
            i += 1;
        }
        const sp = i;
        while (i < buffer.len) : (i += 1) buffer[i] = 0;
        i = sp;
        while (self.cur < self.content.len and !isWhitespace(self.content[self.cur])) {
            self.cur += 1;
        }
        if (eql(u8, buffer[0..i], "data")) {
            self.in_data_section = true;
            return self.data();
        } else if (eql(u8, buffer[0..i], "executable")) {
            self.in_data_section = false;
            return self.next();
        } else {
            try wemVM.err("Incompatible header section `{s}`\n", .{buffer[0..i]});
            return null;
        }
    }

    // hex
    if (startsWith(u8, buffer[0..i], "0x"))
        return Token{ .literal = try parseInt(u8, buffer[2..i], 16) };

    // binary
    if (startsWith(u8, buffer[0..i], "0b"))
        return Token{ .literal = try parseInt(u8, buffer[2..i], 2) };

    // ints
    if (isInteger(buffer[0..i]))
        return Token{ .literal = try parseInt(u8, buffer[0..i], 10) };

    try wemVM.err("Unhandled token: `{s}`\n", .{buffer[0..i]});
    return error.UnhandledToken;
}

/// Parses the data section of the file.
pub fn data(self: *Self) !?Token {
    if (self.cur >= self.content.len) return null;

    if (self.in_string) {
        if (self.content[self.cur] == '"') {
            self.in_string = false;
            self.cur += 1;
            return self.data();
        }

        const char_byte = self.content[self.cur];
        self.cur += 1;
        return Token{ .literal = char_byte };
    }

    while (self.cur < self.content.len and isWhitespace(self.content[self.cur])) {
        self.cur += 1;
    }

    if (self.cur >= self.content.len) return null;

    if (self.content[self.cur] == '"') {
        self.in_string = true;
        self.cur += 1;
        return self.data();
    }

    var buffer: [256]u8 = .{0} ** 256;
    var i: usize = 0;

    while (self.cur < self.content.len and self.content[self.cur] != '"' and self.content[self.cur] != ',') : ({
        self.cur += 1;
        i += 1;
    }) {
        if (isWhitespace(self.content[self.cur])) break;
        buffer[i] = self.content[self.cur];
    }

    // Check if the loop terminated because of a comma
    if (self.cur < self.content.len and self.content[self.cur] == ',') {
        self.cur += 1; // Consume the comma
    }

    if (i == 0) return self.data();

    const value = buffer[0..i];

    // hex
    if (startsWith(u8, value, "0x"))
        return Token{ .literal = try parseInt(u8, buffer[2..i], 16) };

    // binary
    if (startsWith(u8, value, "0b"))
        return Token{ .literal = try parseInt(u8, buffer[2..i], 2) };

    // // ints
    if (isInteger(buffer[0..i]))
        return Token{ .literal = try parseInt(u8, buffer[0..i], 10) };

    return null;
}

/// Checks if a string is an integer.
fn isInteger(str: []const u8) bool {
    _ = parseInt(u8, str, 10) catch return false;
    return true;
}
