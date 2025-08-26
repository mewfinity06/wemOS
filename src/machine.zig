const std = @import("std");
const wemVM = @import("wemVM");

const inst = @import("bytecode/instruction.zig");
const Inst = inst.Inst;
const u8_to_inst = inst.u8_to_inst;

const syscall = @import("bytecode/syscall.zig");
const Syscall = syscall.Syscall;
const Call = syscall.Call;
const CallFn = syscall.CallFn;
const write = syscall.write;

const Lexer = @import("lexer.zig");

allocator: std.mem.Allocator,

pc: usize = 0,
program: std.ArrayList(u8) = undefined,

sp: usize = 0,
stack: [STACK_SIZE]u8 = .{0} ** STACK_SIZE,

gpr: [GPR_SIZE]u8 = .{0} ** GPR_SIZE,
rpop: u8 = 0, //  0x20
rmath: u8 = 0, // 0x21
rret: u8 = 0, //  0x22
rflag: u8 = 0, // 0x23

data: std.ArrayList(u8) = undefined,

pub const STACK_SIZE: usize = 8;
pub const GPR_SIZE: usize = 4;

const Self = @This();

/// Creates a new machine from a file.
pub fn from_file(allocator: std.mem.Allocator, file_path: []const u8) !Self {
    var res = Self{
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

/// Deinitializes the machine.
pub fn deinit(self: *Self) void {
    self.program.deinit(self.allocator);
    self.data.deinit(self.allocator);
}

/// Prints the machine's state.
pub fn print(self: *Self) !void {
    wemVM.seperator();
    defer wemVM.seperator();
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
    if (self.pc >= self.program.items.len) {
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
    if (self.data.items.len > 0) {
        std.debug.print("   Data\n", .{});
        std.debug.print("    - {s}\n", .{self.data.items});
    }
}

/// Displays the machine's program and data.
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
            .set => {
                std.debug.print("set ", .{});
                i += 1;
                const reg = self.program.items[i];
                i += 1;
                const value = self.program.items[i];
                std.debug.print("<reg: {s}>, <value: 0x{X}>", .{ u8_to_reg_name(reg), value });
            },
            .syscall => std.debug.print("set", .{}),
            .goto => {
                std.debug.print("goto ", .{});
                i += 1;
                const arg = self.program.items[i];
                std.debug.print("<arg: 0x{X}>", .{arg});
            },
            else => {
                std.debug.print("\r", .{});
                try wemVM.err("Unhandled inst: 0x{X}", .{self.program.items[i]});
            },
        }
    }
    std.debug.print("\t.data:\n", .{});
    std.debug.print("\t    data len: {}\n", .{self.data.items.len});
    std.debug.print("\t    {any}\n", .{self.data.items});
    std.debug.print("}}\n", .{});
}

/// Executes a single instruction.
pub fn step(self: *Self) !bool {
    defer self.pc += 1;
    if (self.pc >= self.program.items.len) return false;
    switch (try u8_to_inst(self.program.items[self.pc])) {
        .nop => {},
        .halt => return false,
        .push => {
            defer self.sp += 1;
            self.pc += 1;
            self.stack[self.sp] = self.program.items[self.pc];
        },
        .pushr => {
            defer self.sp += 1;
            self.pc += 1;
            const reg = self.program.items[self.pc];
            const reg_v = self.u8_to_reg_value(reg);
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
        .set => {
            self.pc += 1;
            const reg_lit = self.program.items[self.pc];
            self.pc += 1;

            const reg = self.u8_to_reg_pointer(reg_lit);
            const value = self.program.items[self.pc];

            reg.* = value;
        },
        .mov => {
            self.pc += 1;
            const src = self.program.items[self.pc];
            self.pc += 1;
            const dest = self.program.items[self.pc];

            const src_r = self.u8_to_reg_value(src);
            const dest_r = self.u8_to_reg_pointer(dest);

            dest_r.* = src_r;
        },
        .syscall => {
            var writer = Syscall(0, &.{
                self.gpr[1],
                self.gpr[2],
                self.gpr[3],
            }, 3, write);

            switch (self.gpr[0]) {
                0x0 => try writer.execute(writer, self),
                else => @panic("Invalid syscall #"),
            }
        },
        .goto => {
            self.pc += 1;
            const addr = self.program.items[self.pc];
            self.pc = addr - 1;
        },
        else => {
            try wemVM.err("Unhandled inst: {any} (0x{X})\n", .{
                u8_to_inst(self.program.items[self.pc]),
                self.program.items[self.pc],
            });
            return false;
        },
    }
    return true;
}

/// Runs the machine.
pub fn run(self: *Self) !void {
    while (try self.step()) {}
    self.sp = 0;
    self.pc = 0;
}

/// Converts a register's byte representation to its name.
fn u8_to_reg_name(v: u8) []const u8 {
    return switch (v) {
        0x10 => "r0",
        0x11 => "r1",
        0x12 => "r2",
        0x13 => "r3",
        0x20 => "rpop",
        0x21 => "rmath",
        0x22 => "rret",
        0x23 => "rflag",
        else => @panic("Unknown regster"),
    };
}

/// Converts a register's byte representation to its value.
fn u8_to_reg_value(self: *Self, v: u8) u8 {
    return switch (v) {
        0x10 => self.gpr[0],
        0x11 => self.gpr[1],
        0x12 => self.gpr[2],
        0x13 => self.gpr[3],
        0x20 => self.rpop,
        0x21 => self.rmath,
        0x22 => self.rret,
        0x23 => self.rflag,
        else => @panic("Unknown register"),
    };
}

/// Converts a register's byte representation to a pointer to its value.
fn u8_to_reg_pointer(self: *Self, v: u8) *u8 {
    return switch (v) {
        0x10 => &self.gpr[0],
        0x11 => &self.gpr[1],
        0x12 => &self.gpr[2],
        0x13 => &self.gpr[3],
        0x20 => &self.rpop,
        0x21 => &self.rmath,
        0x22 => &self.rret,
        0x23 => &self.rflag,
        else => @panic("Unknown register"),
    };
}
