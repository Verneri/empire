const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const object = @import("object.zig");
const display = @import("display.zig");
const terminal = @import("terminal.zig");
const attack_mod = @import("attack.zig");
const game = @import("game.zig");
const util = @import("util.zig");
const map = @import("map.zig");
const math = @import("math.zig");

const view_map_t = types.view_map_t;
const path_map_t = types.path_map_t;
const piece_info_t = types.piece_info_t;
const city_info_t = types.city_info_t;
const scan_counts_t = types.scan_counts_t;

const MAP_SIZE = globals.MAP_SIZE;
const MAP_WIDTH = globals.MAP_WIDTH;
const MAP_HEIGHT = globals.MAP_HEIGHT;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const NUM_CITY = globals.NUM_CITY;
const MAP_SEA = data.MAP_SEA;
const MAP_LAND = data.MAP_LAND;
const MAP_CITY = data.MAP_CITY;
const INFINITY: c_int = 10000000;

const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);
const ARMY = @intFromEnum(globals.PieceType.Army);
const FIGHTER = @intFromEnum(globals.PieceType.Fighter);
const TRANSPORT = @intFromEnum(globals.PieceType.Transport);
const SATELLITE = @intFromEnum(globals.PieceType.Satellite);
const NOPIECE = @intFromEnum(globals.PieceType.NoPiece);

const T_UNKNOWN: c_int = 0;
const T_AIR: c_int = 6;

// Win condition constants (from enum win_t)
const ratio_win: c_int = 2;
const wipeout_win: c_int = 1;

// ============================================================
// Static data
// ============================================================

var emap: [MAP_SIZE]view_map_t = std.mem.zeroes([MAP_SIZE]view_map_t);
var amap: [MAP_SIZE]view_map_t = std.mem.zeroes([MAP_SIZE]view_map_t);
var path_map_buf: [MAP_SIZE]path_map_t = std.mem.zeroes([MAP_SIZE]path_map_t);
var owncont_map: [MAP_SIZE]c_int = std.mem.zeroes([MAP_SIZE]c_int);
var tcont_map: [MAP_SIZE]c_int = std.mem.zeroes([MAP_SIZE]c_int);

// Production ratios
//                                   A    F    P    S    D    T    C    B   Z
const ratio1 = [NUM_OBJECTS]c_int{ 60, 0, 10, 0, 0, 20, 0, 0, 0 };
const ratio2 = [NUM_OBJECTS]c_int{ 90, 10, 10, 10, 10, 40, 0, 0, 0 };
const ratio3 = [NUM_OBJECTS]c_int{ 120, 20, 20, 10, 10, 60, 10, 10, 0 };
const ratio4 = [NUM_OBJECTS]c_int{ 150, 30, 30, 20, 20, 70, 10, 10, 0 };

var ratio: [*]const c_int = &ratio1;

// Helper: check if char is in a null-terminated C string
fn char_in(c: u8, set: [*c]const u8) ?usize {
    var i: usize = 0;
    while (set[i] != 0) : (i += 1) {
        if (set[i] == c) return i;
    }
    return null;
}

// ============================================================
// Main entry point
// ============================================================

pub export fn comp_move(nmoves: c_int) void {
    var i: c_int = undefined;
    var obj: [*c]piece_info_t = undefined;

    // Update our view of the world.
    i = 0;
    while (i < NUM_OBJECTS) : (i += 1) {
        obj = globals.comp_obj[@intCast(i)];
        while (obj != null) : (obj = obj.*.piece_link.next) {
            object.scan(&globals.comp_map, obj.*.loc);
        }
    }

    i = 1;
    while (i <= nmoves) : (i += 1) {
        terminal.comment("Thinking...");

        @memcpy(&emap, &globals.comp_map);
        map.vmap_prune_explore_locs(&emap);

        do_cities();
        do_pieces();

        if (globals.save_movie) game.save_movie_screen();
        check_endgame();

        terminal.topini();
        display.redisplay();
    }
}

// ============================================================
// City production
// ============================================================

