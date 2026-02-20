const std = @import("std");
const types = @import("types.zig");
const globals = @import("globals.zig");

pub const MAP_LAND = '+';
pub const MAP_SEA = '.';
pub const MAP_CITY = '*';

const INFINITY = 10000000;
const W_TT_BUILD: c_int = -1;
const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);

fn strBuf(comptime N: usize, comptime s: []const u8) [N]u8 {
    var buf: [N]u8 = std.mem.zeroes([N]u8);
    @memcpy(buf[0..s.len], s);
    return buf;
}

fn weights(comptime vals: []const c_int) [11]c_int {
    var w: [11]c_int = std.mem.zeroes([11]c_int);
    for (vals, 0..) |v, i| w[i] = v;
    return w;
}

// Piece attributes

pub var piece_attr: [9]types.piece_attr_t = .{
    .{ .sname = 'A', .name = strBuf(20, "army"), .nickname = strBuf(20, "army"), .article = strBuf(20, "an army"), .plural = strBuf(20, "armies"), .terrain = strBuf(4, "+"), .build_time = 5, .strength = 1, .max_hits = 1, .speed = 1, .capacity = 0, .range = INFINITY },
    .{ .sname = 'F', .name = strBuf(20, "fighter"), .nickname = strBuf(20, "fighter"), .article = strBuf(20, "a fighter"), .plural = strBuf(20, "fighters"), .terrain = strBuf(4, ".+"), .build_time = 10, .strength = 1, .max_hits = 1, .speed = 8, .capacity = 0, .range = 32 },
    .{ .sname = 'P', .name = strBuf(20, "patrol boat"), .nickname = strBuf(20, "patrol"), .article = strBuf(20, "a patrol boat"), .plural = strBuf(20, "patrol boats"), .terrain = strBuf(4, "."), .build_time = 15, .strength = 1, .max_hits = 1, .speed = 4, .capacity = 0, .range = INFINITY },
    .{ .sname = 'D', .name = strBuf(20, "destroyer"), .nickname = strBuf(20, "destroyer"), .article = strBuf(20, "a destroyer"), .plural = strBuf(20, "destroyers"), .terrain = strBuf(4, "."), .build_time = 20, .strength = 1, .max_hits = 3, .speed = 2, .capacity = 0, .range = INFINITY },
    .{ .sname = 'S', .name = strBuf(20, "submarine"), .nickname = strBuf(20, "submarine"), .article = strBuf(20, "a submarine"), .plural = strBuf(20, "submarines"), .terrain = strBuf(4, "."), .build_time = 20, .strength = 3, .max_hits = 2, .speed = 2, .capacity = 0, .range = INFINITY },
    .{ .sname = 'T', .name = strBuf(20, "troop transport"), .nickname = strBuf(20, "transport"), .article = strBuf(20, "a troop transport"), .plural = strBuf(20, "troop transports"), .terrain = strBuf(4, "."), .build_time = 30, .strength = 1, .max_hits = 1, .speed = 2, .capacity = 6, .range = INFINITY },
    .{ .sname = 'C', .name = strBuf(20, "aircraft carrier"), .nickname = strBuf(20, "carrier"), .article = strBuf(20, "an aircraft carrier"), .plural = strBuf(20, "aircraft carriers"), .terrain = strBuf(4, "."), .build_time = 30, .strength = 1, .max_hits = 8, .speed = 2, .capacity = 8, .range = INFINITY },
    .{ .sname = 'B', .name = strBuf(20, "battleship"), .nickname = strBuf(20, "battleship"), .article = strBuf(20, "a battleship"), .plural = strBuf(20, "battleships"), .terrain = strBuf(4, "."), .build_time = 40, .strength = 2, .max_hits = 10, .speed = 2, .capacity = 0, .range = INFINITY },
    .{ .sname = 'Z', .name = strBuf(20, "satellite"), .nickname = strBuf(20, "satellite"), .article = strBuf(20, "a satellite"), .plural = strBuf(20, "satellites"), .terrain = strBuf(4, ".+"), .build_time = 50, .strength = 0, .max_hits = 1, .speed = 10, .capacity = 0, .range = 500 },
};

// Direction offsets

pub var dir_offset: [8]c_int = .{
    -globals.MAP_WIDTH, // north
    -globals.MAP_WIDTH + 1, // northeast
    1, // east
    globals.MAP_WIDTH + 1, // southeast
    globals.MAP_WIDTH, // south
    globals.MAP_WIDTH - 1, // southwest
    -1, // west
    -globals.MAP_WIDTH - 1, // northwest
};

// Names of movement functions

pub var func_name: [19][*c]const u8 = .{
    "none", "random", "sentry", "fill", "land",
    "explore", "load", "attack", "load", "repair",
    "transport", "W", "E", "D", "C",
    "X", "Z", "A", "Q",
};

// The order in which pieces should be moved

pub var move_order: [9]c_int = .{
    @intFromEnum(globals.PieceType.Satellite),
    @intFromEnum(globals.PieceType.Transport),
    @intFromEnum(globals.PieceType.Carrier),
    @intFromEnum(globals.PieceType.Battleship),
    @intFromEnum(globals.PieceType.Patrol),
    @intFromEnum(globals.PieceType.SubMarine),
    @intFromEnum(globals.PieceType.Destroyer),
    @intFromEnum(globals.PieceType.Army),
    @intFromEnum(globals.PieceType.Fighter),
};

