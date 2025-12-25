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

pub inline fn loc_row(loc: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.div(loc, globals.MAP_WIDTH)) {
    _ = &loc;
    return @import("std").zig.c_translation.MacroArithmetic.div(loc, globals.MAP_WIDTH);
}
pub inline fn loc_col(loc: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.rem(loc, globals.MAP_WIDTH)) {
    _ = &loc;
    return @import("std").zig.c_translation.MacroArithmetic.rem(loc, globals.MAP_WIDTH);
}
pub inline fn row_col_sector(row: anytype, col: anytype) c_int {
    return std.zig.c_translation.cast(c_int, (col * globals.SECTOR_ROWS) + row);
}
pub inline fn loc_sector(loc: anytype) c_int {
    return row_col_sector(std.zig.c_translation.MacroArithmetic.div(loc_row(loc), globals.ROWS_PER_SECTOR), std.zig.c_translation.MacroArithmetic.div(loc_col(loc), globals.COLS_PER_SECTOR));
}