fn do_cities() void {
    var i: usize = 0;
    while (i < NUM_CITY) : (i += 1) {
        if (globals.city[i].owner == COMP) {
            object.scan(&globals.comp_map, globals.city[i].loc);
            if (globals.city[i].prod == NOPIECE)
                comp_prod(&globals.city[i], lake(globals.city[i].loc));
        }
    }
    i = 0;
    while (i < NUM_CITY) : (i += 1) {
        if (globals.city[i].owner == COMP) {
            const is_lake = lake(globals.city[i].loc);
            globals.city[i].work += 1;
            if (globals.city[i].work >= @as(c_long, data.piece_attr[@intCast(globals.city[i].prod)].build_time)) {
                object.produce(&globals.city[i]);
                comp_prod(&globals.city[i], is_lake);
            } else if (globals.city[i].prod > FIGHTER and globals.city[i].prod != SATELLITE and is_lake) {
                comp_prod(&globals.city[i], is_lake);
            }
        }
    }
}

fn comp_prod(cityp: [*c]city_info_t, is_lake: bool) void {
    var city_count: [NUM_OBJECTS]c_int = std.mem.zeroes([NUM_OBJECTS]c_int);
    var cont_map: [MAP_SIZE]c_int = undefined;
    var total_cities: c_int = undefined;
    var i: usize = undefined;

    // Map out city's continent
    map.vmap_cont(&cont_map, &globals.comp_map, cityp.*.loc, MAP_SEA);

    // Count items of interest on the continent
    const counts: scan_counts_t = map.vmap_cont_scan(&cont_map, &globals.comp_map);
    var comp_ac: c_int = 0;

    i = 0;
    while (i < MAP_SIZE) : (i += 1) {
        if (cont_map[i] != 0) {
            if (globals.comp_map[i].contents == 'X') {
                const p = object.find_city(@intCast(i));
                std.debug.assert(p != null and p.*.owner == COMP);
                if (p.*.prod == ARMY) comp_ac += 1;
            }
        }
    }

    // See if anything of interest is on continent
    var interest: c_int = @intFromBool(counts.unexplored != 0 or counts.user_cities != 0 or
        counts.user_objects[ARMY] != 0 or counts.unowned_cities != 0);

    // We want one more army producer than enemy has cities + interest
    var need_count: c_int = counts.user_cities - comp_ac + interest;
    if (counts.user_cities != 0) need_count += 1;

    if (need_count > 0) {
        comp_set_prod(cityp, ARMY);
        return;
    }

    // Produce armies in new cities if there is a city to attack.
    if (counts.user_cities != 0 and cityp.*.prod == NOPIECE) {
        comp_set_prod(cityp, ARMY);
        return;
    }

    // Count # of cities producing each piece
    i = 0;
    while (i < NUM_OBJECTS) : (i += 1) city_count[i] = 0;

    total_cities = 0;

    i = 0;
    while (i < NUM_CITY) : (i += 1) {
        if (globals.city[i].owner == COMP and globals.city[i].prod != NOPIECE) {
            city_count[@intCast(globals.city[i].prod)] += 1;
            total_cities += 1;
        }
    }

    if (total_cities <= 10)
        ratio = &ratio1
    else if (total_cities <= 20)
        ratio = &ratio2
    else if (total_cities <= 30)
        ratio = &ratio3
    else
        ratio = &ratio4;

    // If we have one army producer, and this is it, return
    if (city_count[ARMY] == 1 and cityp.*.prod == ARMY) return;

    // First available non-lake becomes a tt producer
    if (city_count[TRANSPORT] == 0) {
        if (!is_lake) {
            comp_set_prod(cityp, TRANSPORT);
            return;
        }
        if (city_count[ARMY] == 1) {
            i = 0;
            while (i < NUM_CITY) : (i += 1) {
                if (globals.city[i].owner == COMP and globals.city[i].prod == ARMY) break;
            }
            if (!lake(globals.city[i].loc)) {
                comp_set_prod(cityp, ARMY);
                return;
            }
        }
    }

    // Don't change prod from armies if something on continent
    if (cityp.*.prod == ARMY and interest != 0) return;

    // Produce armies in new cities if there is a city to attack.
    if (counts.unowned_cities != 0 and cityp.*.prod == NOPIECE) {
        comp_set_prod(cityp, ARMY);
        return;
    }

    // Set production to item most needed
    interest = @intFromBool(counts.comp_cities != 1 or interest != 0);

    if (cityp.*.prod == NOPIECE or
        (cityp.*.prod == ARMY and counts.comp_cities == 1) or
        overproduced(cityp, &city_count) or (cityp.*.prod > FIGHTER and is_lake))
        comp_set_needed(cityp, &city_count, interest != 0, is_lake);
}

