const std = @import("std");
const globals = @import("globals.zig");
const object = @import("object.zig");
const types = @import("types.zig");
const piece_info_t = types.piece_info_t;
const data = @import("data.zig");
const terminal = @import("terminal.zig");
const display = @import("display.zig");
const util = @import("util.zig");
const game = @import("game.zig");
const map = @import("map.zig");
const edit = @import("edit.zig");
const math = @import("math.zig");

extern fn user_move() void;

pub fn move() void {
    // reset moved for units
    for (globals.user_obj) |obj| {
        var cur: ?*types.struct_piece_info = obj;
        while (cur != null) : (cur = cur.?.piece_link.next) {
            cur.?.moved = 0;
            object.scan(&globals.user_map, cur.?.loc);
        }
    }
    // produce
    for (&globals.city) |*city| {
        if (owned_by(city, globals.Ownership.User)) {
            object.scan(&globals.user_map, city.loc);
            const prod = city.prod;
            if (prod == @intFromEnum(globals.PieceType.NoPiece)) {
                object.set_prod(city);
            } else {
                city.work += 1;
                if (city.work >= data.piece_attr[prod].build_time) {
                    terminal.ksend("%s has been completed at city %d.\n", &data.piece_attr[prod].article, terminal.loc_disp(@as(c_int, @bitCast(@as(c_int, @truncate(city.loc))))));
                    terminal.comment("%s has been completed at city %d.\n", &data.piece_attr[prod].article, terminal.loc_disp(@as(c_int, @bitCast(@as(c_int, @truncate(city.loc))))));

                    object.produce(city);
                }
            }
        }
    }

    var cur_satellite: ?*types.struct_piece_info = globals.user_obj[@intFromEnum(globals.PieceType.Satellite)];
    while (cur_satellite != null) : (cur_satellite = cur_satellite.?.piece_link.next) {
        object.move_sat(cur_satellite.?);
    }

    var sec_start = display.cur_sector();
    if (sec_start < 0) sec_start = 0;
    const start: usize = @intCast(sec_start);
    const end: usize = start + globals.NUM_SECTORS;

    for (start..end) |i| {
        const sec = @rem(i, globals.NUM_SECTORS);
        display.sector_change();
        for (data.move_order[0..globals.NUM_OBJECTS]) |j| {
            var cur: ?*types.struct_piece_info = globals.user_obj[@as(usize, @intCast(j))];
            while (cur != null) : (cur = cur.?.piece_link.next) {
                const obj = cur.?;
                if (obj.moved == 0 and util.loc_sector(obj.loc) == sec) {
                    piece_move(obj);
                }
            }
        }
        if (display.cur_sector() == sec) {
            display.print_sector_u(@intCast(sec));
            display.redisplay();
        }
    }
    if (globals.save_movie) game.save_movie_screen();
}

pub inline fn owned_by(obj: anytype, owner: globals.Ownership) bool {
    return obj.owner == @intFromEnum(owner);
}

// Move a piece.  We loop until all the moves of a piece are made.  Within
// the loop, we first awaken the piece if it is adjacent to an enemy piece.
// Then we attempt to handle any preprogrammed function for the piece.  If
// the piece has not moved after this, we ask the user what to do.
fn piece_move(obj: *types.piece_info_t) void {
    const city: ?*types.struct_city_info = object.find_city(obj.loc);
    if (city) |c| {
        const city_func = c.func[@intCast(obj.type)];
        if (city_func != @intFromEnum(globals.Function.NoFunc)) {
            obj.*.func = city_func;
        }
    }

    var changed_location = false;
    const obj_attr = data.piece_attr[@intCast(obj.type)];
    const speed = obj_attr.speed;
    const max_hits = obj_attr.max_hits;
    var need_input = false;

    while (obj.moved < object.moves(obj)) {
        const saved_moves = obj.moved;
        const saved_loc = obj.loc;
        if (awake(obj) or need_input) {
            ask_user(obj);
            terminal.topini();
            display.display_loc_u(obj.loc);
            display.redisplay();
            need_input = false;
        }

        if (obj.moved == saved_moves) {
            const func: globals.Function = @enumFromInt(obj.func);
            switch (func) {
                .NoFunc => {},
                .Random => {
                    move_random(obj);
                },
                .Sentry => {
                    obj.*.moved = speed;
                },
                .Fill => {
                    move_fill(obj);
                },
                .Land => {
                    move_land(obj);
                },
                .Explore => {
                    move_explore(obj);
                },
                .ArmyLoad => move_armyload(obj),
                .ArmyAttack => move_armyattack(obj),
                .TTLoad => move_ttload(obj),
                .Repair => move_repair(obj),
                .WFTransport => move_transport(obj),

                .Move_N, .Move_NE, .Move_E, .Move_SE, .Move_S, .Move_SW, .Move_W, .Move_NW => move_dir(obj),

                _ => move_path(obj),
            }
        }

        if (obj.moved == saved_moves) {
            need_input = true;
        }

        const obj_loc: usize = @intCast(obj.loc);
        if (obj.type == @intFromEnum(globals.PieceType.Fighter) and obj.hits > 0) {
            if ((globals.user_map[obj_loc].contents == 'O' or globals.user_map[obj_loc].contents == 'C') and obj.moved > 0) {
                obj.*.range = @intCast(obj_attr.range);
                obj.*.moved = speed;
                obj.*.func = @intFromEnum(globals.Function.NoFunc);
                terminal.comment("Landing confirmed");
            } else if (obj.range == 0) {
                terminal.comment("Fighter at %d crashed and burned.", terminal.loc_disp(@intCast(obj.loc)));
            }
        }

        if (saved_loc != obj.loc) {
            changed_location = true;
        }

        if (obj.hits > 0 and
            !changed_location and
            !(obj.type == @intFromEnum(globals.PieceType.Fighter) or obj.type == @intFromEnum(globals.PieceType.Army)) and
            obj.hits < max_hits and
            globals.user_map[obj_loc].contents == 'O')
        {
            obj.*.hits += 1;
        }
    }
}

