const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const object = @import("object.zig");
const display = @import("display.zig");

const view_map_t = types.view_map_t;
const path_map_t = types.path_map_t;
const move_info_t = types.move_info_t;
const perimeter_t = types.perimeter_t;
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
const W_TT_BUILD: c_int = -1;

const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);
const UNOWNED = @intFromEnum(globals.Ownership.Unowned);
const TRANSPORT = @intFromEnum(globals.PieceType.Transport);

// Terrain type constants (used as bitmasks)
const T_UNKNOWN: c_int = 0;
const T_PATH: c_int = 1;
const T_LAND: c_int = 2;
const T_WATER: c_int = 4;
const T_AIR: c_int = T_LAND | T_WATER;

// Static perimeter lists
var p1: perimeter_t = .{};
var p2: perimeter_t = .{};
var p3: perimeter_t = .{};
var p4: perimeter_t = .{};

// Best objective found so far
var best_cost: c_int = INFINITY;
var best_loc: c_long = 0;

// Pre-initialized path map template
var pmap_init: [MAP_SIZE]path_map_t = undefined;
var init_done: bool = false;

// Direction order for vmap_find_dir (prefer diagonals)
const order = [8]c_int{
    @intFromEnum(globals.Direction.Northwest),
    @intFromEnum(globals.Direction.Northeast),
    @intFromEnum(globals.Direction.Southwest),
    @intFromEnum(globals.Direction.Southeast),
    @intFromEnum(globals.Direction.West),
    @intFromEnum(globals.Direction.East),
    @intFromEnum(globals.Direction.North),
    @intFromEnum(globals.Direction.South),
};

// Helper: check if char is in a null-terminated C string
fn char_in(c: u8, set: [*c]const u8) ?usize {
    var i: usize = 0;
    while (set[i] != 0) : (i += 1) {
        if (set[i] == c) return i;
    }
    return null;
}

// ============================================================
// Continent mapping
// ============================================================

pub export fn vmap_cont(cont_map: [*c]c_int, vmap: [*c]view_map_t, loc: c_long, bad_terrain: u8) void {
    @memset(cont_map[0..@intCast(MAP_SIZE)], 0);
    vmap_mark_up_cont(cont_map, vmap, loc, bad_terrain);
}

pub export fn vmap_mark_up_cont(cont_map: [*c]c_int, vmap: [*c]view_map_t, loc: c_long, bad_terrain: u8) void {
    var from: *perimeter_t = &p1;
    var to: *perimeter_t = &p2;

    from.len = 1;
    from.list[0] = loc;
    cont_map[@intCast(loc)] = 1;

    while (from.len > 0) {
        to.len = 0;

        var i: usize = 0;
        while (i < @as(usize, @intCast(from.len))) : (i += 1) {
            for (data.dir_offset[0..8]) |offset| {
                const new_loc: c_long = from.list[i] + @as(c_long, offset);
                const nu: usize = @intCast(new_loc);
                if (!globals.map[nu].on_board) continue;
                if (cont_map[nu] != 0) continue;

                if (vmap[nu].contents == ' ') {
                    cont_map[nu] = 1; // mark but don't expand
                } else {
                    const this_terrain: u8 = if (vmap[nu].contents == MAP_LAND)
                        MAP_LAND
                    else if (vmap[nu].contents == MAP_SEA)
                        MAP_SEA
                    else
                        globals.map[nu].contents;

                    if (this_terrain != bad_terrain) {
                        cont_map[nu] = 1;
                        to.list[@intCast(to.len)] = new_loc;
                        to.len += 1;
                    }
                }
            }
        }
        const tmp = from;
        from = to;
        to = tmp;
    }
}

pub export fn rmap_cont(cont_map: [*c]c_int, loc: c_long, bad_terrain: u8) void {
    @memset(cont_map[0..@intCast(MAP_SIZE)], 0);
    rmap_mark_up_cont(cont_map, loc, bad_terrain);
}

fn rmap_mark_up_cont(cont_map: [*c]c_int, loc: c_long, bad_terrain: u8) void {
    const uloc: usize = @intCast(loc);
    if (!globals.map[uloc].on_board) return;
    if (cont_map[uloc] != 0) return;
    if (globals.map[uloc].contents == bad_terrain) return;

    cont_map[uloc] = 1;

    for (data.dir_offset[0..8]) |offset| {
        rmap_mark_up_cont(cont_map, loc + @as(c_long, offset), bad_terrain);
    }
}