fn comp_set_prod(cityp: [*c]city_info_t, prod_type: c_int) void {
    if (cityp.*.prod == prod_type) return;

    terminal.pdebug("Changing city prod at %d from %d to %d\n", terminal.loc_disp(@intCast(cityp.*.loc)), cityp.*.prod, prod_type);
    cityp.*.prod = @intCast(prod_type);
    cityp.*.work = -@divTrunc(@as(c_long, data.piece_attr[@intCast(prod_type)].build_time), 5);
}

fn overproduced(cityp: [*c]city_info_t, city_count: [*c]c_int) bool {
    var i: c_int = 0;
    while (i < NUM_OBJECTS) : (i += 1) {
        if (i != cityp.*.prod and
            ((city_count[@intCast(cityp.*.prod)] - 1) * ratio[@intCast(i)] >
            (city_count[@intCast(i)] + 1) * ratio[@intCast(cityp.*.prod)]))
            return true;
    }
    return false;
}

fn need_more(city_count: [*c]c_int, prod1: c_int, prod2: c_int) c_int {
    if (city_count[@intCast(prod1)] * ratio[@intCast(prod2)] <=
        city_count[@intCast(prod2)] * ratio[@intCast(prod1)])
        return prod1
    else
        return prod2;
}

fn comp_set_needed(cityp: [*c]city_info_t, city_count: [*c]c_int, army_ok: bool, is_lake: bool) void {
    if (!army_ok) city_count[ARMY] = INFINITY;

    if (is_lake) {
        comp_set_prod(cityp, need_more(city_count, ARMY, FIGHTER));
        return;
    }
    // Don't choose fighter
    city_count[FIGHTER] = INFINITY;

    var best_prod: c_int = ARMY;
    var prod: c_int = 0;
    while (prod < NUM_OBJECTS) : (prod += 1) {
        best_prod = need_more(city_count, best_prod, prod);
    }
    comp_set_prod(cityp, best_prod);
}

fn lake(loc: c_long) bool {
    var cont_map_buf: [MAP_SIZE]c_int = undefined;
    map.vmap_cont(&cont_map_buf, &emap, loc, MAP_LAND);
    const counts = map.vmap_cont_scan(&cont_map_buf, &emap);
    return !(counts.unowned_cities != 0 or counts.user_cities != 0 or counts.unexplored != 0);
}

// ============================================================
// Piece movement
// ============================================================

fn do_pieces() void {
    var i: usize = 0;
    while (i < NUM_OBJECTS) : (i += 1) {
        var obj: [*c]piece_info_t = globals.comp_obj[@intCast(data.move_order[i])];
        while (obj != null) {
            const next_obj = obj.*.piece_link.next;
            cpiece_move(obj);
            obj = next_obj;
        }
    }
}

