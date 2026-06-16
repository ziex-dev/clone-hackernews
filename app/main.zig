const zx = @import("zx");
const migrate = @import("db/migrate.zig");

pub fn main(init: zx.Init) !void {
    var app = try zx.App.init(init, zx.io(), zx.allocator, .{}, {});
    defer app.deinit();

    try migrate.run();

    try app.start();
}

pub const std_options = zx.std_options;