// ============================================================
// Continent scanning
// ============================================================

pub export fn vmap_cont_scan(cont_map: [*c]c_int, vmap: [*c]view_map_t) scan_counts_t {
    var counts: scan_counts_t = std.mem.zeroes(scan_counts_t);

    for (0..@intCast(MAP_SIZE)) |i| {
        if (cont_map[i] != 0) {
            counts.size += 1;

            switch (vmap[i].contents) {
                ' ' => counts.unexplored += 1,
                'O' => counts.user_cities += 1,
                'A' => counts.user_objects[@intFromEnum(globals.PieceType.Army)] += 1,
                'F' => counts.user_objects[@intFromEnum(globals.PieceType.Fighter)] += 1,
                'P' => counts.user_objects[@intFromEnum(globals.PieceType.Patrol)] += 1,
                'D' => counts.user_objects[@intFromEnum(globals.PieceType.Destroyer)] += 1,
                'S' => counts.user_objects[@intFromEnum(globals.PieceType.SubMarine)] += 1,
                'T' => counts.user_objects[@intFromEnum(globals.PieceType.Transport)] += 1,
                'C' => counts.user_objects[@intFromEnum(globals.PieceType.Carrier)] += 1,
                'B' => counts.user_objects[@intFromEnum(globals.PieceType.Battleship)] += 1,
                'X' => counts.comp_cities += 1,
                'a' => counts.comp_objects[@intFromEnum(globals.PieceType.Army)] += 1,
                'f' => counts.comp_objects[@intFromEnum(globals.PieceType.Fighter)] += 1,
                'p' => counts.comp_objects[@intFromEnum(globals.PieceType.Patrol)] += 1,
                'd' => counts.comp_objects[@intFromEnum(globals.PieceType.Destroyer)] += 1,
                's' => counts.comp_objects[@intFromEnum(globals.PieceType.SubMarine)] += 1,
                't' => counts.comp_objects[@intFromEnum(globals.PieceType.Transport)] += 1,
                'c' => counts.comp_objects[@intFromEnum(globals.PieceType.Carrier)] += 1,
                'b' => counts.comp_objects[@intFromEnum(globals.PieceType.Battleship)] += 1,
                MAP_CITY => counts.unowned_cities += 1,
                MAP_LAND, MAP_SEA => {},
                else => {
                    if (globals.map[i].contents == MAP_CITY) {
                        const cityp = globals.map[i].cityp;
                        if (cityp != null) {
                            switch (cityp.*.owner) {
                                USER => counts.user_cities += 1,
                                COMP => counts.comp_cities += 1,
                                UNOWNED => counts.unowned_cities += 1,
                                else => {},
                            }
                        }
                    }
                },
            }
        }
    }
    return counts;
}

pub export fn rmap_cont_scan(cont_map: [*c]c_int) scan_counts_t {
    var counts: scan_counts_t = std.mem.zeroes(scan_counts_t);

    for (0..@intCast(MAP_SIZE)) |i| {
        if (cont_map[i] != 0) {
            counts.size += 1;
            if (globals.map[i].contents == MAP_CITY) counts.unowned_cities += 1;
        }
    }
    return counts;
}

pub export fn map_cont_edge(cont_map: [*c]c_int, loc: c_long) bool {
    if (cont_map[@intCast(loc)] == 0) return false;

    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board and cont_map[nu] == 0) return true;
    }
    return false;
}

// ============================================================
// Path finding - perimeter operations
// ============================================================

fn start_perimeter(pmap: [*c]path_map_t, perim: *perimeter_t, loc: c_long, terrain: c_int) void {
    if (!init_done) {
        init_done = true;
        for (0..@intCast(MAP_SIZE)) |i| {
            pmap_init[i].cost = INFINITY;
            pmap_init[i].inc_cost = 0;
            pmap_init[i].terrain = @intCast(T_UNKNOWN);
        }
    }
    @memcpy(pmap[0..@intCast(MAP_SIZE)], &pmap_init);

    const uloc: usize = @intCast(loc);
    pmap[uloc].cost = 0;
    pmap[uloc].inc_cost = 0;
    pmap[uloc].terrain = @intCast(terrain);

    perim.len = 1;
    perim.list[0] = loc;

    best_cost = INFINITY;
    best_loc = loc;
}