fn cpiece_move(obj: [*c]piece_info_t) void {
    if (obj.*.type == SATELLITE) {
        object.move_sat(obj);
        return;
    }

    obj.*.moved = 0;
    var changed_loc: bool = false;
    const max_hits: c_int = @intCast(data.piece_attr[@intCast(obj.*.type)].max_hits);

    if (obj.*.type == FIGHTER) {
        const cityp = object.find_city(obj.*.loc);
        if (cityp != null) obj.*.range = @intCast(data.piece_attr[FIGHTER].range);
    }

    while (obj.*.moved < object.obj_moves(obj)) {
        const saved_loc = obj.*.loc;
        move1(obj);
        if (saved_loc != obj.*.loc) changed_loc = true;

        if (obj.*.type == FIGHTER and obj.*.hits > 0) {
            if (globals.comp_map[@intCast(obj.*.loc)].contents == 'X')
                obj.*.moved = @intCast(data.piece_attr[FIGHTER].speed)
            else if (obj.*.range == 0) {
                terminal.pdebug("Fighter at %d crashed and burned\n", terminal.loc_disp(@intCast(obj.*.loc)));
                terminal.ksend("Fighter at %d crashed and burned\n", terminal.loc_disp(@intCast(obj.*.loc)));
                object.kill_obj(obj, obj.*.loc);
            }
        }
    }
    // If a boat is in port, damaged, and never moved, fix some damage
    if (obj.*.hits > 0 and
        !changed_loc and
        obj.*.type != ARMY and obj.*.type != FIGHTER and
        obj.*.hits != max_hits and
        globals.comp_map[@intCast(obj.*.loc)].contents == 'X')
        obj.*.hits += 1;
}

fn move1(obj: [*c]piece_info_t) void {
    switch (obj.*.type) {
        ARMY => army_move(obj),
        TRANSPORT => transport_move(obj),
        FIGHTER => fighter_move(obj),
        else => ship_move(obj),
    }
}

// ============================================================
// Army movement
// ============================================================

fn army_move(obj: [*c]piece_info_t) void {
    var new_loc: c_long = undefined;
    var path_map2: [MAP_SIZE]path_map_t = undefined;
    var cross_cost: c_int = 0;

    obj.*.func = 0;
    if (map.vmap_at_sea(&globals.comp_map, obj.*.loc)) {
        _ = load_army(obj);
        obj.*.moved = @intCast(data.piece_attr[ARMY].speed);
        if (obj.*.ship == null) obj.*.func = 1;
        return;
    }

    if (obj.*.ship != null)
        new_loc = find_attack(obj.*.loc, &data.army_attack, "+*")
    else
        new_loc = find_attack(obj.*.loc, &data.army_attack, ".+*");

    if (new_loc != obj.*.loc) {
        attack_mod.attack(obj, new_loc);
        if (globals.map[@intCast(new_loc)].contents == MAP_SEA and obj.*.hits > 0) {
            object.kill_obj(obj, new_loc);
            object.scan(&globals.user_map, new_loc);
        }
        return;
    }

    if (obj.*.ship != null) {
        if (obj.*.ship.*.func == 0) {
            if (!load_army(obj)) unreachable;
            return;
        }
        make_unload_map(&amap, &globals.comp_map);
        new_loc = map.vmap_find_wlobj(&path_map_buf, &amap, obj.*.loc, &data.tt_unload);
        move_objective(obj, &path_map_buf, new_loc, " ");
        return;
    }

    new_loc = map.vmap_find_lobj(&path_map_buf, &globals.comp_map, obj.*.loc, &data.army_fight);

    if (new_loc != obj.*.loc) {
        switch (globals.comp_map[@intCast(new_loc)].contents) {
            'A', 'O' => cross_cost = 60,
            MAP_CITY => cross_cost = 30,
            ' ' => cross_cost = 14,
            else => unreachable,
        }
        cross_cost = path_map_buf[@intCast(new_loc)].cost * 2 - cross_cost;
    } else {
        cross_cost = INFINITY;
    }

    if (new_loc == obj.*.loc or cross_cost > 0) {
        // See if there is something interesting to load
        make_army_load_map(obj, &amap, &globals.comp_map);
        const new_loc2 = map.vmap_find_lwobj(&path_map2, &amap, obj.*.loc, &data.army_load, cross_cost);

        if (new_loc2 != obj.*.loc) {
            board_ship(obj, &path_map2, new_loc2);
            return;
        }
    }

    move_objective(obj, &path_map_buf, new_loc, " ");
}

fn unmark_explore_locs(xmap: [*c]view_map_t) void {
    var i: usize = 0;
    while (i < MAP_SIZE) : (i += 1) {
        if (globals.map[i].on_board and xmap[i].contents == ' ')
            xmap[i].contents = emap[i].contents;
    }
}

