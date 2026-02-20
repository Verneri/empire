const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const terminal = @import("terminal.zig");
const object = @import("object.zig");
const math = @import("math.zig");
const util = @import("util.zig");
const map = @import("map.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
    @cInclude("ctype.h");
});

const piece_info_t = types.piece_info_t;
const city_info_t = types.city_info_t;
const view_map_t = types.view_map_t;
const path_map_t = types.path_map_t;

const STRSIZE = globals.STRSIZE;
const MAP_SIZE = globals.MAP_SIZE;
const MAP_WIDTH = globals.MAP_WIDTH;
const MAP_HEIGHT = globals.MAP_HEIGHT;
const NUM_CITY = globals.NUM_CITY;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const LIST_SIZE = globals.LIST_SIZE;

const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);
const UNOWNED = @intFromEnum(globals.Ownership.Unowned);
const NOPIECE: u8 = @intCast(@intFromEnum(globals.PieceType.NoPiece));
const ARMY: c_int = @intFromEnum(globals.PieceType.Army);
const FIGHTER: c_int = @intFromEnum(globals.PieceType.Fighter);
const TRANSPORT: c_int = @intFromEnum(globals.PieceType.Transport);
const CARRIER: c_int = @intFromEnum(globals.PieceType.Carrier);
const NOFUNC = @as(c_long, @intFromEnum(globals.Function.NoFunc));

const MAP_LAND = data.MAP_LAND;
const MAP_SEA = data.MAP_SEA;
const MAP_CITY = data.MAP_CITY;


const MAX_HEIGHT = 999;
const MAX_CONT = 10;

// Static arrays for map generation
var height: [2][MAP_SIZE]c_int = undefined;
var height_count: [MAX_HEIGHT + 1]c_int = undefined;
var land: [MAP_SIZE]c_long = undefined;

// Continent data
const cont_t = struct {
    value: c_long,
    ncity: c_int,
    cityp: [NUM_CITY][*c]city_info_t,
};

const pair_t = struct {
    value: c_long,
    user_cont: c_int,
    comp_cont: c_int,
};

var marked: [MAP_SIZE]c_int = std.mem.zeroes([MAP_SIZE]c_int);
var ncont: c_int = 0;
var cont_tab: [MAX_CONT]cont_t = undefined;
var rank_tab: [MAX_CONT]c_int = undefined;
var pair_tab: [MAX_CONT * MAX_CONT]pair_t = undefined;

// Statics for mark_cont
var mc_ncity: c_int = 0;
var mc_nland: c_long = 0;
var mc_nshore: c_int = 0;

// Movie buffer
var mapbuf: [MAP_SIZE]u8 = undefined;

// Public wrapper interface

pub const LoadError = error{NotLoaded};

pub fn restore() LoadError!void {
    if (!restore_game()) return LoadError.NotLoaded;
}

pub fn init() void {
    init_game();
}

pub fn save() void {
    save_game();
}

// Game initialization

pub export fn init_game() void {
    display.kill_display();
    globals.automove = false;
    globals.resigned = false;
    globals.debug = false;
    globals.print_debug = false;
    globals.print_vmap = 0;
    globals.trace_pmap = false;
    globals.save_movie = false;
    globals.win = 0; // no_win
    globals.date = 0;
    globals.user_score = 0;
    globals.comp_score = 0;

    for (0..MAP_SIZE) |i| {
        globals.user_map[i].contents = ' ';
        globals.user_map[i].seen = 0;
        globals.comp_map[i].contents = ' ';
        globals.comp_map[i].seen = 0;
    }
    for (0..NUM_OBJECTS) |i| {
        globals.user_obj[i] = null;
        globals.comp_obj[i] = null;
    }
    globals.free_list = null;
    for (0..LIST_SIZE) |i| {
        var obj: *piece_info_t = &globals.object[i];
        obj.hits = 0;
        obj.owner = UNOWNED;
        object.link(&globals.free_list, obj, .piece_link);
    }

    make_map();

    while (true) {
        for (0..MAP_SIZE) |i| {
            if (globals.map[i].contents == MAP_CITY) globals.map[i].contents = MAP_LAND;
        }
        place_cities();
        if (select_cities()) break;
    }
}