fn add_cell(pmap: [*c]path_map_t, new_loc: c_long, perim: *perimeter_t, terrain: c_int, cur_cost: c_int, inc_cost: c_int) void {
    const nu: usize = @intCast(new_loc);
    pmap[nu].terrain = @intCast(terrain);
    pmap[nu].inc_cost = inc_cost;
    pmap[nu].cost = cur_cost + inc_cost;

    perim.list[@intCast(perim.len)] = new_loc;
    perim.len += 1;
}

fn terrain_type(pmap: [*c]path_map_t, vmap: [*c]view_map_t, move_info: [*c]move_info_t, from_loc: c_long, to_loc: c_long) c_int {
    const tu: usize = @intCast(to_loc);
    const fu: usize = @intCast(from_loc);

    if (vmap[tu].contents == MAP_LAND) return T_LAND;
    if (vmap[tu].contents == MAP_SEA) return T_WATER;
    if (vmap[tu].contents == '%') return T_UNKNOWN;
    if (vmap[tu].contents == ' ') return @as(c_int, pmap[fu].terrain);

    return switch (globals.map[tu].contents) {
        MAP_SEA => T_WATER,
        MAP_LAND => T_LAND,
        MAP_CITY => if (globals.map[tu].cityp != null and globals.map[tu].cityp.*.owner == move_info.*.city_owner)
            T_WATER
        else
            T_UNKNOWN,
        else => unreachable,
    };
}

fn objective_cost(vmap: [*c]view_map_t, move_info: [*c]move_info_t, loc: c_long, base_cost: c_int) c_int {
    const uloc: usize = @intCast(loc);
    const idx = char_in(vmap[uloc].contents, move_info.*.objectives) orelse return INFINITY;

    const w = move_info.*.weights[idx];
    if (w >= 0) return w + base_cost;

    switch (w) {
        W_TT_BUILD => {
            const cityp = object.find_city(loc);
            if (cityp == null) return base_cost + 2;
            if (cityp.*.prod != TRANSPORT) return base_cost + 2;

            var wt: c_int = @as(c_int, data.piece_attr[TRANSPORT].build_time) - @as(c_int, @truncate(cityp.*.work));
            wt *= 2;
            if (wt < base_cost + 2) wt = base_cost + 2;
            return wt;
        },
        else => unreachable,
    }
}

fn expand_perimeter(
    pmap: [*c]path_map_t,
    vmap: [*c]view_map_t,
    move_info: [*c]move_info_t,
    curp: *perimeter_t,
    terrain_mask: c_int,
    cur_cost: c_int,
    inc_wcost: c_int,
    inc_lcost: c_int,
    waterp: ?*perimeter_t,
    landp: ?*perimeter_t,
) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(curp.len))) : (i += 1) {
        for (data.dir_offset[0..8]) |offset| {
            const new_loc: c_long = curp.list[i] + @as(c_long, offset);
            const nu: usize = @intCast(new_loc);
            if (!globals.map[nu].on_board) continue;

            const pm = &pmap[nu];

            if (pm.cost == INFINITY) {
                const new_type = terrain_type(pmap, vmap, move_info, curp.list[i], new_loc);

                if (new_type == T_LAND and (terrain_mask & T_LAND) != 0) {
                    if (landp) |lp| add_cell(pmap, new_loc, lp, new_type, cur_cost, inc_lcost);
                } else if (new_type == T_WATER and (terrain_mask & T_WATER) != 0) {
                    if (waterp) |wp| add_cell(pmap, new_loc, wp, new_type, cur_cost, inc_wcost);
                } else if (new_type == T_UNKNOWN) {
                    pm.terrain = @intCast(T_UNKNOWN);
                    pm.cost = cur_cost + @divTrunc(INFINITY, 2);
                    pm.inc_cost = @divTrunc(INFINITY, 2);
                }

                if (pmap[nu].cost != INFINITY) {
                    const obj_cost = objective_cost(vmap, move_info, new_loc, cur_cost);
                    if (obj_cost < best_cost) {
                        best_cost = obj_cost;
                        best_loc = new_loc;
                        if (new_type == T_UNKNOWN) {
                            pm.cost = cur_cost + 2;
                            pm.inc_cost = 2;
                        }
                    }
                }
            }
        }
    }
}

// ============================================================
// Path finding - find objectives
// ============================================================