fn make_army_load_map(obj: [*c]piece_info_t, xmap: [*c]view_map_t, vmap: [*c]view_map_t) void {
    @memcpy(xmap[0..MAP_SIZE], vmap[0..MAP_SIZE]);

    // Mark loading transports or cities building transports
    var p: [*c]piece_info_t = globals.comp_obj[TRANSPORT];
    while (p != null) : (p = p.*.piece_link.next) {
        if (p.*.func == 0)
            xmap[@intCast(p.*.loc)].contents = '$';
    }

    var i: usize = 0;
    while (i < NUM_CITY) : (i += 1) {
        if (globals.city[i].owner == COMP and globals.city[i].prod == TRANSPORT) {
            if (nearby_load(obj, globals.city[i].loc))
                xmap[@intCast(globals.city[i].loc)].contents = 'x'
            else if (nearby_count(globals.city[i].loc) < @as(c_int, data.piece_attr[TRANSPORT].capacity))
                xmap[@intCast(globals.city[i].loc)].contents = 'x';
        }
    }

    if (globals.print_vmap == 'A') display.print_xzoom(xmap);
}

fn nearby_load(obj: [*c]piece_info_t, loc: c_long) bool {
    return obj.*.func == 1 and math.dist(obj.*.loc, loc) <= 2;
}

fn nearby_count(loc: c_long) c_int {
    var count: c_int = 0;
    var obj: [*c]piece_info_t = globals.comp_obj[ARMY];
    while (obj != null) : (obj = obj.*.piece_link.next) {
        if (nearby_load(obj, loc)) count += 1;
    }
    return count;
}

fn make_tt_load_map(xmap: [*c]view_map_t, vmap: [*c]view_map_t) void {
    @memcpy(xmap[0..MAP_SIZE], vmap[0..MAP_SIZE]);

    var p: [*c]piece_info_t = globals.comp_obj[ARMY];
    while (p != null) : (p = p.*.piece_link.next) {
        if (p.*.func == 1)
            xmap[@intCast(p.*.loc)].contents = '$';
    }

    if (globals.print_vmap == 'L') display.print_xzoom(xmap);
}

fn make_unload_map(xmap: [*c]view_map_t, vmap: [*c]view_map_t) void {
    @memcpy(xmap[0..MAP_SIZE], vmap[0..MAP_SIZE]);
    unmark_explore_locs(xmap);

    @memset(&owncont_map, 0);

    var i: usize = 0;
    while (i < NUM_CITY) : (i += 1) {
        if (globals.city[i].owner == COMP)
            map.vmap_mark_up_cont(&owncont_map, xmap, globals.city[i].loc, MAP_SEA);
    }

    i = 0;
    while (i < MAP_SIZE) : (i += 1) {
        if (char_in(vmap[i].contents, "O*") != null) {
            map.vmap_cont(&tcont_map, xmap, @intCast(i), MAP_SEA);
            const counts = map.vmap_cont_scan(&tcont_map, xmap);

            var total_cities: c_int = counts.unowned_cities + counts.user_cities + counts.comp_cities;

            if (total_cities > 9) total_cities = 0;

            if (counts.user_cities != 0 and counts.comp_cities != 0)
                xmap[i].contents = @intCast(@as(c_int, '0') + total_cities)
            else if (counts.unowned_cities > counts.user_cities and counts.comp_cities == 0)
                xmap[i].contents = @intCast(@as(c_int, '0') + total_cities)
            else if (counts.user_cities == 1 and counts.comp_cities == 0)
                xmap[i].contents = '2'
            else
                xmap[i].contents = '0';
        }
    }
    if (globals.print_vmap == 'U') display.print_xzoom(xmap);
}

fn board_ship(obj: [*c]piece_info_t, pmap: [*c]path_map_t, dest: c_long) void {
    if (!load_army(obj)) {
        obj.*.func = 1;
        move_objective(obj, pmap, dest, "t.");
    }
}