fn make_map() void {
    for (0..MAP_SIZE) |i| {
        height[0][i] = @intCast(math.irand(MAX_HEIGHT));
    }

    var from: usize = 0;
    var to: usize = 1;
    for (0..@intCast(globals.SMOOTH)) |_| {
        for (0..MAP_SIZE) |j| {
            var sum: c_int = height[from][j];
            for (0..8) |k| {
                var loc: c_long = @as(c_long, @intCast(j)) + data.dir_offset[k];
                if (loc < 0 or loc >= MAP_SIZE) loc = @intCast(j);
                sum += height[from][@intCast(loc)];
            }
            height[to][j] = @divTrunc(sum, 9);
        }
        const tmp = to;
        to = from;
        from = tmp;
    }

    // count cells at each height
    for (0..MAX_HEIGHT + 1) |i| height_count[i] = 0;
    for (0..MAP_SIZE) |i| {
        const h: usize = @intCast(height[from][i]);
        height_count[h] += 1;
    }

    // find the water line
    var water_line: c_long = MAX_HEIGHT;
    var sum: c_long = 0;
    for (0..MAX_HEIGHT + 1) |i| {
        sum += height_count[i];
        if (@divTrunc(sum * 100, MAP_SIZE) > globals.WATER_RATIO and sum >= NUM_CITY) {
            water_line = @intCast(i);
            break;
        }
    }

    // mark land and water
    for (0..MAP_SIZE) |i| {
        if (height[from][i] > @as(c_int, @intCast(water_line)))
            globals.map[i].contents = MAP_LAND
        else
            globals.map[i].contents = MAP_SEA;

        globals.map[i].objp = null;
        globals.map[i].cityp = null;

        const j: c_int = @intCast(util.loc_col(@as(c_long, @intCast(i))));
        const k: c_int = @intCast(util.loc_row(@as(c_long, @intCast(i))));

        globals.map[i].on_board = !(j == 0 or j == MAP_WIDTH - 1 or k == 0 or k == MAP_HEIGHT - 1);
    }
}

fn place_cities() void {
    var num_land: c_long = 0;
    var placed: c_long = 0;
    while (placed < NUM_CITY) {
        while (num_land == 0) num_land = regen_land(placed);
        const i: usize = @intCast(math.irand(num_land - 1));
        const loc: usize = @intCast(land[i]);

        const up: usize = @intCast(placed);
        globals.city[up].loc = land[i];
        globals.city[up].owner = UNOWNED;
        globals.city[up].work = 0;
        globals.city[up].prod = NOPIECE;

        for (0..NUM_OBJECTS) |fi| {
            globals.city[up].func[fi] = NOFUNC;
        }

        globals.map[loc].contents = MAP_CITY;
        globals.map[loc].cityp = &globals.city[up];
        placed += 1;

        num_land = remove_land(land[i], num_land);
    }
}

fn regen_land(placed: c_long) c_long {
    var num_land: c_long = 0;
    for (0..MAP_SIZE) |i| {
        if (globals.map[i].on_board and globals.map[i].contents == MAP_LAND) {
            land[@intCast(num_land)] = @intCast(i);
            num_land += 1;
        }
    }
    if (placed > 0) {
        globals.MIN_CITY_DIST -= 1;
        std.debug.assert(globals.MIN_CITY_DIST >= 0);
    }
    for (0..@intCast(placed)) |i| {
        num_land = remove_land(globals.city[i].loc, num_land);
    }
    return num_land;
}

fn remove_land(loc: c_long, num_land: c_long) c_long {
    var new_land: c_long = 0;
    for (0..@intCast(num_land)) |i| {
        if (math.dist(loc, land[i]) >= globals.MIN_CITY_DIST) {
            land[@intCast(new_land)] = land[i];
            new_land += 1;
        }
    }
    return new_land;
}

