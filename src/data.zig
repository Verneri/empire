const types = @import("types.zig");

pub const help_cmd: [*c][*c]u8 = @extern([*c][*c]u8, .{
    .name = "help_cmd",
});
pub extern var cmd_lines: c_int;

pub const piece_attr: [*c]types.piece_attr_t = @extern([*c]types.piece_attr_t, .{
    .name = "piece_attr",
});
pub const move_order: [*c]c_int = @extern([*c]c_int, .{
    .name = "move_order",
});
