const std = @import("std");
const wemVM = @import("wemVM");
const Inst = @import("bytecode/instruction.zig").Inst;
const Machine = @import("machine.zig");

const isWhitespace = std.ascii.isWhitespace;
const parseInt = std.fmt.parseInt;
const eql = std.mem.eql;
const split = std.mem.splitAny;
const startsWith = std.mem.startsWith;
const trim = std.mem.trim;

machine: *Machine,

content: []u8 = undefined,
cur: usize = 0,

// flags
in_string: bool = false,
in_data_section: bool = false,

const Self = @This();

/// Creates a new lexer.
pub fn new(machine: *Machine, content: []u8) Self {
    return .{ .machine = machine, .content = content };
}

/// Deinitializes the lexer.
pub fn deinit(self: *Self) void {
    self.allocator.free(self.data);
}

// The main tokenizing function. It handles both instructions and data.
/// Returns the next token.
pub fn next(self: *Self) !?u8 {
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
    if (eql(u8, buffer[0..i], "halt")) return Inst.halt.to_u8();
    if (eql(u8, buffer[0..i], "nop")) return Inst.nop.to_u8();
    if (eql(u8, buffer[0..i], "push")) return Inst.push.to_u8();
    if (eql(u8, buffer[0..i], "pushr")) return Inst.pushr.to_u8();
    if (eql(u8, buffer[0..i], "pop")) return Inst.pop.to_u8();
    if (eql(u8, buffer[0..i], "popr")) return Inst.popr.to_u8();

    if (eql(u8, buffer[0..i], "add")) return Inst.add.to_u8();
    if (eql(u8, buffer[0..i], "sub")) return Inst.sub.to_u8();
    if (eql(u8, buffer[0..i], "mul")) return Inst.mul.to_u8();
    if (eql(u8, buffer[0..i], "div")) return Inst.div.to_u8();

    if (eql(u8, buffer[0..i], "mov")) return Inst.mov.to_u8();
    if (eql(u8, buffer[0..i], "set")) return Inst.set.to_u8();
    if (eql(u8, buffer[0..i], "syscall")) return Inst.syscall.to_u8();

    // general purpose registers
    if (eql(u8, buffer[0..i], "r0")) return 0x10;
    if (eql(u8, buffer[0..i], "r1")) return 0x11;
    if (eql(u8, buffer[0..i], "r2")) return 0x12;
    if (eql(u8, buffer[0..i], "r3")) return 0x13;

    // special purpose registers
    if (eql(u8, buffer[0..i], "rpop")) return 0x20;
    if (eql(u8, buffer[0..i], "rmath")) return 0x21;
    if (eql(u8, buffer[0..i], "rret")) return 0x22;
    if (eql(u8, buffer[0..i], "rflag")) return 0x23;

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
        } else {
            try wemVM.err("Incompatible header section `{s}`\n", .{buffer});
            return null;
        }
    }

    // hex
    if (startsWith(u8, buffer[0..i], "0x"))
        return try parseInt(u8, buffer[2..i], 16);

    // binary
    if (startsWith(u8, buffer[0..i], "0b"))
        return try parseInt(u8, buffer[2..i], 2);

    // ints
    if (isInteger(buffer[0..i]))
        return try parseInt(u8, buffer[0..i], 10);

    try wemVM.err("Unhandled token: `{s}`\n", .{buffer[0..i]});
    return null;
}

/// Parses the data section of the file.
pub fn data(self: *Self) !?u8 {
    if (self.cur >= self.content.len) return null;

    if (self.in_string) {
        if (self.content[self.cur] == '"') {
            self.in_string = false;
            self.cur += 1;
            return self.data();
        }

        const char_byte = self.content[self.cur];
        self.cur += 1;
        return char_byte;
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
        return try parseInt(u8, value[2..], 16);

    // binary
    if (startsWith(u8, value, "0b"))
        return try parseInt(u8, value[2..], 2);

    // ints
    return try parseInt(u8, value, 10);
}

/// Checks if a string is an integer.
fn isInteger(str: []const u8) bool {
    _ = parseInt(u8, str, 10) catch return false;
    return true;
}