fn select_cities() bool {
    find_cont();
    if (ncont == 0) return false;

    make_pair();

    _ = c.snprintf(&globals.jnkbuf, STRSIZE,
        "Choose a difficulty level where 0 is easy and %d is hard: ",
        ncont * ncont - 1);

    const pair = terminal.get_range(&globals.jnkbuf, 0, ncont * ncont - 1);
    const comp_cont: usize = @intCast(pair_tab[@intCast(pair)].comp_cont);
    const user_cont: usize = @intCast(pair_tab[@intCast(pair)].user_cont);

    const compi: usize = @intCast(math.irand(@intCast(cont_tab[comp_cont].ncity)));
    const compp: [*c]city_info_t = cont_tab[comp_cont].cityp[compi];

    var userp: [*c]city_info_t = undefined;
    while (true) {
        const useri: usize = @intCast(math.irand(@intCast(cont_tab[user_cont].ncity)));
        userp = cont_tab[user_cont].cityp[useri];
        if (userp != compp) break;
    }

    terminal.topmsg(1, "Your city is at %d.", terminal.loc_disp(@intCast(userp.*.loc)));
    display.delay();

    compp.*.owner = COMP;
    compp.*.prod = @intCast(ARMY);
    compp.*.work = 0;
    object.scan(&globals.comp_map, compp.*.loc);

    userp.*.owner = USER;
    userp.*.work = 0;
    object.scan(&globals.user_map, userp.*.loc);
    object.set_prod(userp);
    return true;
}

fn find_cont() void {
    for (0..MAP_SIZE) |i| marked[i] = 0;

    ncont = 0;
    var mapi: c_long = 0;

    while (ncont < MAX_CONT) {
        if (!find_next(&mapi)) return;
    }
}

fn find_next(mapi: *c_long) bool {
    while (true) {
        if (mapi.* >= MAP_SIZE) return false;

        const um: usize = @intCast(mapi.*);
        if (!globals.map[um].on_board or marked[um] != 0 or globals.map[um].contents == MAP_SEA) {
            mapi.* += 1;
        } else if (good_cont(mapi.*)) {
            const unc: usize = @intCast(ncont);
            rank_tab[unc] = ncont;
            const val = cont_tab[unc].value;

            var i = ncont;
            while (i > 0) : (i -= 1) {
                const ui: usize = @intCast(i);
                const ui1: usize = @intCast(i - 1);
                if (val > cont_tab[@intCast(rank_tab[ui1])].value) {
                    rank_tab[ui] = rank_tab[ui1];
                    rank_tab[ui1] = ncont;
                } else break;
            }
            ncont += 1;
            return true;
        }
    }
}

fn good_cont(mapi: c_long) bool {
    mc_ncity = 0;
    mc_nland = 0;
    mc_nshore = 0;

    mark_cont(mapi);

    if (mc_nshore < 1 or mc_ncity < 2) return false;

    var val: c_long = undefined;
    if (mc_ncity == mc_nshore)
        val = (mc_nshore - 2) * 3
    else
        val = (mc_nshore - 1) * 3 + (mc_ncity - mc_nshore - 1) * 2;

    val *= 1000;
    val += mc_nland;
    const unc: usize = @intCast(ncont);
    cont_tab[unc].value = val;
    cont_tab[unc].ncity = mc_ncity;
    return true;
}

fn mark_cont(mapi: c_long) void {
    const um: usize = @intCast(mapi);
    if (marked[um] != 0 or globals.map[um].contents == MAP_SEA or !globals.map[um].on_board)
        return;

    marked[um] = 1;
    mc_nland += 1;

    if (globals.map[um].contents == MAP_CITY) {
        const unc: usize = @intCast(ncont);
        const unci: usize = @intCast(mc_ncity);
        cont_tab[unc].cityp[unci] = globals.map[um].cityp;
        mc_ncity += 1;
        if (map.rmap_shore(mapi)) mc_nshore += 1;
    }

    for (0..8) |i| {
        mark_cont(mapi + data.dir_offset[i]);
    }
}