export fn awake(obj: *types.piece_info_t) bool {
    if (type_is(obj, .Army) and
        map.vmap_at_sea(&globals.user_map, obj.loc))
    {
        obj.*.moved = @intCast(piece_attr(.Army).range);
        return false;
    }

    if (function(obj) == .NoFunc) return true;

    var city_loc: c_long = undefined;

    if (piece_type(obj) == .Fighter and
        function(obj) != .Land and
        !has_destination(obj) and
        obj.range <= object.find_nearest_city(obj.loc, @intFromEnum(globals.Ownership.User), &city_loc) + 2)
    {
        obj.*.func = @intFromEnum(globals.Function.NoFunc);
        return true;
    }

    for (data.dir_offset[0..8]) |offset| {
        const neighbor_loc: usize = @intCast(obj.loc + offset);
        const c = globals.user_map[neighbor_loc].contents;
        if (std.ascii.isLower(c) or
            c == data.MAP_CITY or
            c == 'X')
        {
            if (!has_destination(obj)) {
                obj.*.func = @intFromEnum(globals.Function.NoFunc);
            }
            return true;
        }
    }
    return false;
}

fn ask_user(obj: *types.piece_info_t) void {
    while (true) {
        display.display_loc_u(obj.loc);
        object.describe_obj(obj);
        display.display_score();
        display.display_loc_u(obj.loc);

        const c = terminal.get_chx();
        switch (c) {
            'Q' => {
                user_direction(obj, .Northwest);
                return;
            },
            'W' => {
                user_direction(obj, .North);
                return;
            },
            'E' => {
                user_direction(obj, .Northeast);
                return;
            },
            'D' => {
                user_direction(obj, .East);
                return;
            },
            'C' => {
                user_direction(obj, .Southeast);
                return;
            },
            'X' => {
                user_direction(obj, .South);
                return;
            },
            'Z' => {
                user_direction(obj, .Southwest);
                return;
            },
            'A' => {
                user_direction(obj, .West);
                return;
            },

            'J' => {
                edit.edit(obj.loc);
                reset_func(obj);
                return;
            },
            'V' => {
                user_set_city_func(obj);
                reset_func(obj);
                return;
            },

            ' ' => {
                user_skip(obj);
                return;
            },
            'F' => {
                user_fill(obj);
                return;
            },
            'I' => {
                user_set_dir(obj);
                return;
            },
            'R' => {
                user_random(obj);
                return;
            },
            'S' => {
                user_sentry(obj);
                return;
            },
            'L' => {
                user_land(obj);
                return;
            },
            'G' => {
                user_explore(obj);
                return;
            },
            'T' => {
                user_transport(obj);
                return;
            },
            'U' => {
                user_repair(obj);
                return;
            },
            'Y' => {
                user_armyattack(obj);
                return;
            },

            'B' => {
                user_build(obj);
            },
            'H' => {
                user_help();
            },
            'K' => {
                user_wake(obj);
            },
            'O' => {
                user_cancel_auto();
            },
            12, 'P' => {
                user_redraw();
            },
            '?' => {
                object.describe_obj(obj);
            },

            else => display.complain(),
        }
    }
}

