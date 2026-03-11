const std = @import("std");

pub const loc_t = i64;
pub const uchar = u8;

// ── Piece pool types ────────────────────────────────────────────────────

pub const PieceIdx = u16;
pub const NO_PIECE: PieceIdx = std.math.maxInt(PieceIdx);
pub const MAX_CARGO: usize = 8;
pub const LIST_SIZE: usize = 5000;

pub const Piece = struct {
    owner: i32 = 0,
    type: i32 = 0,
    loc: loc_t = 0,
    func: i64 = 0,
    hits: i16 = 0,
    moved: i32 = 0,
    ship: PieceIdx = NO_PIECE,
    count: i16 = 0,
    range: i16 = 0,

    // Pool bookkeeping
    alive: bool = false,

    // Location chain (replaces loc_link doubly-linked list)
    loc_next: PieceIdx = NO_PIECE,

    // Cargo (replaces cargo_link doubly-linked list)
    cargo: [MAX_CARGO]PieceIdx = [_]PieceIdx{NO_PIECE} ** MAX_CARGO,
};

// ── Map types ───────────────────────────────────────────────────────────

pub const real_map_t = struct {
    contents: u8 = 0,
    on_board: bool = false,
    cityp: ?*city_info_t = null,
    obj_head: PieceIdx = NO_PIECE,
};

pub const view_map_t = extern struct {
    contents: u8 = 0,
    seen: i64 = 0,
};

// ── City types ──────────────────────────────────────────────────────────

pub const struct_city_info = extern struct {
    loc: loc_t = 0,
    owner: uchar = 0,
    func: [9]i64 = [_]i64{0} ** 9,
    work: i64 = 0,
    prod: u8 = 0,
};
pub const city_info_t = struct_city_info;

// ── Other types ─────────────────────────────────────────────────────────

pub const struct_piece_attr = struct {
    sname: u8 = 0,
    name: [20]u8 = std.mem.zeroes([20]u8),
    nickname: [20]u8 = std.mem.zeroes([20]u8),
    article: [20]u8 = std.mem.zeroes([20]u8),
    plural: [20]u8 = std.mem.zeroes([20]u8),
    terrain: [4]u8 = std.mem.zeroes([4]u8),
    build_time: uchar = 0,
    strength: uchar = 0,
    max_hits: uchar = 0,
    speed: uchar = 0,
    capacity: uchar = 0,
    range: i64 = 0,
};
pub const piece_attr_t = struct_piece_attr;

pub const path_map_t = struct {
    cost: i32 = 0,
    inc_cost: i32 = 0,
    terrain: u8 = 0,
};

pub const move_info_t = struct {
    city_owner: u8 = 0,
    objectives: [*:0]const u8 = "",
    weights: [11]i32 = [_]i32{0} ** 11,
};

pub const scan_counts_t = struct {
    user_cities: i32 = 0,
    user_objects: [9]i32 = [_]i32{0} ** 9,
    comp_cities: i32 = 0,
    comp_objects: [9]i32 = [_]i32{0} ** 9,
    size: i32 = 0,
    unowned_cities: i32 = 0,
    unexplored: i32 = 0,
};

pub const perimeter_t = struct {
    len: i64 = 0,
    list: [6000]i64 = std.mem.zeroes([6000]i64),
};

// ── Old types (for backward-compatible save loading) ────────────────────

pub const OldLink = extern struct {
    next: ?*anyopaque = null,
    prev: ?*anyopaque = null,
};

pub const OldPieceInfo = extern struct {
    piece_link: OldLink = .{},
    loc_link: OldLink = .{},
    cargo_link: OldLink = .{},
    owner: i32 = 0,
    type: i32 = 0,
    loc: i64 = 0,
    func: i64 = 0,
    hits: i16 = 0,
    moved: i32 = 0,
    ship: ?*anyopaque = null,
    cargo: ?*anyopaque = null,
    count: i16 = 0,
    range: i16 = 0,
};

pub const OldRealMap = extern struct {
    contents: u8 = 0,
    on_board: bool = false,
    cityp: ?*anyopaque = null,
    objp: ?*anyopaque = null,
};

// ── Save format types ───────────────────────────────────────────────────

pub const SavedPiece = extern struct {
    owner: i32 = 0,
    type: i32 = 0,
    loc: i64 = 0,
    func: i64 = 0,
    hits: i16 = 0,
    moved: i32 = 0,
    ship: PieceIdx = NO_PIECE,
    count: i16 = 0,
    range: i16 = 0,
    alive: u8 = 0,
};

pub const SavedMapCell = extern struct {
    contents: u8 = 0,
    on_board: u8 = 0,
};