fn make_pair() void {
    var npair: c_int = 0;

    var i: c_int = 0;
    while (i < ncont) : (i += 1) {
        var j: c_int = 0;
        while (j < ncont) : (j += 1) {
            const ui: usize = @intCast(i);
            const uj: usize = @intCast(j);
            const up: usize = @intCast(npair);
            const val = cont_tab[ui].value - cont_tab[uj].value;
            pair_tab[up].value = val;
            pair_tab[up].user_cont = i;
            pair_tab[up].comp_cont = j;

            var k = npair;
            while (k > 0) : (k -= 1) {
                const uk: usize = @intCast(k);
                const uk1: usize = @intCast(k - 1);
                if (val > pair_tab[uk1].value) {
                    pair_tab[uk] = pair_tab[uk1];
                    pair_tab[uk1].user_cont = i;
                    pair_tab[uk1].comp_cont = j;
                } else break;
            }
            npair += 1;
        }
    }
}

// Save/restore

fn xwrite(f: *c.FILE, buf: [*]u8, size: usize) bool {
    const bytes = c.fwrite(buf, 1, size, f);
    if (bytes != size) {
        c.perror("Write to save file failed");
        return false;
    }
    return true;
}

fn xread(f: *c.FILE, buf: [*]u8, size: usize) bool {
    const bytes = c.fread(buf, 1, size, f);
    if (bytes != size) {
        c.perror("Read from save file failed");
        return false;
    }
    return true;
}

pub export fn save_game() void {
    const f = c.fopen(globals.savefile, "w") orelse {
        c.perror("Cannot save saved game");
        return;
    };

    if (!xwrite(f, @ptrCast(&globals.map), @sizeOf(@TypeOf(globals.map)))) return;
    if (!xwrite(f, @ptrCast(&globals.comp_map), @sizeOf(@TypeOf(globals.comp_map)))) return;
    if (!xwrite(f, @ptrCast(&globals.user_map), @sizeOf(@TypeOf(globals.user_map)))) return;
    if (!xwrite(f, @ptrCast(&globals.city), @sizeOf(@TypeOf(globals.city)))) return;
    if (!xwrite(f, @ptrCast(&globals.object), @sizeOf(@TypeOf(globals.object)))) return;
    if (!xwrite(f, @ptrCast(&globals.user_obj), @sizeOf(@TypeOf(globals.user_obj)))) return;
    if (!xwrite(f, @ptrCast(&globals.comp_obj), @sizeOf(@TypeOf(globals.comp_obj)))) return;
    if (!xwrite(f, @ptrCast(&globals.free_list), @sizeOf(@TypeOf(globals.free_list)))) return;
    if (!xwrite(f, @ptrCast(&globals.date), @sizeOf(@TypeOf(globals.date)))) return;
    if (!xwrite(f, @ptrCast(&globals.automove), @sizeOf(@TypeOf(globals.automove)))) return;
    if (!xwrite(f, @ptrCast(&globals.resigned), @sizeOf(@TypeOf(globals.resigned)))) return;
    if (!xwrite(f, @ptrCast(&globals.debug), @sizeOf(@TypeOf(globals.debug)))) return;
    if (!xwrite(f, @ptrCast(&globals.win), @sizeOf(@TypeOf(globals.win)))) return;
    if (!xwrite(f, @ptrCast(&globals.save_movie), @sizeOf(@TypeOf(globals.save_movie)))) return;
    if (!xwrite(f, @ptrCast(&globals.user_score), @sizeOf(@TypeOf(globals.user_score)))) return;
    if (!xwrite(f, @ptrCast(&globals.comp_score), @sizeOf(@TypeOf(globals.comp_score)))) return;

    _ = c.fclose(f);
    terminal.topmsg(3, "Game saved.");
}