/// Move a piece at random.  We create a list of empty squares to which
/// the piece can move.  If there are none, we do nothing, otherwise we
/// move the piece to a random adjacent square.
fn move_random(obj: *types.piece_info_t) void {
    var nloc: usize = 0;
    var loc_list: [8]c_long = [_]c_long{0} ** 8;
    for (data.dir_offset[0..8]) |offset| {
        const loc: c_long = obj.loc + offset;
        if (object.good_loc(obj, loc)) {
            loc_list[nloc] = loc;
            nloc += 1;
        }
        if (nloc == 0) return;
        const i: usize = @intCast(math.irand(@intCast(nloc - 1)));
        object.move_obj(obj, loc_list[i]);
    }
}

/// Here we have a transport or carrier waiting to be filled.  If the
/// object is not full, we set the move count to its maximum value.
/// Otherwise we awaken the object.
fn move_fill(obj: *types.piece_info_t) void {
    if (obj.count == object.capacity(obj)) {
        obj.*.func = @intFromEnum(globals.Function.NoFunc);
    } else {
        obj.*.moved = piece_attr(piece_type(obj)).speed;
    }
}

/// Here we have a piece that wants to land at the nearest carrier or
/// owned city.  We scan through the lists of cities and carriers looking
/// for the closest one.  We then move toward that item's location.
/// The nearest landing field must be within the object's range.
fn move_land(obj: *types.piece_info_t) void {
    var best_loc: c_long = 0;
    var best_dist = object.find_nearest_city(obj.loc, @intFromEnum(globals.Ownership.User), &best_loc);
    var p: ?*piece_info_t = globals.user_obj[@intFromEnum(globals.PieceType.Carrier)];
    while (p != null) : (p = p.?.piece_link.next) {
        const carrier = p.?;
        const new_dist = math.dist(obj.loc, carrier.loc);
        if (new_dist < best_dist) {
            best_dist = new_dist;
            best_loc = carrier.loc;
        }
    }

    if (best_dist == 0) {
        obj.*.moved += 1;
    } else if (best_dist <= obj.range) {
        move_to_dest(obj, best_loc);
    } else {
        obj.*.func = @intFromEnum(globals.Function.NoFunc);
    }
}

/// Have a piece explore.  We look for the nearest unexplored territory
/// which the piece can reach and have to piece move toward the
/// territory.
fn move_explore(obj: *types.piece_info_t) void {
    var path_map: [globals.MAP_SIZE]types.path_map_t = undefined;
    const loc_terrain = switch (piece_type(obj)) {
        .Army => .{
            map.vmap_find_lobj(&path_map, &globals.user_map, obj.loc, &globals.user_army),
            "+",
        },
        .Fighter => .{
            map.vmap_find_aobj(&path_map, &globals.user_map, obj.loc, &globals.user_fighter),
            "+.O",
        },
        else => .{
            map.vmap_find_wobj(&path_map, &globals.user_map, obj.loc, &globals.user_ship),
            ".O",
        },
    };
    const loc = loc_terrain.@"0";
    const terrain = loc_terrain.@"1";

    if (loc == obj.loc) return;

    const iloc: usize = @intCast(loc);

    if (globals.user_map[iloc].contents == ' ' and path_map[iloc].cost == 2) {
        map.vmap_mark_adjacent(&path_map, obj.loc);
    } else {
        map.vmap_mark_path(&path_map, &globals.user_map, loc);
    }

    const dest = map.vmap_find_dir(&path_map, &globals.user_map, obj.loc, terrain, " ");
    if (dest != obj.loc) object.move_obj(obj, dest);
}

/// Move an army toward the nearest loading transport.
/// If there is an adjacent transport, move the army onto
/// the transport, and awaken the army.
/// current implementation just panics
fn move_armyload(obj: *types.piece_info_t) void {
    _ = obj;
    std.debug.panic("no implementation for move_armyload. aborting", .{});
}

/// Move an army toward an attackable city or enemy army.
fn move_armyattack(obj: *types.piece_info_t) void {
    if (piece_type(obj) != .Army) {
        std.debug.panic("Army attack invoked for: {s}", .{@tagName(piece_type(obj))});
    }
    var path_map: [globals.MAP_SIZE]types.path_map_t = undefined;
    const loc = map.vmap_find_lobj(
        &path_map,
        &globals.user_map,
        obj.loc,
        &globals.user_army_attack,
    );
    if (loc == obj.loc) return;
    map.vmap_mark_path(&path_map, &globals.user_map, loc);
    const dest = map.vmap_find_dir(
        &path_map,
        &globals.user_map,
        obj.loc,
        "+",
        "X*a",
    );
    if (obj.loc != dest) object.move_obj(obj, dest);
}

/// unclear what this is meant to be, current implementation just panics
fn move_ttload(obj: *types.piece_info_t) void {
    _ = obj;
    std.debug.panic("no implementation for move_ttload", .{});
}

