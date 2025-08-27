const std = @import("std");
const wemVM = @import("wemVM");

const inst_lib = @import("bytecode/instruction.zig");
const Inst = inst_lib.Inst;
const u8_to_inst = inst_lib.u8_to_inst;

const syscall = @import("bytecode/syscall.zig");
const Syscall = syscall.Syscall;
const Call = syscall.Call;
const CallFn = syscall.CallFn;
const write = syscall.write;

const Lexer = @import("lexer.zig");

const Token = @import("token.zig").Token;

allocator: std.mem.Allocator,

pc: usize = 0,
program: std.ArrayList(Token) = undefined,
data: std.ArrayList(Token) = undefined,

sp: usize = 0,
stack: [STACK_SIZE]u8 = .{0} ** STACK_SIZE,

gpr: [GPR_SIZE]u8 = .{0} ** GPR_SIZE,
rpop: u8 = 0, //  0x20
rmath: u8 = 0, // 0x21
rret: u8 = 0, //  0x22
rflag: u8 = 0, // 0x23

unresolved_labels: std.AutoHashMap([]const u8, u8),
resolved_labels: std.AutoHashMap([]const u8, u8),

pub const STACK_SIZE: usize = 8;
pub const GPR_SIZE: usize = 8;

const Self = @This();

/// Creates a new machine from a file.
pub fn from_file(allocator: std.mem.Allocator, file_path: []const u8) !Self {
    var res = Self{
        .allocator = allocator,
        .program = try std.ArrayList(Token).initCapacity(allocator, 0),
        .data = try std.ArrayList(Token).initCapacity(allocator, 0),
        .unresolved_labels = std.AutoHashMap([]const u8, u8).init(allocator),
        .resolved_labels = std.AutoHashMap([]const u8, u8).init(allocator),
    };

    const content = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    defer allocator.free(content);

    var l = Lexer.new(&res, content);
    defer l.deinit();

    while (try l.next()) |t| {
        if (l.in_data_section) {
            // try wemVM.debug("From data_section: {any}\n", .{t});
            try res.data.append(res.allocator, t);
        } else {
            // try wemVM.debug("From executable_section: {any}\n", .{t});
            try res.program.append(res.allocator, t);
        }
    }

    return res;
}

fn create_label(self: *Self, label: []const u8) !void {
    if (self.resolved_labels.contains(label)) {
        try create_label_known(self, label);
    } else {
        try create_label_unknown(self, label);
    }
}

fn create_label_known(self: *Self, label: []const u8) !void {
    _ = .{ self, label };
}

fn create_label_unknown(self: *Self, label: []const u8) !void {
    _ = .{ self, label };
}

fn remove_label(self: *Self, label: []const u8) !void {
    _ = .{ self, label };
}

fn resolve_label(self: *Self, label: []const u8) !u8 {
    _ = .{ self, label };
    return error.Unimplemented;
}

/// Deinitializes the machine.
pub fn deinit(self: *Self) void {
    for (self.program.items) |dp| {
        switch (dp) {
            .label_definition => |ld| {
                // wemVM.debug("deinit: label_definition\n", .{}) catch {};
                self.allocator.free(ld.@"0");
            },
            .label_reference => |lr| {
                // wemVM.debug("deinit: label_reference\n", .{}) catch {};
                self.allocator.free(lr.@"0");
            },
            else => {},
        }
    }
    self.data.deinit(self.allocator);
    self.program.deinit(self.allocator);
}

/// Prints the machine's state.
pub fn print(self: *Self) !void {
    try wemVM.seperator();
    defer wemVM.seperator() catch {};
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
        std.debug.print("   pc: 0x{X} -> 0x{X} ({any})\n", .{ self.pc, self.program.items[self.pc].instruction.to_u8(), self.program.items[self.pc].instruction });
    }
    // Registers
    std.debug.print("   General Purpose Registers:\n", .{});
    for (0..Self.GPR_SIZE) |i| {
        std.debug.print("      r{} (0x{X}) => 0x{X}\n", .{ i, i + 0x10, self.gpr[i] });
    }
    std.debug.print("   Special Purpose Registers:\n", .{});
    std.debug.print("      pop => 0x{X}, math  => 0x{X}\n", .{ self.rpop, self.rmath });
    std.debug.print("      ret => 0x{X}, flags => 0x{X}\n", .{ self.rret, self.rflag });
}

