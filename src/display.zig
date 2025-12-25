const globals = @import("globals.zig");
const types = @import("types.zig");

pub extern fn ttinit() void;
pub extern fn clear_screen() void;
pub extern fn pos_str(row: c_int, col: c_int, str: [*c]const u8, ...) void;
pub extern fn redisplay() void;
pub extern fn cur_sector() c_int;
pub extern fn print_zoom(vmap: [*c]types.view_map_t) void;
pub extern fn redraw() void;
pub extern fn print_sector(whose: c_int, vmap: [*c]types.view_map_t, sector: c_int) void;

pub inline fn print_sector_u(sector: c_int) void {
    print_sector(@intFromEnum(globals.Ownership.User), &globals.user_map, sector);
}

pub inline fn print_sector_c(sector: c_int) void {
    print_sector(@intFromEnum(globals.Ownership.Comp), &globals.comp_map, sector);
}
