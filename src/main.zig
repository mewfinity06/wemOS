const std = @import("std");
const wemVM = @import("wemVM");
const Machine = @import("machine.zig");

pub fn main() !void {
    // get allocator
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const allocator = da.allocator();

    // get args
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len < 2) {
        try wemVM.usage();
        try wemVM.err("Not enough args!\n", .{});
        return;
    }

    // run machine
    var m = try Machine.from_file(allocator, argv[1]);
    defer m.deinit();

    try m.run();
    wemVM.seperator();
    try m.display();
    wemVM.seperator();
}