fn find_best_tt(best_in: [*c]piece_info_t, loc: c_long) [*c]piece_info_t {
    var best: [*c]piece_info_t = best_in;
    var p: [*c]piece_info_t = globals.map[@intCast(loc)].objp;
    while (p != null) : (p = p.*.loc_link.next) {
        if (p.*.type == TRANSPORT and object.obj_capacity(p) > p.*.count) {
            if (best == null)
                best = p
            else if (p.*.count >= best.*.count)
                best = p;
        }
    }
    return best;
}

fn load_army(obj: [*c]piece_info_t) bool {
    var p: [*c]piece_info_t = find_best_tt(obj.*.ship, obj.*.loc);

    for (0..8) |i| {
        const x_loc: c_long = obj.*.loc + @as(c_long, data.dir_offset[i]);
        if (globals.map[@intCast(x_loc)].on_board) p = find_best_tt(p, x_loc);
    }

    if (p == null) return false;

    if (p.*.loc == obj.*.loc) {
        obj.*.moved = @intCast(data.piece_attr[ARMY].speed);
    } else {
        object.move_obj(obj, p.*.loc);
    }

    if (p.*.ship != obj.*.ship) {
        object.disembark(@ptrCast(obj));
        object.embark(@ptrCast(p), @ptrCast(obj));
    }
    return true;
}

fn move_away(vmap: [*c]view_map_t, loc: c_long, terrain: [*c]const u8) c_long {
    for (0..8) |i| {
        const new_loc: c_long = loc + @as(c_long, data.dir_offset[i]);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board and char_in(vmap[nu].contents, terrain) != null)
            return new_loc;
    }
    return loc;
}

fn find_attack(loc: c_long, obj_list: [*c]const u8, terrain: [*c]const u8) c_long {
    var best_loc: c_long = loc;
    var best_val: c_int = INFINITY;

    for (0..8) |i| {
        const new_loc: c_long = loc + @as(c_long, data.dir_offset[i]);
        const nu: usize = @intCast(new_loc);

        if (globals.map[nu].on_board and
            char_in(globals.map[nu].contents, terrain) != null)
        {
            if (char_in(globals.comp_map[nu].contents, obj_list)) |idx| {
                if (@as(c_int, @intCast(idx)) < best_val) {
                    best_val = @intCast(idx);
                    best_loc = new_loc;
                }
            }
        }
    }
    return best_loc;
}

// ============================================================
// Transport movement
// ============================================================

fn transport_move(obj: [*c]piece_info_t) void {
    var new_loc: c_long = undefined;

    // Empty transports can attack
    if (obj.*.count == 0) {
        obj.*.func = 0;
        new_loc = find_attack(obj.*.loc, &data.tt_attack, ".");
        if (new_loc != obj.*.loc) {
            attack_mod.attack(obj, new_loc);
            return;
        }
    }

    if (obj.*.count == object.obj_capacity(obj))
        obj.*.func = 1;

    if (obj.*.func == 0) {
        make_tt_load_map(&amap, &globals.comp_map);
        new_loc = map.vmap_find_wlobj(&path_map_buf, &amap, obj.*.loc, &data.tt_load);

        if (new_loc == obj.*.loc) {
            @memcpy(&amap, &globals.comp_map);
            unmark_explore_locs(&amap);
            if (globals.print_vmap == 'S') display.print_xzoom(&amap);
            new_loc = map.vmap_find_wobj(&path_map_buf, &amap, obj.*.loc, &data.tt_explore);
        }

        move_objective(obj, &path_map_buf, new_loc, "a ");
    } else {
        make_unload_map(&amap, &globals.comp_map);
        new_loc = map.vmap_find_wlobj(&path_map_buf, &amap, obj.*.loc, &data.tt_unload);
        move_objective(obj, &path_map_buf, new_loc, " ");
    }
}

// ============================================================
// Fighter movement
// ============================================================