// Types of pieces, in declared order

pub var type_chars: [10]u8 = "AFPDSTCBZ\x00".*;

// Lists of attackable objects if object is adjacent to moving piece

pub var tt_attack: [2]u8 = "T\x00".*;
pub var army_attack: [11]u8 = "O*TACFBSDP\x00".*;
pub var fighter_attack: [9]u8 = "TCFBSDPA\x00".*;
pub var ship_attack: [7]u8 = "TCBSDP\x00".*;

// Movement objectives

pub var tt_explore: types.move_info_t = .{ .city_owner = COMP, .objectives = " ", .weights = weights(&.{1}) };
pub var tt_load: types.move_info_t = .{ .city_owner = COMP, .objectives = "$", .weights = weights(&.{1}) };
pub var tt_unload: types.move_info_t = .{ .city_owner = COMP, .objectives = "9876543210 ", .weights = weights(&.{ 1, 1, 1, 1, 1, 1, 11, 21, 41, 101, 61 }) };
pub var army_fight: types.move_info_t = .{ .city_owner = COMP, .objectives = "O*TA ", .weights = weights(&.{ 1, 1, 1, 1, 11 }) };
pub var army_load: types.move_info_t = .{ .city_owner = COMP, .objectives = "$x", .weights = weights(&.{ 1, W_TT_BUILD }) };
pub var fighter_fight: types.move_info_t = .{ .city_owner = COMP, .objectives = "TCFBSDPA ", .weights = weights(&.{ 1, 1, 5, 5, 5, 5, 5, 5, 9 }) };
pub var ship_fight: types.move_info_t = .{ .city_owner = COMP, .objectives = "TCBSDP ", .weights = weights(&.{ 1, 1, 3, 3, 3, 3, 21 }) };
pub var ship_repair: types.move_info_t = .{ .city_owner = COMP, .objectives = "X", .weights = weights(&.{1}) };

pub var user_army: types.move_info_t = .{ .city_owner = USER, .objectives = " ", .weights = weights(&.{1}) };
pub var user_army_attack: types.move_info_t = .{ .city_owner = USER, .objectives = "*Xa ", .weights = weights(&.{ 1, 1, 1, 12 }) };
pub var user_fighter: types.move_info_t = .{ .city_owner = USER, .objectives = " ", .weights = weights(&.{1}) };
pub var user_ship: types.move_info_t = .{ .city_owner = USER, .objectives = " ", .weights = weights(&.{1}) };
pub var user_ship_repair: types.move_info_t = .{ .city_owner = USER, .objectives = "O", .weights = weights(&.{1}) };

// Help texts

pub var help_cmd: [19][*c]const u8 = .{
    "COMMAND MODE",
    "Auto:     enter automove mode",
    "City:     give city to computer",
    "Date:     print round",
    "Examine:  examine enemy map",
    "File:     print map to file",
    "Give:     give move to computer",
    "Help:     display this text",
    "J:        enter edit mode",
    "Move:     make a move",
    "N:        give N moves to computer",
    "Print:    print a sector",
    "Quit:     quit game",
    "Restore:  restore game",
    "Save:     save game",
    "Trace:    save movie in empmovie.dat",
    "Watch:    watch movie",
    "Zoom:     display compressed map",
    "<ctrl-L>: redraw screen",
};
pub var cmd_lines: c_int = 19;

pub var help_user: [22][*c]const u8 = .{
    "USER MODE",
    "QWE",
    "A D       movement directions",
    "ZXC",
    "<space>:  sit",
    "Build:    change city production",
    "Fill:     set func to fill",
    "Grope:    set func to explore",
    "Help:     display this text",
    "I <dir>:  set func to dir",
    "J:        enter edit mode",
    "Kill:     set func to awake",
    "Land:     set func to land",
    "Out:      leave automove mode",
    "Print:    redraw screen",
    "Random:   set func to random",
    "Sentry:   set func to sentry",
    "Transport:set func to transport",
    "Upgrade:  set func to repair",
    "V <piece> <func>:  set city func",
    "Y:        set func to attack",
    "?:        describe piece",
};
pub var user_lines: c_int = 22;

pub var help_edit: [22][*c]const u8 = .{
    "EDIT MODE",
    "QWE",
    "A D       movement directions",
    "ZXC",
    "Build:    change city production",
    "Fill:     set func to fill",
    "Grope:    set func to explore",
    "Help:     display this text",
    "I <dir>:  set func to dir",
    "Kill:     set func to awake",
    "Land:     set func to land",
    "Mark:     mark piece",
    "N:        set dest for marked piece",
    "Out:      exit edit mode",
    "Print:    print sector",
    "Random:   set func to random",
    "Sentry:   set func to sentry",
    "Upgrade:  set func to repair",
    "V <piece> <func>:  set city func",
    "Y:        set func to attack",
    "<ctrl-L>: redraw screen",
    "?:        describe piece",
};
pub var edit_lines: c_int = 22;
