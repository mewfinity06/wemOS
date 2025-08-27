const std = @import("std");
const Inst = @import("bytecode/instruction.zig").Inst;

pub const Token = union(enum) {
    instruction: Inst,
    register: u8, // For register operands (r0, r1, etc.)
    literal: u8, // For immediate values (numbers, hex, binary)
    label_definition: struct { []const u8, ?u8 }, // For "label:"
    label_reference: struct { []const u8, ?u8 }, // For ":label" or label in goto
};