fn fighter_move(obj: [*c]piece_info_t) void {
    var new_loc: c_long = find_attack(obj.*.loc, &data.fighter_attack, ".+");
    if (new_loc != obj.*.loc) {
        attack_mod.attack(obj, new_loc);
        return;
    }

    // Return to base if low on fuel
    if (obj.*.range <= object.find_nearest_city(obj.*.loc, COMP, &new_loc) + 2) {
        if (new_loc != obj.*.loc)
            new_loc = map.vmap_find_dest(&path_map_buf, &globals.comp_map, obj.*.loc, new_loc, COMP, T_AIR);
    } else {
        new_loc = obj.*.loc;
    }

    if (new_loc == obj.*.loc) {
        new_loc = map.vmap_find_aobj(&path_map_buf, &globals.comp_map, obj.*.loc, &data.fighter_fight);
    }
    move_objective(obj, &path_map_buf, new_loc, " ");
}

// ============================================================
// Ship movement
// ============================================================

fn ship_move(obj: [*c]piece_info_t) void {
    var new_loc: c_long = undefined;
    var adj_list: [*c]const u8 = undefined;

    if (obj.*.hits < @as(c_short, @intCast(data.piece_attr[@intCast(obj.*.type)].max_hits))) {
        if (globals.comp_map[@intCast(obj.*.loc)].contents == 'X') {
            obj.*.moved = @intCast(data.piece_attr[@intCast(obj.*.type)].speed);
            return;
        }
        new_loc = map.vmap_find_wobj(&path_map_buf, &globals.comp_map, obj.*.loc, &data.ship_repair);
        adj_list = ".";
    } else {
        new_loc = find_attack(obj.*.loc, &data.ship_attack, ".");
        if (new_loc != obj.*.loc) {
            attack_mod.attack(obj, new_loc);
            return;
        }
        @memcpy(&amap, &globals.comp_map);
        unmark_explore_locs(&amap);
        if (globals.print_vmap == 'S') display.print_xzoom(&amap);

        new_loc = map.vmap_find_wobj(&path_map_buf, &amap, obj.*.loc, &data.ship_fight);
        adj_list = data.ship_fight.objectives;
    }

    move_objective(obj, &path_map_buf, new_loc, adj_list);
}

// ============================================================
// Move to objective
// ============================================================

fn move_objective(obj: [*c]piece_info_t, pathmap: [*c]path_map_t, new_loc_in: c_long, adj_list: [*c]const u8) void {
    var new_loc: c_long = new_loc_in;

    if (new_loc == obj.*.loc) {
        obj.*.moved = @intCast(data.piece_attr[@intCast(obj.*.type)].speed);
        obj.*.range -= 1;
        terminal.pdebug("No destination found for %d at %d; func=%d\n", obj.*.type, terminal.loc_disp(@intCast(obj.*.loc)), @as(c_int, @truncate(obj.*.func)));
        return;
    }

    const old_loc = obj.*.loc;
    const old_dest = new_loc;

    const d_val = math.dist(new_loc, obj.*.loc);
    var reuse: bool = true;

    if (globals.comp_map[@intCast(new_loc)].contents == ' ' and d_val == 2) {
        map.vmap_mark_adjacent(pathmap, obj.*.loc);
        reuse = false;
    } else {
        map.vmap_mark_path(pathmap, &globals.comp_map, new_loc);
    }

    // Path terrain and move terrain may differ
    var terrain: [*c]const u8 = undefined;
    switch (obj.*.type) {
        ARMY => terrain = "+",
        FIGHTER => terrain = "+.X",
        else => terrain = ".X",
    }

    new_loc = map.vmap_find_dir(pathmap, &globals.comp_map, obj.*.loc, terrain, adj_list);

    if (new_loc == obj.*.loc and
        (obj.*.type != ARMY or obj.*.ship == null))
    {
        map.vmap_mark_near_path(pathmap, obj.*.loc);
        reuse = false;
        new_loc = map.vmap_find_dir(pathmap, &globals.comp_map, obj.*.loc, terrain, adj_list);
    }

    // Encourage army to leave city
    if (new_loc == obj.*.loc and globals.map[@intCast(obj.*.loc)].cityp != null and obj.*.type == ARMY) {
        new_loc = move_away(&globals.comp_map, obj.*.loc, "+");
        reuse = false;
    }

    if (new_loc == obj.*.loc) {
        obj.*.moved = @intCast(data.piece_attr[@intCast(obj.*.type)].speed);
        if (obj.*.type == ARMY and obj.*.ship != null) {
            // do nothing
        } else {
            terminal.pdebug("Cannot move %d at %d toward objective; func=%d\n", obj.*.type, terminal.loc_disp(@intCast(obj.*.loc)), @as(c_int, @truncate(obj.*.func)));
        }
    } else {
        object.move_obj(obj, new_loc);
    }

    // Try to make more moves using same path map.
    if (reuse and obj.*.moved < object.obj_moves(obj) and obj.*.loc != old_dest) {
        var attack_list: [*c]const u8 = undefined;
        switch (obj.*.type) {
            FIGHTER => {
                if (globals.comp_map[@intCast(old_dest)].contents != 'X' and
                    obj.*.range <= @divTrunc(@as(c_short, @intCast(data.piece_attr[FIGHTER].range)), 2))
                    return;
                attack_list = &data.fighter_attack;
                terrain = "+.";
            },
            ARMY => {
                attack_list = &data.army_attack;
                if (obj.*.ship != null)
                    terrain = "+*"
                else
                    terrain = "+.*";
            },
            TRANSPORT => {
                terrain = ".*";
                if (obj.*.cargo != null)
                    attack_list = &data.tt_attack
                else
                    attack_list = "*O";
            },
            else => {
                attack_list = &data.ship_attack;
                terrain = ".";
            },
        }
        if (find_attack(obj.*.loc, attack_list, terrain) != obj.*.loc) return;

        // Clear old path
        pathmap[@intCast(old_loc)].terrain = @intCast(T_UNKNOWN);
        for (0..8) |di| {
            const nl: c_long = old_loc + @as(c_long, data.dir_offset[di]);
            pathmap[@intCast(nl)].terrain = @intCast(T_UNKNOWN);
        }
        // Pathmap is already marked, but this should work
        move_objective(obj, pathmap, old_dest, adj_list);
    }
}