fn restore_game() bool {
    const f = c.fopen(globals.savefile, "r") orelse {
        c.perror("Cannot open saved game");
        return false;
    };

    if (!xread(f, @ptrCast(&globals.map), @sizeOf(@TypeOf(globals.map)))) return false;
    if (!xread(f, @ptrCast(&globals.comp_map), @sizeOf(@TypeOf(globals.comp_map)))) return false;
    if (!xread(f, @ptrCast(&globals.user_map), @sizeOf(@TypeOf(globals.user_map)))) return false;
    if (!xread(f, @ptrCast(&globals.city), @sizeOf(@TypeOf(globals.city)))) return false;
    if (!xread(f, @ptrCast(&globals.object), @sizeOf(@TypeOf(globals.object)))) return false;
    if (!xread(f, @ptrCast(&globals.user_obj), @sizeOf(@TypeOf(globals.user_obj)))) return false;
    if (!xread(f, @ptrCast(&globals.comp_obj), @sizeOf(@TypeOf(globals.comp_obj)))) return false;
    if (!xread(f, @ptrCast(&globals.free_list), @sizeOf(@TypeOf(globals.free_list)))) return false;
    if (!xread(f, @ptrCast(&globals.date), @sizeOf(@TypeOf(globals.date)))) return false;
    if (!xread(f, @ptrCast(&globals.automove), @sizeOf(@TypeOf(globals.automove)))) return false;
    if (!xread(f, @ptrCast(&globals.resigned), @sizeOf(@TypeOf(globals.resigned)))) return false;
    if (!xread(f, @ptrCast(&globals.debug), @sizeOf(@TypeOf(globals.debug)))) return false;
    if (!xread(f, @ptrCast(&globals.win), @sizeOf(@TypeOf(globals.win)))) return false;
    if (!xread(f, @ptrCast(&globals.save_movie), @sizeOf(@TypeOf(globals.save_movie)))) return false;
    if (!xread(f, @ptrCast(&globals.user_score), @sizeOf(@TypeOf(globals.user_score)))) return false;
    if (!xread(f, @ptrCast(&globals.comp_score), @sizeOf(@TypeOf(globals.comp_score)))) return false;

    // Recreate pointers
    globals.free_list = null;
    for (0..MAP_SIZE) |i| {
        globals.map[i].cityp = null;
        globals.map[i].objp = null;
    }
    for (0..LIST_SIZE) |i| {
        globals.object[i].loc_link.next = null;
        globals.object[i].loc_link.prev = null;
        globals.object[i].cargo_link.next = null;
        globals.object[i].cargo_link.prev = null;
        globals.object[i].piece_link.next = null;
        globals.object[i].piece_link.prev = null;
        globals.object[i].ship = null;
        globals.object[i].cargo = null;
    }
    for (0..NUM_OBJECTS) |i| {
        globals.comp_obj[i] = null;
        globals.user_obj[i] = null;
    }

    // put cities on map
    for (0..NUM_CITY) |i| {
        globals.map[@intCast(globals.city[i].loc)].cityp = &globals.city[i];
    }

    // put pieces in free list or on map and in object lists
    for (0..LIST_SIZE) |i| {
        const obj: *piece_info_t = &globals.object[i];
        if (globals.object[i].owner == UNOWNED or globals.object[i].hits == 0) {
            object.link(&globals.free_list, obj, .piece_link);
        } else {
            const list = if (globals.object[i].owner == USER) &globals.user_obj else &globals.comp_obj;
            const t: usize = @intCast(globals.object[i].type);
            object.link(&list[t], obj, .piece_link);
            object.link(&globals.map[@intCast(globals.object[i].loc)].objp, obj, .loc_link);
        }
    }

    // Embark armies and fighters
    read_embark(globals.user_obj[TRANSPORT], ARMY);
    read_embark(globals.user_obj[CARRIER], FIGHTER);
    read_embark(globals.comp_obj[TRANSPORT], ARMY);
    read_embark(globals.comp_obj[CARRIER], FIGHTER);

    _ = c.fclose(f);
    display.kill_display();
    terminal.topmsg(3, "Game restored from save file.");
    return true;
}

fn read_embark(list_head: [*c]piece_info_t, piece_type: c_int) void {
    var ship: [*c]piece_info_t = list_head;
    while (ship != null) : (ship = @ptrCast(ship.*.piece_link.next)) {
        var count = ship.*.count;
        if (count < 0) inconsistent();
        ship.*.count = 0;
        var obj: [*c]piece_info_t = globals.map[@intCast(ship.*.loc)].objp;
        while (obj != null and count > 0) : (obj = @ptrCast(obj.*.loc_link.next)) {
            if (obj.*.ship == null and obj.*.type == piece_type) {
                object.embark(@ptrCast(ship), @ptrCast(obj));
                count -= 1;
            }
        }
        if (count != 0) inconsistent();
    }
}

