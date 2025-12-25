const globals = @import("globals.zig");
const std = @import("std");

pub extern fn empend() void;

pub inline fn row_col_loc(row: c_int, col: c_int) c_long {
    return @intCast(row * globals.MAP_WIDTH + col);
}

pub inline fn sector_row(sector: c_int) c_int {
    return std.zig.c_translation.signedRemainder(sector, globals.SECTOR_ROWS);
}

pub inline fn sector_col(sector: c_int) c_int {
    return @divFloor(sector, globals.SECTOR_ROWS);
}

pub inline fn sector_loc(sector: c_int) c_long {
    return row_col_loc(sector_row(sector) * globals.ROWS_PER_SECTOR + globals.ROWS_PER_SECTOR / 2, sector_col(sector) * globals.COLS_PER_SECTOR + globals.COLS_PER_SECTOR / 2);
}