// ============================================================
// End game check
// ============================================================

fn check_endgame() void {
    globals.date += 1;
    if (globals.win != 0) return;

    var nuser_city: c_int = 0;
    var ncomp_city: c_int = 0;
    var nuser_army: c_int = 0;
    var ncomp_army: c_int = 0;

    for (0..NUM_CITY) |i| {
        if (globals.city[i].owner == USER)
            nuser_city += 1
        else if (globals.city[i].owner == COMP)
            ncomp_city += 1;
    }

    var p: [*c]piece_info_t = globals.user_obj[ARMY];
    while (p != null) : (p = p.*.piece_link.next) nuser_army += 1;

    p = globals.comp_obj[ARMY];
    while (p != null) : (p = p.*.piece_link.next) ncomp_army += 1;

    if (ncomp_city < @divTrunc(nuser_city, 3) and ncomp_army < @divTrunc(nuser_army, 3)) {
        display.clear_screen();
        terminal.prompt("The computer acknowledges defeat. Do");
        terminal.ksend("The computer acknowledges defeat.");
        terminal.@"error"("you wish to smash the rest of the enemy?");

        if (terminal.get_chx() != 'Y') util.empend();
        display.announce("\nThe enemy inadvertantly revealed its code used for");
        display.announce("\nreceiving battle information. You can display what");
        display.announce("\nthey've learned with the ''E'' command.");
        globals.resigned = true;
        globals.win = ratio_win;
        globals.automove = false;
    } else if (ncomp_city == 0 and ncomp_army == 0) {
        display.clear_screen();
        display.announce("The enemy is incapable of defeating you.\n");
        display.announce("You are free to rape the empire as you wish.\n");
        display.announce("There may be, however, remnants of the enemy fleet\n");
        display.announce("to be routed out and destroyed.\n");
        globals.win = wipeout_win;
        globals.automove = false;
    } else if (nuser_city == 0 and nuser_army == 0) {
        display.clear_screen();
        display.announce("You have been rendered incapable of\n");
        display.announce("defeating the rampaging enemy fascists! The\n");
        display.announce("empire is lost. If you have any ships left, you\n");
        display.announce("may attempt to harass enemy shipping.");
        globals.win = 1;
        globals.automove = false;
    }
}