pub export fn vmap_find_xobj(path_map_arg: [*c]path_map_t, vmap: [*c]view_map_t, loc: c_long, move_info: [*c]move_info_t, start: c_int, expand: c_int) c_long {
    var from: *perimeter_t = &p1;
    var to: *perimeter_t = &p2;

    start_perimeter(path_map_arg, from, loc, start);
    var cur_cost: c_int = 0;

    while (true) {
        to.len = 0;
        expand_perimeter(path_map_arg, vmap, move_info, from, expand, cur_cost, 1, 1, to, to);

        if (globals.trace_pmap) display.print_pzoom("After xobj loop:", path_map_arg, vmap);

        cur_cost += 1;
        if (to.len == 0 or best_cost <= cur_cost) return best_loc;

        const tmp = from;
        from = to;
        to = tmp;
    }
}

pub export fn vmap_find_aobj(path_map_arg: [*c]path_map_t, vmap: [*c]view_map_t, loc: c_long, move_info: [*c]move_info_t) c_long {
    return vmap_find_xobj(path_map_arg, vmap, loc, move_info, T_LAND, T_AIR);
}

pub export fn vmap_find_wobj(path_map_arg: [*c]path_map_t, vmap: [*c]view_map_t, loc: c_long, move_info: [*c]move_info_t) c_long {
    return vmap_find_xobj(path_map_arg, vmap, loc, move_info, T_WATER, T_WATER);
}

pub export fn vmap_find_lobj(path_map_arg: [*c]path_map_t, vmap: [*c]view_map_t, loc: c_long, move_info: [*c]move_info_t) c_long {
    return vmap_find_xobj(path_map_arg, vmap, loc, move_info, T_LAND, T_LAND);
}

pub export fn vmap_find_lwobj(path_map_arg: [*c]path_map_t, vmap: [*c]view_map_t, loc: c_long, move_info: [*c]move_info_t, beat_cost: c_int) c_long {
    var cur_land: *perimeter_t = &p1;
    var cur_water: *perimeter_t = &p2;
    var new_water: *perimeter_t = &p3;
    var new_land: *perimeter_t = &p4;

    start_perimeter(path_map_arg, cur_land, loc, T_LAND);
    cur_water.len = 0;
    best_cost = beat_cost;
    var cur_cost: c_int = 0;

    while (true) {
        new_water.len = 0;
        new_land.len = 0;
        expand_perimeter(path_map_arg, vmap, move_info, cur_water, T_WATER, cur_cost, 1, 1, new_water, null);
        expand_perimeter(path_map_arg, vmap, move_info, cur_land, T_AIR, cur_cost, 1, 2, new_water, new_land);

        // expand new water one cell
        cur_water.len = 0;
        expand_perimeter(path_map_arg, vmap, move_info, new_water, T_WATER, cur_cost + 1, 1, 1, cur_water, null);

        if (globals.trace_pmap) display.print_pzoom("After lwobj loop:", path_map_arg, vmap);

        cur_cost += 2;
        if ((cur_water.len == 0 and new_land.len == 0) or best_cost <= cur_cost)
            return best_loc;

        const tmp = cur_land;
        cur_land = new_land;
        new_land = tmp;
    }
}

pub export fn vmap_find_wlobj(path_map_arg: [*c]path_map_t, vmap: [*c]view_map_t, loc: c_long, move_info: [*c]move_info_t) c_long {
    var cur_land: *perimeter_t = &p1;
    var cur_water: *perimeter_t = &p2;
    var new_water: *perimeter_t = &p3;
    var new_land: *perimeter_t = &p4;

    start_perimeter(path_map_arg, cur_water, loc, T_WATER);
    cur_land.len = 0;
    var cur_cost: c_int = 0;

    while (true) {
        new_water.len = 0;
        new_land.len = 0;
        expand_perimeter(path_map_arg, vmap, move_info, cur_water, T_AIR, cur_cost, 1, 2, new_water, new_land);
        expand_perimeter(path_map_arg, vmap, move_info, cur_land, T_LAND, cur_cost, 1, 2, null, new_land);

        // expand new water one cell to water
        cur_water.len = 0;
        expand_perimeter(path_map_arg, vmap, move_info, new_water, T_WATER, cur_cost + 1, 1, 1, cur_water, null);

        if (globals.trace_pmap) display.print_pzoom("After wlobj loop:", path_map_arg, vmap);

        cur_cost += 2;
        if ((cur_water.len == 0 and new_land.len == 0) or best_cost <= cur_cost)
            return best_loc;

        const tmp = cur_land;
        cur_land = new_land;
        new_land = tmp;
    }
}

