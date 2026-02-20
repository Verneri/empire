const std = @import("std");
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
pub const STRSIZE = 400;
pub const NUM_OBJECTS = 9;
pub const LIST_SIZE = 5000;

pub const Ownership = enum(c_int) {
    Unowned = 0,
    User = 1,
    Comp = 2,
};

pub const PieceType = enum(c_int) {
    Army = 0,
    Fighter = 1,
    Patrol = 2,
    Destroyer = 3,
    SubMarine = 4,
    Transport = 5,
    Carrier = 6,
    Battleship = 7,
    Satellite = 8,
    NumObjects = 9,
    NoPiece = 255,
};

pub const Function = enum(c_long) {
    NoFunc = -1, //       /* no programmed function */
    Random = -2, //       /* move randomly */
    Sentry = -3, //       /* sleep */
    Fill = -4, //         /* fill transport */
    Land = -5, //         /* land fighter at city */
    Explore = -6, //      /* piece explores nearby */
    ArmyLoad = -7, //     /* army moves toward and boards a transport */
    ArmyAttack = -8, //   /* army looks for city to attack */
    TTLoad = -9, //       /* transport moves toward loading armies */
    Repair = -10, //      /* ship moves toward port */
    WFTransport = -11, // /* army boards a transport */
    Move_N = -12, //      /* move north */
    Move_NE = -13, //     /* move northeast */
    Move_E = -14, //      /* move east */
    Move_SE = -15, //     /* move southeast */
    Move_S = -16, //      /* move south */
    Move_SW = -17, //     /* move southwest */
    Move_W = -18, //      /* move west */
    Move_NW = -19, //     /* move northwest
    _, // move to loc
};

pub const Direction = enum(c_int) {
    North = 0,
    Northeast = 1,
    East = 2,
    Southeast = 3,
    South = 4,
    Southwest = 5,
    West = 6,
    Northwest = 7,
};

pub const Terrain = enum(c_int) {
    Unknown = 0,
    Path = 1,
    Land = 2,
    Water = 4,
    Air = 2 | 4,
};

// Game configuration (set during init)
pub export var SMOOTH: c_int = 0;
pub export var WATER_RATIO: c_int = 0;
pub export var MIN_CITY_DIST: c_int = 0;
pub export var delay_time: c_int = 0;
pub export var savefile: [*c]u8 = null;

// Game state
pub export var date: c_long = 0;
pub export var automove: bool = false;
pub export var resigned: bool = false;
pub export var debug: bool = false;
pub export var print_debug: bool = false;
pub export var print_vmap: u8 = 0;
pub export var trace_pmap: bool = false;
pub export var save_movie: bool = false;
pub export var win: c_int = 0;
pub export var user_score: c_int = 0;
pub export var comp_score: c_int = 0;

// Maps
pub export var map: [MAP_SIZE]types.real_map_t = std.mem.zeroes([MAP_SIZE]types.real_map_t);
pub export var comp_map: [MAP_SIZE]types.view_map_t = std.mem.zeroes([MAP_SIZE]types.view_map_t);
pub export var user_map: [MAP_SIZE]types.view_map_t = std.mem.zeroes([MAP_SIZE]types.view_map_t);

// Cities
pub export var city: [NUM_CITY]types.city_info_t = std.mem.zeroes([NUM_CITY]types.city_info_t);

// Objects
pub export var free_list: [*c]types.piece_info_t = null;
pub export var user_obj: [NUM_OBJECTS][*c]types.piece_info_t = std.mem.zeroes([NUM_OBJECTS][*c]types.piece_info_t);
pub export var comp_obj: [NUM_OBJECTS][*c]types.piece_info_t = std.mem.zeroes([NUM_OBJECTS][*c]types.piece_info_t);
pub export var object: [LIST_SIZE]types.piece_info_t = std.mem.zeroes([LIST_SIZE]types.piece_info_t);

// Display
pub export var lines: c_int = 0;
pub export var cols: c_int = 0;
pub export var jnkbuf: [STRSIZE]u8 = std.mem.zeroes([STRSIZE]u8);