/// Move a ship toward port.  If the ship is healthy, wake it up.
fn move_repair(obj: *types.piece_info_t) void {
    if (obj.type <= @intFromEnum(globals.PieceType.Fighter)) {
        std.debug.panic("Repair invoked for: {s}", .{@tagName(piece_type(obj))});
    }

    if (obj.hits == piece_attr(piece_type(obj)).max_hits) {
        obj.*.func = @intFromEnum(globals.Function.NoFunc);
        return;
    }

    if (globals.user_map[@intCast(obj.loc)].contents == 'O') {
        obj.*.moved += 1;
        return;
    }

    var path_map: [globals.MAP_SIZE]types.path_map_t = undefined;

    const loc = map.vmap_find_wobj(
        &path_map,
        &globals.user_map,
        obj.loc,
        &globals.user_ship_repair,
    );
    if (loc == obj.loc) return;
    map.vmap_mark_path(&path_map, &globals.user_map, loc);
    const dest = map.vmap_find_dir(
        &path_map,
        &globals.user_map,
        obj.loc,
        ".O",
        ".",
    );
    if (obj.loc != dest) object.move_obj(obj, dest);
}

/// Move an army onto a transport when it arrives.  We scan around the
/// army to find a non-full transport.  If one is present, we move the
/// army to the transport and waken the army.
fn move_transport(obj: *types.piece_info_t) void {
    const loc = object.find_transport(@intFromEnum(globals.Ownership.User), obj.loc);
    if (loc != obj.loc) {
        object.move_obj(obj, loc);
        obj.*.func = @intFromEnum(globals.Function.NoFunc);
    } else {
        obj.*.moved = piece_attr(piece_type(obj)).speed;
    }
}
/// Move a piece in the specified direction if possible.
/// If the object is a fighter which has travelled for half its range,
/// we wake it up.
fn move_dir(obj: *types.piece_info_t) void {
    const dir = to_move_dir(function(obj)) catch {
        std.debug.panic("trying to convert a non movement direction function ({s}), to direction", .{@tagName(function(obj))});
    };
    const loc = obj.loc + dir_offset(dir);
    if (object.good_loc(obj, loc)) {
        object.move_obj(obj, loc);
    }
}
extern fn move_path(obj: *types.piece_info_t) void;
extern fn user_dir(obj: *types.piece_info_t, dir: c_int) void;
extern fn reset_func(obj: *types.piece_info_t) void;
extern fn user_set_city_func(obj: *types.piece_info_t) void;
extern fn user_skip(arg_obj: *types.piece_info_t) void;
extern fn user_fill(arg_obj: [*c]piece_info_t) void;
extern fn user_set_dir(arg_obj: [*c]piece_info_t) void;
extern fn user_random(arg_obj: [*c]piece_info_t) void;
extern fn user_sentry(arg_obj: [*c]piece_info_t) void;
extern fn user_land(arg_obj: [*c]piece_info_t) void;
extern fn user_explore(arg_obj: [*c]piece_info_t) void;
extern fn user_transport(arg_obj: [*c]piece_info_t) void;
extern fn user_repair(arg_obj: [*c]piece_info_t) void;
extern fn user_armyattack(arg_obj: [*c]piece_info_t) void;
extern fn user_build(arg_obj: [*c]piece_info_t) void;
extern fn user_help() void;
extern fn user_wake(arg_obj: [*c]piece_info_t) void;
extern fn user_cancel_auto() void;
extern fn user_redraw() void;
extern fn move_to_dest(arg_obj: [*c]piece_info_t, arg_dest: c_long) void;

fn user_direction(obj: *types.piece_info_t, dir: globals.Direction) void {
    user_dir(obj, @intFromEnum(dir));
}

inline fn type_is(obj: *const types.piece_info_t, ptype: globals.PieceType) bool {
    return obj.type == @intFromEnum(ptype);
}

inline fn piece_type(obj: *const types.piece_info_t) globals.PieceType {
    return @enumFromInt(obj.type);
}

inline fn piece_attr(ptype: globals.PieceType) types.piece_attr_t {
    return data.piece_attr[@intCast(@intFromEnum(ptype))];
}

inline fn function(obj: *const types.piece_info_t) globals.Function {
    return @enumFromInt(obj.func);
}

inline fn has_destination(obj: *const types.piece_info_t) bool {
    return obj.func > 0;
}

const DirectionConversionError = error{NotADirectionFunction};

inline fn to_move_dir(func: globals.Function) DirectionConversionError!globals.Direction {
    const n = @intFromEnum(func);
    if (n > @intFromEnum(globals.Function.Move_N)) {
        return @enumFromInt((-1 * n) + @intFromEnum(globals.Function.Move_N));
    } else return DirectionConversionError.NotADirectionFunction;
}

inline fn dir_offset(dir: globals.Direction) c_int {
    return data.dir_offset[@intCast(@intFromEnum(dir))];
}
