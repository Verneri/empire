const types = @import("types.zig");
pub export var save_interval: u16 = undefined;

pub const MAP_WIDTH = @as(c_int, 100);
pub const MAP_HEIGHT = @as(c_int, 60);
pub const MAP_SIZE = MAP_WIDTH * MAP_HEIGHT;
pub const NUM_CITY = 100 * (MAP_WIDTH + MAP_HEIGHT) / 228;
pub const SECTOR_ROWS = @as(c_int, 5);
pub const SECTOR_COLS = @as(c_int, 2);
pub const NUM_SECTORS = SECTOR_ROWS * SECTOR_COLS;
pub const ROWS_PER_SECTOR = @import("std").zig.c_translation.MacroArithmetic.div((MAP_HEIGHT + SECTOR_ROWS) - @as(c_int, 1), SECTOR_ROWS);
pub const COLS_PER_SECTOR = @import("std").zig.c_translation.MacroArithmetic.div((MAP_WIDTH + SECTOR_COLS) - @as(c_int, 1), SECTOR_COLS);

pub extern var SMOOTH: c_int;
pub extern var WATER_RATIO: c_int;
pub extern var MIN_CITY_DIST: c_int;
pub extern var delay_time: c_int;
pub extern var savefile: [*c]u8;
pub extern var automove: bool;
pub extern var date: c_long;
pub extern var resigned: bool;
pub extern var debug: bool;
pub extern var save_movie: bool;
pub extern var map: [MAP_SIZE]types.real_map_t;
pub extern var comp_map: [MAP_SIZE]types.view_map_t;
pub extern var user_map: [MAP_SIZE]types.view_map_t;