// ============================================================
// Find destination (shortest path to known location)
// ============================================================

pub export fn vmap_find_dest(path_map_arg: [*c]path_map_t, vmap: [*c]view_map_t, cur_loc: c_long, dest_loc: c_long, owner: c_int, terrain: c_int) c_long {
    const du: usize = @intCast(dest_loc);
    const old_contents = vmap[du].contents;
    vmap[du].contents = '%'; // mark objective

    var move_info: move_info_t = .{};
    move_info.city_owner = @intCast(owner);
    move_info.objectives = "%";
    move_info.weights[0] = 1;

    var from: *perimeter_t = &p1;
    var to: *perimeter_t = &p2;

    const start_terrain: c_int = if (terrain == T_AIR) T_LAND else terrain;

    start_perimeter(path_map_arg, from, cur_loc, start_terrain);
    var cur_cost: c_int = 0;

    while (true) {
        to.len = 0;
        expand_perimeter(path_map_arg, vmap, &move_info, from, terrain, cur_cost, 1, 1, to, to);
        cur_cost += 1;
        if (to.len == 0 or best_cost <= cur_cost) {
            vmap[du].contents = old_contents;
            return best_loc;
        }
        const tmp = from;
        from = to;
        to = tmp;
    }
}

// ============================================================
// Path marking
// ============================================================

pub export fn vmap_mark_path(pmap: [*c]path_map_t, vmap: [*c]view_map_t, dest: c_long) void {
    const du: usize = @intCast(dest);

    if (pmap[du].cost == 0) return;
    if (pmap[du].terrain == @as(u8, @intCast(T_PATH))) return;

    pmap[du].terrain = @intCast(T_PATH);

    for (data.dir_offset[0..8]) |offset| {
        const new_dest: c_long = dest + @as(c_long, offset);
        const nu: usize = @intCast(new_dest);
        if (pmap[nu].cost == pmap[du].cost - pmap[du].inc_cost)
            vmap_mark_path(pmap, vmap, new_dest);
    }
}

pub export fn vmap_mark_adjacent(pmap: [*c]path_map_t, loc: c_long) void {
    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board)
            pmap[nu].terrain = @intCast(T_PATH);
    }
}

pub export fn vmap_mark_near_path(pmap: [*c]path_map_t, loc: c_long) void {
    var hit_loc = [_]c_int{0} ** 8;

    for (0..8) |i| {
        const new_loc: c_long = loc + @as(c_long, data.dir_offset[i]);
        const nu: usize = @intCast(new_loc);
        if (!globals.map[nu].on_board) continue;

        for (data.dir_offset[0..8]) |offset2| {
            const xloc: c_long = new_loc + @as(c_long, offset2);
            const xu: usize = @intCast(xloc);
            if (globals.map[xu].on_board and xloc != loc and pmap[xu].terrain == @as(u8, @intCast(T_PATH))) {
                hit_loc[i] = 1;
                break;
            }
        }
    }
    for (0..8) |i| {
        if (hit_loc[i] != 0) {
            const target: usize = @intCast(loc + @as(c_long, data.dir_offset[i]));
            pmap[target].terrain = @intCast(T_PATH);
        }
    }
}

// ============================================================
// Direction finding
// ============================================================

pub export fn vmap_find_dir(pmap: [*c]path_map_t, vmap: [*c]view_map_t, loc: c_long, terrain: [*c]const u8, adj_char: [*c]const u8) c_long {
    if (globals.trace_pmap) display.print_pzoom("Before vmap_find_dir:", pmap, vmap);

    var bestcount: c_int = -INFINITY;
    var bestpath: c_int = -1;
    var bestloc: c_long = loc;

    for (order) |dir| {
        const new_loc: c_long = loc + @as(c_long, data.dir_offset[@intCast(dir)]);
        const nu: usize = @intCast(new_loc);
        if (pmap[nu].terrain == @as(u8, @intCast(T_PATH))) {
            if (char_in(vmap[nu].contents, terrain) != null) {
                const count = vmap_count_adjacent(vmap, new_loc, adj_char);
                const path_count = vmap_count_path(pmap, new_loc);

                if (count > bestcount or
                    (count == bestcount and path_count > bestpath))
                {
                    bestcount = count;
                    bestpath = path_count;
                    bestloc = new_loc;
                }
            }
        }
    }
    return bestloc;
}

