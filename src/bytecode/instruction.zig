/// Represents a single instruction in the wemVM.
pub const Inst = enum {
    halt, //  0x0,  halt
    nop, //   0x1,  nop
    push, //  0x2,  push  <u8>  -> stack
    pushr, // 0x21, pushr <reg> -> stack
    pop, //   0x3,  pop         -> rpop
    popr, //  0x31, popr  <reg> -> rpop

    add, // 0x40, add -> rmath
    sub, // 0x41, sub -> rmath
    mul, // 0x42, mul -> rmath
    div, // 0x43, div -> rmath

    mov, //     0x50, mov <src> <dest>
    set, //     0x51, set <reg> <u8>
    syscall, // 0x52, syscall

    ignore,

    /// Converts an instruction to its byte representation.
    pub fn to_u8(i: Inst) u8 {
        return @intFromEnum(i);
    }
};

/// Converts a byte to its instruction representation.
pub fn u8_to_inst(n: u8) !Inst {
    return @enumFromInt(n);
}
