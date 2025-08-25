// |------------------------------------------|
// |              SYSCALL TABLE               |
// |------------------------------------------|
// | syscall # | arg0 | arg1    | arg2 | arg3 |
// |------------------------------------------|
// | r0        | r0   | r1      | r2   | r3   |
// |------------------------------------------|
// | write (0) | fd   | *buffer | size |      |
// |------------------------------------------|
//
pub fn Syscall(comptime arg_len: usize, sys: u8, args: [arg_len]u8) struct {
    sys: u8,
    args: [arg_len]u8,

    const Self = @This();

    pub fn execute(self: @This()) void {
        _ = self;
    }
} {
    return .{
        .sys = sys,
        .args = args,
    };
}
