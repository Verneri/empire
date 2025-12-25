pub const help_cmd: [*c][*c]u8 = @extern([*c][*c]u8, .{
    .name = "help_cmd",
});
pub extern var cmd_lines: c_int;
