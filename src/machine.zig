const std = @import("std");
const wemVM = @import("wemVM");

const inst = @import("bytecode/instruction.zig");
const Inst = inst.Inst;
const u8_to_inst = inst.u8_to_inst;

const Lexer = @import("lexer.zig");

allocator: std.mem.Allocator,

pc: usize = 0,
program: std.ArrayList(u8) = undefined,

sp: usize = 0,
stack: [STACK_SIZE]u8 = .{0} ** STACK_SIZE,

gpr: [GPR_SIZE]u8 = .{0} ** GPR_SIZE,
rpop: u8 = 0,
rmath: u8 = 0,
rret: u8 = 0,
rflag: u8 = 0,

data: std.ArrayList(u8) = undefined,

pub const STACK_SIZE: usize = 8;
pub const GPR_SIZE: usize = 4;

const Self = @This();

pub fn from_file(allocator: std.mem.Allocator, file_path: []const u8) !Self {
    var res = .{
        .allocator = allocator,
        .program = try std.ArrayList(u8).initCapacity(allocator, 100),
        .data = try std.ArrayList(u8).initCapacity(allocator, 100),
    };

    const content = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    defer allocator.free(content);

    var l = Lexer.new(&res, content);

    while (try l.next()) |t| {
        if (l.in_data_section) {
            try res.data.append(res.allocator, t);
        } else {
            try res.program.append(res.allocator, t);
        }
    }

    return res;
}

pub fn deinit(self: *Self) void {
    self.program.deinit(self.allocator);
    self.data.deinit(self.allocator);
}

pub fn print(self: *Self) !void {
    try wemVM.info("Self {{\n", .{});
    defer std.debug.print("}}\n", .{});

    // Stack
    if (self.sp > 0) {
        std.debug.print("   stack: {{\n", .{});
        defer std.debug.print("   }}\n", .{});
        for (0..self.sp) |i| {
            std.debug.print("      sp: 0x{X} -> 0x{X}\n", .{ i, self.stack[i] });
        }
    } else {
        std.debug.print("   stack: {{}}\n", .{});
    }

    // Program
    if (self.pc >= self.program_len) {
        std.debug.print("   pc: NULL\n", .{});
    } else {
        std.debug.print("   pc: 0x{X} -> 0x{X} ({any})\n", .{ self.pc, self.program.items[self.pc], u8_to_inst(self.program.items[self.pc]) });
    }
    // Registers
    std.debug.print("   General Purpose Registers:\n", .{});
    for (0..Self.GPR_SIZE) |i| {
        std.debug.print("      r{} (0x{X}) => 0x{X}\n", .{ i, i + 0x10, self.gpr[i] });
    }
    std.debug.print("   Special Purpose Registers:\n", .{});
    std.debug.print("      pop => 0x{X}, math  => 0x{X}\n", .{ self.rpop, self.rmath });
    std.debug.print("      ret => 0x{X}, flags => 0x{X}\n", .{ self.rret, self.rflag });

    // Data
    if (self.text_data.items.len > 0) {
        std.debug.print("   Data\n", .{});
        var i: usize = 0;
        for (self.text_data.items) |text| {
            std.debug.print("      - \"{s}\"", .{text});
            if (i % 8 == 0) std.debug.print("\n", .{});
            i += 1;
        }
    }
}