fn inconsistent() void {
    _ = c.printf("saved game is inconsistent.  Please remove it.\n");
    c.exit(1);
}

// Movie

pub export fn save_movie_screen() void {
    const f = c.fopen("empmovie.dat", "a") orelse {
        c.perror("Cannot open empmovie.dat");
        return;
    };

    for (0..MAP_SIZE) |i| {
        if (globals.map[i].cityp != null) {
            mapbuf[i] = object.city_char[globals.map[i].cityp.*.owner];
        } else {
            const p = object.find_obj_at_loc(@intCast(i));
            if (p == null) {
                mapbuf[i] = globals.map[i].contents;
            } else if (p.*.owner == USER) {
                mapbuf[i] = data.piece_attr[@intCast(p.*.type)].sname;
            } else {
                mapbuf[i] = data.piece_attr[@intCast(p.*.type)].sname | 0x20;
            }
        }
    }
    _ = xwrite(f, &mapbuf, @sizeOf(@TypeOf(mapbuf)));
    _ = c.fclose(f);
}

pub fn replay_movie() void {
    replay_movie_impl();
}

pub export fn replay_movie_c() void {
    replay_movie_impl();
}

fn replay_movie_impl() void {
    const f = c.fopen("empmovie.dat", "r") orelse {
        c.perror("Cannot open empmovie.dat");
        return;
    };

    var round: c_int = 0;
    display.clear_screen();
    while (true) {
        if (c.fread(&mapbuf, 1, @sizeOf(@TypeOf(mapbuf)), f) != @sizeOf(@TypeOf(mapbuf))) break;
        round += 1;

        stat_display(&mapbuf, round);

        const row_inc = @divTrunc(MAP_HEIGHT + globals.lines - 3 - 1, globals.lines - 3);
        const col_inc = @divTrunc(MAP_WIDTH + globals.cols - 1, globals.cols - 1);

        var r: c_int = 0;
        while (r < MAP_HEIGHT) : (r += row_inc) {
            var col: c_int = 0;
            while (col < MAP_WIDTH) : (col += col_inc) {
                display.print_movie_cell(&mapbuf, r, col, row_inc, col_inc);
            }
        }

        display.redisplay();
        display.delay();
    }
    _ = c.fclose(f);
}

const pieces = "OAFPDSTCBZXafpdstcbz";

fn stat_display(mbuf: [*]u8, round: c_int) void {
    var counts: [2 * NUM_OBJECTS + 2]c_int = std.mem.zeroes([2 * NUM_OBJECTS + 2]c_int);

    for (0..MAP_SIZE) |i| {
        if (std.mem.indexOfScalar(u8, pieces, mbuf[i])) |idx| {
            counts[idx] += 1;
        }
    }

    var user_cost: c_int = 0;
    for (1..NUM_OBJECTS + 1) |i| {
        user_cost += counts[i] * @as(c_int, data.piece_attr[i - 1].build_time);
    }

    var comp_cost: c_int = 0;
    for (NUM_OBJECTS + 2..2 * NUM_OBJECTS + 2) |i| {
        comp_cost += counts[i] * @as(c_int, data.piece_attr[i - NUM_OBJECTS - 2].build_time);
    }

    var i: c_int = 0;
    while (i < NUM_OBJECTS + 1) : (i += 1) {
        const ui: usize = @intCast(i);
        display.pos_str(1, i * 6, "%2d %c  ", counts[ui], @as(c_int, pieces[ui]));
        display.pos_str(2, i * 6, "%2d %c  ", counts[ui + NUM_OBJECTS + 1], @as(c_int, pieces[ui + NUM_OBJECTS + 1]));
    }

    display.pos_str(1, i * 6, "%5d", user_cost);
    display.pos_str(2, i * 6, "%5d", comp_cost);
    display.pos_str(0, 0, "Round %3d", @divTrunc(round + 1, 2));
}
