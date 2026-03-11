const std = @import("std");
const globals = @import("globals.zig");
const object = @import("object.zig");
const types = @import("types.zig");
const Piece = types.Piece;
const PieceIdx = types.PieceIdx;
const NO_PIECE = types.NO_PIECE;
const LIST_SIZE = globals.LIST_SIZE;
const data = @import("data.zig");
const terminal = @import("terminal.zig");
const display = @import("display.zig");
const util = @import("util.zig");
const game = @import("game.zig");
const map = @import("map.zig");
const edit = @import("edit.zig");
const math = @import("math.zig");
const attack = @import("attack.zig");

pub fn move() void {
    // reset moved for units
    for (&globals.pool) |*piece| {
        if (piece.alive and piece.owner == @intFromEnum(globals.Ownership.User)) {
            piece.moved = 0;
            object.scan(&globals.user_map, piece.loc);
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
                    terminal.ksend("{s} has been completed at city {d}.\n", .{ std.mem.sliceTo(&data.piece_attr[prod].article, 0), terminal.loc_disp(@intCast(city.loc)) });
                    terminal.comment("{s} has been completed at city {d}.", .{ std.mem.sliceTo(&data.piece_attr[prod].article, 0), terminal.loc_disp(@intCast(city.loc)) });

                    object.produce(city);
                }
            }
        }
    }

    for (&globals.pool) |*piece| {
        if (piece.alive and piece.owner == @intFromEnum(globals.Ownership.User) and
            piece.type == @intFromEnum(globals.PieceType.Satellite))
        {
            object.move_sat(piece);
        }
    }

    var sec_start = display.cur_sector();
    if (sec_start < 0) sec_start = 0;
    const start: usize = @intCast(sec_start);
    const end: usize = start + globals.NUM_SECTORS;

    for (start..end) |i| {
        const sec = @rem(i, globals.NUM_SECTORS);
        display.sector_change();
        for (data.move_order[0..globals.NUM_OBJECTS]) |j| {
            for (&globals.pool) |*piece| {
                if (piece.alive and piece.owner == @intFromEnum(globals.Ownership.User) and
                    piece.type == j and piece.moved == 0 and util.loc_sector(piece.loc) == sec)
                {
                    piece_move(piece);
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
fn piece_move(obj: *Piece) void {
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
                terminal.comment("Landing confirmed", .{});
            } else if (obj.range == 0) {
                terminal.comment("Fighter at {d} crashed and burned.", .{terminal.loc_disp(@intCast(obj.loc))});
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

pub fn awake(obj: *Piece) bool {
    if (type_is(obj, .Army) and
        map.vmap_at_sea(&globals.user_map, obj.loc))
    {
        obj.*.moved = @intCast(piece_attr(.Army).range);
        return false;
    }

    if (function(obj) == .NoFunc) return true;

    var city_loc: i64 = undefined;

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

fn ask_user(obj: *Piece) void {
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
pub fn move_random(obj: *Piece) void {
    var nloc: usize = 0;
    var loc_list: [8]i64 = [_]i64{0} ** 8;
    for (data.dir_offset[0..8]) |offset| {
        const loc: i64 = obj.loc + offset;
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
pub fn move_fill(obj: *Piece) void {
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
pub fn move_land(obj: *Piece) void {
    var best_loc: i64 = 0;
    var best_dist = object.find_nearest_city(obj.loc, @intFromEnum(globals.Ownership.User), &best_loc);
    for (&globals.pool) |*piece| {
        if (piece.alive and piece.owner == @intFromEnum(globals.Ownership.User) and
            piece.type == @intFromEnum(globals.PieceType.Carrier))
        {
            const new_dist = math.dist(obj.loc, piece.loc);
            if (new_dist < best_dist) {
                best_dist = new_dist;
                best_loc = piece.loc;
            }
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
pub fn move_explore(obj: *Piece) void {
    var path_map: [globals.MAP_SIZE]types.path_map_t = undefined;
    const loc_terrain = switch (piece_type(obj)) {
        .Army => .{
            map.vmap_find_lobj(&path_map, &globals.user_map, obj.loc, &data.user_army),
            "+",
        },
        .Fighter => .{
            map.vmap_find_aobj(&path_map, &globals.user_map, obj.loc, &data.user_fighter),
            "+.O",
        },
        else => .{
            map.vmap_find_wobj(&path_map, &globals.user_map, obj.loc, &data.user_ship),
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
pub fn move_armyload(obj: *Piece) void {
    _ = obj;
    std.debug.panic("no implementation for move_armyload. aborting", .{});
}

/// Move an army toward an attackable city or enemy army.
pub fn move_armyattack(obj: *Piece) void {
    if (piece_type(obj) != .Army) {
        std.debug.panic("Army attack invoked for: {s}", .{@tagName(piece_type(obj))});
    }
    var path_map: [globals.MAP_SIZE]types.path_map_t = undefined;
    const loc = map.vmap_find_lobj(
        &path_map,
        &globals.user_map,
        obj.loc,
        &data.user_army_attack,
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
pub fn move_ttload(obj: *Piece) void {
    _ = obj;
    std.debug.panic("no implementation for move_ttload", .{});
}

/// Move a ship toward port.  If the ship is healthy, wake it up.
pub fn move_repair(obj: *Piece) void {
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
        &data.user_ship_repair,
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
pub fn move_transport(obj: *Piece) void {
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
pub fn move_dir(obj: *Piece) void {
    const dir = to_move_dir(function(obj)) catch {
        std.debug.panic("trying to convert a non movement direction function ({s}), to direction", .{@tagName(function(obj))});
    };
    const loc = obj.loc + dir_offset(dir);
    if (object.good_loc(obj, loc)) {
        object.move_obj(obj, loc);
    }
}

/// Move a piece toward a specified destination if possible.  For each
/// direction, we see if moving in that direction would bring us closer
/// to our destination, and if there is nothing in the way.  If so, we
/// move in the first direction we find.
pub fn move_path(obj: *Piece) void {
    if (obj.loc == obj.func) {
        obj.func = @intFromEnum(globals.Function.NoFunc);
    } else {
        object.move_obj(obj, obj.func);
    }
}

/// Move a piece toward a specific destination.  We first map out
/// the paths to the destination, if we can't get there, we return.
/// Then we mark the paths to the destination.  Then we choose a
/// move.
fn move_to_dest(obj: *Piece, dest: i64) void {
    var path_map: [globals.MAP_SIZE]types.path_map_t = undefined;
    const fm_terrain = switch (piece_type(obj)) {
        .Army => .{
            @intFromEnum(globals.Terrain.Land),
            "+",
        },
        .Fighter => .{
            @intFromEnum(globals.Terrain.Air),
            "+.O",
        },
        else => .{
            @intFromEnum(globals.Terrain.Water),
            ".O",
        },
    };
    const fterrain = fm_terrain.@"0";
    const mterrain = fm_terrain.@"1";

    const loc = map.vmap_find_dest(&path_map, &globals.user_map, obj.loc, dest, @intFromEnum(globals.Ownership.User), fterrain);

    if (loc == obj.loc) return;

    map.vmap_mark_path(&path_map, &globals.user_map, dest);

    const new_loc = map.vmap_find_dir(&path_map, &globals.user_map, obj.loc, mterrain, " .");
    if (!object.good_loc(obj, new_loc)) {
        std.debug.panic("location is not suitable for the object", .{});
    }
    object.move_obj(obj, new_loc);
}
fn user_direction(obj: *Piece, dir: globals.Direction) void {
    user_dir(obj, dir);
}

pub fn reset_func(obj: *Piece) void {
    const maybe_cityp = object.find_city(obj.loc);
    if (maybe_cityp) |cityp| {
        const func = cityp.*.func[@intCast(obj.type)];
        if (func != @intFromEnum(globals.Function.NoFunc)) {
            obj.*.func = func;
            _ = awake(obj);
        }
    }
}

pub fn user_skip(obj: *Piece) void {
    if (obj.type == @intFromEnum(globals.PieceType.Army) and
        globals.user_map[@intCast(obj.loc)].contents == 'O')
    {
        move_army_to_city(obj, obj.loc);
    } else {
        obj.*.moved += 1;
    }
}

pub fn user_fill(obj: *Piece) void {
    if (obj.type != @intFromEnum(globals.PieceType.Transport) and
        obj.type != @intFromEnum(globals.PieceType.Carrier))
    {
        display.complain();
    } else {
        obj.*.func = @intFromEnum(globals.Function.Fill);
    }
}

fn user_help() void {
    terminal.help(&data.help_user, data.user_lines);
    terminal.prompt("Press any key to continue: ", .{});
    _ = terminal.get_chx();
}

fn user_set_dir(obj: *Piece) void {
    const c = terminal.get_chx();
    const func: ?globals.Function = switch (c) {
        'Q' => .Move_NW,
        'W' => .Move_N,
        'E' => .Move_NE,
        'D' => .Move_E,
        'C' => .Move_SE,
        'X' => .Move_S,
        'Z' => .Move_SW,
        'A' => .Move_W,
        else => null,
    };
    if (func) |f| {
        obj.*.func = @intFromEnum(f);
    } else {
        display.complain();
    }
}

pub fn user_wake(obj: *Piece) void {
    obj.*.func = @intFromEnum(globals.Function.NoFunc);
}

pub fn user_random(obj: *Piece) void {
    obj.*.func = @intFromEnum(globals.Function.Random);
}

pub fn user_sentry(obj: *Piece) void {
    obj.*.func = @intFromEnum(globals.Function.Sentry);
}

pub fn user_land(obj: *Piece) void {
    if (obj.type != @intFromEnum(globals.PieceType.Fighter)) {
        display.complain();
    } else {
        obj.*.func = @intFromEnum(globals.Function.Land);
    }
}

pub fn user_explore(obj: *Piece) void {
    obj.*.func = @intFromEnum(globals.Function.Explore);
}

pub fn user_transport(obj: *Piece) void {
    if (obj.type != @intFromEnum(globals.PieceType.Army)) {
        display.complain();
    } else {
        obj.*.func = @intFromEnum(globals.Function.WFTransport);
    }
}

pub fn user_armyattack(obj: *Piece) void {
    if (obj.type != @intFromEnum(globals.PieceType.Army)) {
        display.complain();
    } else {
        obj.*.func = @intFromEnum(globals.Function.ArmyAttack);
    }
}

pub fn user_repair(obj: *Piece) void {
    if (obj.type == @intFromEnum(globals.PieceType.Army) or
        obj.type == @intFromEnum(globals.PieceType.Fighter))
    {
        display.complain();
    } else {
        obj.*.func = @intFromEnum(globals.Function.Repair);
    }
}

fn user_set_city_func(obj: *Piece) void {
    const cityp = object.find_city(obj.loc);
    if (cityp == null or cityp.*.owner != @intFromEnum(globals.Ownership.User)) {
        display.complain();
        return;
    }

    const piece_t = object.get_piece_name();
    if (piece_t == @intFromEnum(globals.PieceType.NoPiece)) {
        display.complain();
        return;
    }

    const e = terminal.get_chx();
    switch (e) {
        'F' => edit.e_city_fill(cityp, piece_t),
        'G' => edit.e_city_explore(cityp, piece_t),
        'I' => edit.e_city_stasis(cityp, piece_t),
        'K' => edit.e_city_wake(cityp, piece_t),
        'R' => edit.e_city_random(cityp, piece_t),
        'U' => edit.e_city_repair(cityp, piece_t),
        'Y' => edit.e_city_attack(cityp, piece_t),
        else => display.complain(),
    }
}

fn user_build(obj: *Piece) void {
    if (globals.user_map[@intCast(obj.loc)].contents != 'O') {
        display.complain();
        return;
    }
    const cityp = object.find_city(obj.loc);
    std.debug.assert(cityp != null);
    object.set_prod(cityp);
}

fn user_dir(obj: *Piece, dir: globals.Direction) void {
    const loc = obj.loc + dir_offset(dir);

    if (object.good_loc(obj, loc)) {
        object.move_obj(obj, loc);
        return;
    }
    if (!globals.map[@intCast(loc)].on_board) {
        terminal.@"error"("You cannot move to the edge of the world.", .{});
        display.delay();
        return;
    }
    switch (@as(globals.PieceType, @enumFromInt(obj.type))) {
        .Army => user_dir_army(obj, loc),
        .Fighter => user_dir_fighter(obj, loc),
        else => user_dir_ship(obj, loc),
    }
}

fn user_dir_army(obj: *Piece, loc: i64) void {
    const uloc: usize = @intCast(loc);
    const obj_uloc: usize = @intCast(obj.loc);

    if (globals.user_map[uloc].contents == 'O') {
        move_army_to_city(obj, loc);
    } else if (globals.user_map[uloc].contents == 'T') {
        fatal(obj, loc, "Sorry, sir.  There is no more room on the transport.  Do you insist? ", "Your army jumped into the briny and drowned.");
    } else if (globals.map[uloc].contents == data.MAP_SEA) {
        var enemy_killed = false;

        if (!terminal.getyn("Troops can't walk on water, sir.  Do you really want to go to sea? "))
            return;

        if (globals.user_map[obj_uloc].contents == 'T') {
            terminal.comment("Your army jumped into the briny and drowned.", .{});
            terminal.ksend("Your army jumped into the briny and drowned.\n", .{});
        } else if (globals.user_map[uloc].contents == data.MAP_SEA) {
            terminal.comment("Your army marched dutifully into the sea and drowned.", .{});
            terminal.ksend("Your army marched dutifully into the sea and drowned.\n", .{});
        } else {
            enemy_killed = std.ascii.isLower(globals.user_map[uloc].contents);
            attack.attack(obj, loc);

            if (obj.hits > 0) {
                terminal.comment("Your army regretfully drowns after its successful assault.", .{});
                terminal.ksend("Your army regretfully drowns after its successful assault.\n", .{});
            }
        }
        if (obj.hits > 0) {
            object.kill_obj(obj, loc);
            if (enemy_killed) object.scan(&globals.comp_map, loc);
        }
    } else if (std.ascii.isUpper(globals.user_map[uloc].contents) and
        globals.user_map[uloc].contents != 'X')
    {
        if (!terminal.getyn("Sir, those are our men!  Do you really want to attack them? "))
            return;
        attack.attack(obj, loc);
    } else {
        attack.attack(obj, loc);
    }
}

fn user_dir_fighter(obj: *Piece, loc: i64) void {
    const uloc: usize = @intCast(loc);

    if (globals.map[uloc].contents == data.MAP_CITY) {
        fatal(obj, loc, "That's never worked before, sir.  Do you really want to try? ", "Your fighter was shot down.");
    } else if (std.ascii.isUpper(globals.user_map[uloc].contents)) {
        if (!terminal.getyn("Sir, those are our men!  Do you really want to attack them? "))
            return;
        attack.attack(obj, loc);
    } else {
        attack.attack(obj, loc);
    }
}

fn user_dir_ship(obj: *Piece, loc: i64) void {
    const uloc: usize = @intCast(loc);
    const name = std.mem.sliceTo(&data.piece_attr[@intCast(obj.type)].name, 0);

    if (globals.map[uloc].contents == data.MAP_CITY) {
        if (terminal.getyn("That's never worked before, sir.  Do you really want to try? ")) {
            terminal.comment("Your {s} broke up on shore.", .{name});
            object.kill_obj(obj, loc);
        }
    } else if (globals.map[uloc].contents == data.MAP_LAND) {
        var enemy_killed = false;

        if (!terminal.getyn("Ships need sea to float, sir.  Do you really want to go ashore? "))
            return;

        if (globals.user_map[uloc].contents == data.MAP_LAND) {
            terminal.comment("Your {s} broke up on shore.", .{name});
            terminal.ksend("Your {s} broke up on shore.\n", .{name});
        } else {
            enemy_killed = std.ascii.isLower(globals.user_map[uloc].contents);
            attack.attack(obj, loc);

            if (obj.hits > 0) {
                terminal.comment("Your {s} breaks up after its successful assault.", .{name});
                terminal.ksend("Your {s} breaks up after its successful assault.\n", .{name});
            }
        }
        if (obj.hits > 0) {
            object.kill_obj(obj, loc);
            if (enemy_killed) object.scan(&globals.comp_map, loc);
        }
    } else if (std.ascii.isUpper(globals.user_map[uloc].contents)) {
        if (!terminal.getyn("Sir, those are our men!  Do you really want to attack them? "))
            return;
        attack.attack(obj, loc);
    } else {
        attack.attack(obj, loc);
    }
}

fn move_army_to_city(obj: *Piece, city_loc: i64) void {
    const tt = object.find_nfull(@intFromEnum(globals.PieceType.Transport), city_loc);
    if (tt != null) {
        object.move_obj(obj, city_loc);
    } else {
        fatal(obj, city_loc, "That's our city, sir!  Do you really want to attack the garrison? ", "Your rebel army was liquidated.");
    }
}

pub fn user_cancel_auto() void {
    if (!globals.automove) {
        terminal.comment("Not in auto mode!", .{});
    } else {
        globals.automove = false;
        terminal.comment("Auto mode cancelled.", .{});
    }
}

fn user_redraw() void {
    display.redraw();
}

fn fatal(obj: *Piece, loc: i64, message: [*:0]const u8, comptime response: []const u8) void {
    if (terminal.getyn(message)) {
        terminal.comment(response, .{});
        object.kill_obj(obj, loc);
    }
}

inline fn type_is(obj: *const Piece, ptype: globals.PieceType) bool {
    return obj.type == @intFromEnum(ptype);
}

inline fn piece_type(obj: *const Piece) globals.PieceType {
    return @enumFromInt(obj.type);
}

inline fn piece_attr(ptype: globals.PieceType) types.piece_attr_t {
    return data.piece_attr[@intCast(@intFromEnum(ptype))];
}

inline fn function(obj: *const Piece) globals.Function {
    return @enumFromInt(obj.func);
}

inline fn has_destination(obj: *const Piece) bool {
    return obj.func > 0;
}

const DirectionConversionError = error{NotADirectionFunction};

inline fn to_move_dir(func: globals.Function) DirectionConversionError!globals.Direction {
    const n = @intFromEnum(func);
    if (n > @intFromEnum(globals.Function.Move_N)) {
        return @enumFromInt((-1 * n) + @intFromEnum(globals.Function.Move_N));
    } else return DirectionConversionError.NotADirectionFunction;
}

pub inline fn dir_offset(dir: globals.Direction) i32 {
    return data.dir_offset[@intCast(@intFromEnum(dir))];
}