pub export fn vmap_count_adjacent(vmap: [*c]view_map_t, loc: c_long, adj_char: [*c]const u8) c_int {
    // compute length of adj_char
    var len: c_int = 0;
    while (adj_char[@intCast(len)] != 0) : (len += 1) {}

    var count: c_int = 0;

    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board) {
            if (char_in(vmap[nu].contents, adj_char)) |idx| {
                count += 8 * (len - @as(c_int, @intCast(idx)));
            }
        }
    }
    return count;
}

fn vmap_count_path(pmap: [*c]path_map_t, loc: c_long) c_int {
    var count: c_int = 0;

    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board and pmap[nu].terrain == @as(u8, @intCast(T_PATH)))
            count += 1;
    }
    return count;
}

// ============================================================
// Explore location pruning
// ============================================================

pub export fn vmap_prune_explore_locs(vmap: [*c]view_map_t) void {
    var pmap: [MAP_SIZE]path_map_t = std.mem.zeroes([MAP_SIZE]path_map_t);
    var from: *perimeter_t = &p1;
    var to: *perimeter_t = &p2;
    from.len = 0;
    var explored: c_int = 0;

    // build initial path map and perimeter list
    for (0..@intCast(MAP_SIZE)) |loc| {
        if (vmap[loc].contents != ' ') {
            explored += 1;
        } else {
            for (data.dir_offset[0..8]) |offset| {
                const new_loc: c_long = @as(c_long, @intCast(loc)) + @as(c_long, offset);
                if (new_loc < 0 or new_loc >= MAP_SIZE) {
                    // ignore off map
                } else if (vmap[@intCast(new_loc)].contents == ' ') {
                    // ignore adjacent unexplored
                } else if (globals.map[@intCast(new_loc)].contents != MAP_SEA) {
                    pmap[loc].cost += 1; // count land
                } else {
                    pmap[loc].inc_cost += 1; // count water
                }
            }
            if (pmap[loc].cost != 0 or pmap[loc].inc_cost != 0) {
                from.list[@intCast(from.len)] = @intCast(loc);
                from.len += 1;
            }
        }
    }

    if (globals.print_vmap == 'I') display.print_xzoom(vmap);

    // high probability predictions
    while (true) {
        if (from.len + @as(c_long, explored) == MAP_SIZE) return;
        to.len = 0;
        var copied: c_long = 0;

        var i: usize = 0;
        while (i < @as(usize, @intCast(from.len))) : (i += 1) {
            const loc = from.list[i];
            const uloc: usize = @intCast(loc);
            if (pmap[uloc].cost >= 5)
                expand_prune(vmap, &pmap, loc, T_LAND, to, &explored)
            else if (pmap[uloc].inc_cost >= 5)
                expand_prune(vmap, &pmap, loc, T_WATER, to, &explored)
            else if ((loc < MAP_WIDTH or loc >= MAP_SIZE - MAP_WIDTH) and pmap[uloc].cost >= 3)
                expand_prune(vmap, &pmap, loc, T_LAND, to, &explored)
            else if ((loc < MAP_WIDTH or loc >= MAP_SIZE - MAP_WIDTH) and pmap[uloc].inc_cost >= 3)
                expand_prune(vmap, &pmap, loc, T_WATER, to, &explored)
            else if ((loc == 0 or loc == MAP_SIZE - 1) and pmap[uloc].cost >= 2)
                expand_prune(vmap, &pmap, loc, T_LAND, to, &explored)
            else if ((loc == 0 or loc == MAP_SIZE - 1) and pmap[uloc].inc_cost >= 2)
                expand_prune(vmap, &pmap, loc, T_WATER, to, &explored)
            else {
                to.list[@intCast(to.len)] = loc;
                to.len += 1;
                copied += 1;
            }
        }
        if (copied == from.len) break;
        const tmp = from;
        from = to;
        to = tmp;
    }

    if (globals.print_vmap == 'I') display.print_xzoom(vmap);

    // one pass for medium probability predictions
    if (from.len + @as(c_long, explored) == MAP_SIZE) return;
    to.len = 0;

    {
        var i: usize = 0;
        while (i < @as(usize, @intCast(from.len))) : (i += 1) {
            const loc = from.list[i];
            const uloc: usize = @intCast(loc);
            if (pmap[uloc].cost > pmap[uloc].inc_cost)
                expand_prune(vmap, &pmap, loc, T_LAND, to, &explored)
            else if (pmap[uloc].cost < pmap[uloc].inc_cost)
                expand_prune(vmap, &pmap, loc, T_WATER, to, &explored)
            else {
                to.list[@intCast(to.len)] = loc;
                to.len += 1;
            }
        }
    }
    {
        const tmp = from;
        from = to;
        to = tmp;
    }

    if (globals.print_vmap == 'I') display.print_xzoom(vmap);

    // multiple low probability passes
    while (true) {
        if (from.len + @as(c_long, explored) >= MAP_SIZE - MAP_HEIGHT) {
            if (globals.print_vmap == 'I') display.print_xzoom(vmap);
            return;
        }
        to.len = 0;
        var copied: c_long = 0;

        var i: usize = 0;
        while (i < @as(usize, @intCast(from.len))) : (i += 1) {
            const loc = from.list[i];
            const uloc: usize = @intCast(loc);
            if (pmap[uloc].cost >= 4 and pmap[uloc].inc_cost < 4)
                expand_prune(vmap, &pmap, loc, T_LAND, to, &explored)
            else if (pmap[uloc].inc_cost >= 4 and pmap[uloc].cost < 4)
                expand_prune(vmap, &pmap, loc, T_WATER, to, &explored)
            else if ((loc < MAP_WIDTH or loc >= MAP_SIZE - MAP_WIDTH) and pmap[uloc].cost > pmap[uloc].inc_cost)
                expand_prune(vmap, &pmap, loc, T_LAND, to, &explored)
            else if ((loc < MAP_WIDTH or loc >= MAP_SIZE - MAP_WIDTH) and pmap[uloc].inc_cost > pmap[uloc].cost)
                expand_prune(vmap, &pmap, loc, T_WATER, to, &explored)
            else {
                to.list[@intCast(to.len)] = loc;
                to.len += 1;
                copied += 1;
            }
        }
        if (copied == from.len) break;
        const tmp = from;
        from = to;
        to = tmp;
    }
    if (globals.print_vmap == 'I') display.print_xzoom(vmap);
}