/// Displays the machine's program and data.
pub fn display(self: *Self) !void {
    try wemVM.info("Program {{\n", .{});
    var i: usize = 0;
    while (i < self.program.items.len) : (i += 1) {
        defer std.debug.print("\n", .{});
        switch (self.program.items[i]) {
            .label_definition => |ld| {
                std.debug.print("- {s}", .{ld.@"0"});
            },
            .instruction => |in| {
                std.debug.print("(0x{X})\t", .{i});
                switch (in) {
                    .halt => std.debug.print("halt", .{}),
                    .nop => std.debug.print("nop", .{}),
                    .push => {
                        std.debug.print("push ", .{});
                        i += 1;
                        const arg = self.program.items[i].literal;
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
                        const src = self.program.items[i].register;
                        i += 1;
                        const dest = self.program.items[i].register;
                        std.debug.print("<src: {s}>, <dest: {s}>", .{ u8_to_reg_name(src), u8_to_reg_name(dest) });
                    },
                    .set => {
                        std.debug.print("set ", .{});
                        i += 1;
                        const reg = self.program.items[i].register;
                        i += 1;
                        const value = self.program.items[i].literal;
                        std.debug.print("<reg: {s}>, <value: 0x{X}>", .{ u8_to_reg_name(reg), value });
                    },
                    .syscall => std.debug.print("set", .{}),
                    .goto => {
                        std.debug.print("goto ", .{});
                        i += 1;
                        const arg = self.program.items[i].label_reference.@"0";
                        std.debug.print("<label: {s}>", .{arg});
                    },
                    else => {
                        std.debug.print("\r", .{});
                        try wemVM.err("Unhandled inst: {any}", .{self.program.items[i]});
                    },
                }
            },
            else => |e| {
                try wemVM.err("Invalid: {any}", .{e});
            },
        }
    }
    std.debug.print("\t.data:\n", .{});
    std.debug.print("\t    data len: {}\n", .{self.data.items.len});
    for (self.data.items) |dp| {
        std.debug.print("\t    {any}\n", .{dp});
    }
    std.debug.print("}}\n", .{});
}

fn advance(self: *Self) Token {
    defer self.pc += 1;
    return self.program.items[self.pc];
}

fn get_stack(self: *Self, by: isize) u8 {
    defer {
        if (by > 0)
            self.sp += @intCast(by)
        else if (by < 0)
            self.sp -= @intCast(by)
        else {}
    }
    return self.stack[self.sp];
}

/// Executes a single instruction.
pub fn step(self: *Self) !bool {
    if (self.pc >= self.program.items.len) return false;
    switch (self.advance()) {
        .instruction => |inst| switch (inst) {
            .halt => return false,
            .nop => {},
            .push => {
                const value = self.advance().literal;
                self.stack[self.sp] = value;
                self.sp += 1;
            },
            .pushr => {
                const value = self.u8_to_reg_value(self.advance().register);
                self.stack[self.sp] = value;
                self.sp += 1;
            },
            .pop => {
                const value = self.stack[self.sp];
                self.rpop = value;
                self.sp -= 1;
            },
            .popr => {
                const value = self.u8_to_reg_value(self.advance().register);
                self.rpop = value;
                self.sp -= 1;
            },
            .add => {
                const b = self.get_stack(-1);
                const a = self.get_stack(-1);
                self.rmath = b + a;
            },
            .goto => {
                const addr = self.advance().label_reference;
                _ = addr;
            },
            else => |in| {
                try wemVM.err("Unhandled instruction: {any}\n", .{in});
                return false;
            },
        },
        .label_definition => |ld| {
            // handle label definitions
            const name, _ = ld;
            try wemVM.info("Label definition: {s}\n", .{name});
        },
        .label_reference => |lr| {
            // handle label references
            const name, _ = lr;
            try wemVM.info("Label definition: {s}\n", .{name});
        },
        else => |t| {
            try wemVM.err("Found `{any}`, expected instruction, label_definition, label_reference\n", .{t});
            return false;
        },
    }
    return true;
}

/// Runs the machine.
pub fn run(self: *Self) !void {
    while (try self.step()) {}
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
