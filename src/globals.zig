const std = @import("std");
const types = @import("types.zig");

pub var save_interval: u16 = undefined;

pub const MAP_WIDTH: i32 = 100;
pub const MAP_HEIGHT: i32 = 60;
pub const MAP_SIZE = MAP_WIDTH * MAP_HEIGHT;
pub const NUM_CITY = 100 * (MAP_WIDTH + MAP_HEIGHT) / 228;
pub const SECTOR_ROWS: i32 = 5;
pub const SECTOR_COLS: i32 = 2;
pub const NUM_SECTORS = SECTOR_ROWS * SECTOR_COLS;
pub const ROWS_PER_SECTOR = @divTrunc((MAP_HEIGHT + SECTOR_ROWS) - 1, SECTOR_ROWS);
pub const COLS_PER_SECTOR = @divTrunc((MAP_WIDTH + SECTOR_COLS) - 1, SECTOR_COLS);
pub const STRSIZE = 400;
pub const NUM_OBJECTS = 9;
pub const LIST_SIZE = types.LIST_SIZE;

pub const Ownership = enum(i32) {
    Unowned = 0,
    User = 1,
    Comp = 2,
};

pub const PieceType = enum(i32) {
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

pub const Function = enum(i64) {
    NoFunc = -1,
    Random = -2,
    Sentry = -3,
    Fill = -4,
    Land = -5,
    Explore = -6,
    ArmyLoad = -7,
    ArmyAttack = -8,
    TTLoad = -9,
    Repair = -10,
    WFTransport = -11,
    Move_N = -12,
    Move_NE = -13,
    Move_E = -14,
    Move_SE = -15,
    Move_S = -16,
    Move_SW = -17,
    Move_W = -18,
    Move_NW = -19,
    _,
};

pub const Direction = enum(i32) {
    North = 0,
    Northeast = 1,
    East = 2,
    Southeast = 3,
    South = 4,
    Southwest = 5,
    West = 6,
    Northwest = 7,
};

pub const Terrain = enum(i32) {
    Unknown = 0,
    Path = 1,
    Land = 2,
    Water = 4,
    Air = 2 | 4,
};

// Game configuration (set during init)
pub var SMOOTH: i32 = 0;
pub var WATER_RATIO: i32 = 0;
pub var MIN_CITY_DIST: i32 = 0;
pub var delay_time: i32 = 0;
pub var savefile: ?[*:0]u8 = null;

// Game state
pub var date: i64 = 0;
pub var automove: bool = false;
pub var resigned: bool = false;
pub var debug: bool = false;
pub var print_debug: bool = false;
pub var print_vmap: u8 = 0;
pub var trace_pmap: bool = false;
pub var save_movie: bool = false;
pub var win: i32 = 0;
pub var user_score: i32 = 0;
pub var comp_score: i32 = 0;

// Maps
pub var map: [MAP_SIZE]types.real_map_t = std.mem.zeroes([MAP_SIZE]types.real_map_t);
pub var comp_map: [MAP_SIZE]types.view_map_t = std.mem.zeroes([MAP_SIZE]types.view_map_t);
pub var user_map: [MAP_SIZE]types.view_map_t = std.mem.zeroes([MAP_SIZE]types.view_map_t);

// Cities
pub var city: [NUM_CITY]types.city_info_t = std.mem.zeroes([NUM_CITY]types.city_info_t);

// Piece pool (replaces object[], free_list, user_obj[], comp_obj[])
pub var pool: [LIST_SIZE]types.Piece = std.mem.zeroes([LIST_SIZE]types.Piece);
pub var free_stack: [LIST_SIZE]types.PieceIdx = undefined;
pub var free_count: u16 = 0;

// Display
pub var lines: i32 = 0;
pub var cols: i32 = 0;
pub var jnkbuf: [STRSIZE]u8 = std.mem.zeroes([STRSIZE]u8);