fn expand_prune(vmap: [*c]view_map_t, pmap: *[MAP_SIZE]path_map_t, loc: c_long, terrain_type_val: c_int, to: *perimeter_t, explored: *c_int) void {
    const uloc: usize = @intCast(loc);
    explored.* += 1;

    if (terrain_type_val == T_LAND)
        vmap[uloc].contents = MAP_LAND
    else
        vmap[uloc].contents = MAP_SEA;

    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        if (new_loc >= 0 and new_loc < MAP_SIZE) {
            const nu: usize = @intCast(new_loc);
            if (vmap[nu].contents == ' ') {
                if (pmap[nu].cost == 0 and pmap[nu].inc_cost == 0) {
                    to.list[@intCast(to.len)] = new_loc;
                    to.len += 1;
                }
                if (terrain_type_val == T_LAND)
                    pmap[nu].cost += 1
                else
                    pmap[nu].inc_cost += 1;
            }
        }
    }
}

// ============================================================
// Shore and sea tests
// ============================================================

pub export fn rmap_shore(loc: c_long) bool {
    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board and globals.map[nu].contents == MAP_SEA)
            return true;
    }
    return false;
}

pub export fn vmap_shore(vmap: [*c]view_map_t, loc: c_long) bool {
    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board and
            vmap[nu].contents != ' ' and vmap[nu].contents != MAP_LAND and
            globals.map[nu].contents == MAP_SEA)
            return true;
    }
    return false;
}

pub export fn vmap_at_sea(vmap: [*c]view_map_t, loc: c_long) bool {
    const uloc: usize = @intCast(loc);
    if (globals.map[uloc].contents != MAP_SEA) return false;

    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board and
            (vmap[nu].contents == ' ' or vmap[nu].contents == MAP_LAND or
            globals.map[nu].contents != MAP_SEA))
            return false;
    }
    return true;
}

pub export fn rmap_at_sea(loc: c_long) bool {
    const uloc: usize = @intCast(loc);
    if (globals.map[uloc].contents != MAP_SEA) return false;

    for (data.dir_offset[0..8]) |offset| {
        const new_loc: c_long = loc + @as(c_long, offset);
        const nu: usize = @intCast(new_loc);
        if (globals.map[nu].on_board and globals.map[nu].contents != MAP_SEA)
            return false;
    }
    return true;
}