pub fn display(self: *Self) !void {
    try wemVM.info("Program {{\n", .{});
    var i: usize = 0;
    while (i < self.program.items.len) : (i += 1) {
        std.debug.print("(0x{X})\t", .{i});
        defer std.debug.print("\n", .{});
        switch (try u8_to_inst(self.program.items[i])) {
            .halt => std.debug.print("halt", .{}),
            .nop => std.debug.print("nop", .{}),
            .push => {
                std.debug.print("push ", .{});
                i += 1;
                const arg = self.program.items[i];
                std.debug.print("<arg: 0x{X}>", .{arg});
            },
            .pop => std.debug.print("pop", .{}),
            .add => std.debug.print("add", .{}),
            .sub => std.debug.print("sub", .{}),
            .mul => std.debug.print("mul", .{}),
            .div => std.debug.print("div", .{}),
            .mov => {
                std.debug.print("mov ", .{});
                i += 1;
                const src = self.program.items[i];
                i += 1;
                const dest = self.program.items[i];
                std.debug.print("<src: 0x{X}>, <dest: 0x{X}>", .{ src, dest });
            },
            else => {
                std.debug.print("\r", .{});
                try wemVM.err("Unhandled inst: 0x{X}", .{self.program.items[i]});
            },
        }
    }
    i = 1;
    std.debug.print("\t.data:\n", .{});
    std.debug.print("\t    {s}\n", .{self.data.items});
    std.debug.print("}}\n", .{});
}

pub fn step(self: *Self) !bool {
    defer self.pc += 1;
    try self.print();
    if (self.pc >= self.program_len) return false;
    switch (try u8_to_inst(self.program.items[self.pc])) {
        .nop => {},
        .push => {
            defer self.sp += 1;
            self.pc += 1;
            self.stack[self.sp] = self.program.items[self.pc];
        },
        .pushr => {
            defer self.sp += 1;
            self.pc += 1;
            const reg = self.program.items[self.pc];
            const reg_v = switch (reg) {
                0x10 => self.gpr[0],
                0x11 => self.gpr[1],
                0x12 => self.gpr[2],
                0x13 => self.gpr[3],
                0x20 => self.rpop,
                0x21 => self.rmath,
                else => @panic("unknown register"),
            };
            self.stack[self.sp] = reg_v;
        },
        .pop => {
            self.sp -= 1;
            self.rpop = self.stack[self.sp];
            self.stack[self.sp] = 0;
        },
        .add => {
            if (self.sp < 1) return error.StackUnderflow;
            const a = self.stack[self.sp - 1];
            self.sp -= 1;
            const b = self.stack[self.sp - 1];
            self.sp -= 1;
            self.rmath = b + a;
        },
        .sub => {
            if (self.sp < 1) return error.StackUnderflow;
            const a = self.stack[self.sp - 1];
            self.sp -= 1;
            const b = self.stack[self.sp - 1];
            self.sp -= 1;
            self.rmath = b - a;
        },
        .mul => {
            if (self.sp < 1) return error.StackUnderflow;
            const a = self.stack[self.sp - 1];
            self.sp -= 1;
            const b = self.stack[self.sp - 1];
            self.sp -= 1;
            self.rmath = b * a;
        },
        .div => {
            if (self.sp < 1) return error.StackUnderflow;
            const a = self.stack[self.sp - 1];
            self.sp -= 1;
            const b = self.stack[self.sp - 1];
            self.sp -= 1;
            self.rmath = b / a;
        },
        .halt => {
            try wemVM.info("Self halted successfully!\n", .{});
            return false;
        },
        .mov => {
            self.pc += 1;
            const src = self.program.items[self.pc];
            self.pc += 1;
            const dest = self.program.items[self.pc];

            const src_r = switch (src) {
                0x10 => self.gpr[0],
                0x11 => self.gpr[1],
                0x12 => self.gpr[2],
                0x13 => self.gpr[3],
                0x20 => self.rpop,
                0x21 => self.rmath,
                else => @panic("unknown register"),
            };

            const dest_r = switch (dest) {
                0x10 => &self.gpr[0],
                0x11 => &self.gpr[1],
                0x12 => &self.gpr[2],
                0x13 => &self.gpr[3],
                0x20 => &self.rpop,
                0x21 => &self.rmath,
                else => @panic("unknown register"),
            };

            dest_r.* = src_r;
        },
        else => {
            try wemVM.err("Unhandled inst: 0x{X}\n", .{self.program.items[self.pc]});
            return false;
        },
    }
    return true;
}

pub fn run(self: *Self) !void {
    while (try self.step()) {}
}
