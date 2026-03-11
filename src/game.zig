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

const Piece = types.Piece;
const PieceIdx = types.PieceIdx;
const NO_PIECE = types.NO_PIECE;
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
const ARMY: i32 = @intFromEnum(globals.PieceType.Army);
const FIGHTER: i32 = @intFromEnum(globals.PieceType.Fighter);
const TRANSPORT: i32 = @intFromEnum(globals.PieceType.Transport);
const CARRIER: i32 = @intFromEnum(globals.PieceType.Carrier);
const NOFUNC = @as(i64, @intFromEnum(globals.Function.NoFunc));

const MAP_LAND = data.MAP_LAND;
const MAP_SEA = data.MAP_SEA;
const MAP_CITY = data.MAP_CITY;

const MAX_HEIGHT = 999;
const MAX_CONT = 10;

// Static arrays for map generation
var height: [2][MAP_SIZE]i32 = undefined;
var height_count: [MAX_HEIGHT + 1]i32 = undefined;
var land: [MAP_SIZE]i64 = undefined;

// Continent data
const cont_t = struct {
    value: i64,
    ncity: i32,
    cityp: [NUM_CITY]?*city_info_t,
};

const pair_t = struct {
    value: i64,
    user_cont: i32,
    comp_cont: i32,
};

var marked: [MAP_SIZE]i32 = std.mem.zeroes([MAP_SIZE]i32);
var ncont: i32 = 0;
var cont_tab: [MAX_CONT]cont_t = undefined;
var rank_tab: [MAX_CONT]i32 = undefined;
var pair_tab: [MAX_CONT * MAX_CONT]pair_t = undefined;

// Statics for mark_cont
var mc_ncity: i32 = 0;
var mc_nland: i64 = 0;
var mc_nshore: i32 = 0;

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

pub fn init_game() void {
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
    object.pool_init();

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
            var sum: i32 = height[from][j];
            for (0..8) |k| {
                var loc: i64 = @as(i64, @intCast(j)) + data.dir_offset[k];
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
    var water_line: i64 = MAX_HEIGHT;
    var sum: i64 = 0;
    for (0..MAX_HEIGHT + 1) |i| {
        sum += height_count[i];
        if (@divTrunc(sum * 100, MAP_SIZE) > globals.WATER_RATIO and sum >= NUM_CITY) {
            water_line = @intCast(i);
            break;
        }
    }

    // mark land and water
    for (0..MAP_SIZE) |i| {
        if (height[from][i] > @as(i32, @intCast(water_line)))
            globals.map[i].contents = MAP_LAND
        else
            globals.map[i].contents = MAP_SEA;

        globals.map[i].obj_head = NO_PIECE;
        globals.map[i].cityp = null;

        const j: i32 = @intCast(util.loc_col(@as(i64, @intCast(i))));
        const k: i32 = @intCast(util.loc_row(@as(i64, @intCast(i))));

        globals.map[i].on_board = !(j == 0 or j == MAP_WIDTH - 1 or k == 0 or k == MAP_HEIGHT - 1);
    }
}

fn place_cities() void {
    var num_land: i64 = 0;
    var placed: i64 = 0;
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

fn regen_land(placed: i64) i64 {
    var num_land: i64 = 0;
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

fn remove_land(loc: i64, num_land: i64) i64 {
    var new_land: i64 = 0;
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

    const range_msg = std.fmt.bufPrintZ(&globals.jnkbuf, "Choose a difficulty level where 0 is easy and {d} is hard: ", .{ncont * ncont - 1}) catch unreachable;

    const pair = terminal.get_range(range_msg.ptr, 0, ncont * ncont - 1);
    const comp_cont: usize = @intCast(pair_tab[@intCast(pair)].comp_cont);
    const user_cont: usize = @intCast(pair_tab[@intCast(pair)].user_cont);

    const compi: usize = @intCast(math.irand(@intCast(cont_tab[comp_cont].ncity)));
    const compp: *city_info_t = cont_tab[comp_cont].cityp[compi].?;

    var userp: *city_info_t = undefined;
    while (true) {
        const useri: usize = @intCast(math.irand(@intCast(cont_tab[user_cont].ncity)));
        userp = cont_tab[user_cont].cityp[useri].?;
        if (userp != compp) break;
    }

    terminal.topmsg(1, "Your city is at {d}.", .{terminal.loc_disp(@intCast(userp.loc))});
    display.delay();

    compp.owner = COMP;
    compp.prod = @intCast(ARMY);
    compp.work = 0;
    object.scan(&globals.comp_map, compp.loc);

    userp.owner = USER;
    userp.work = 0;
    object.scan(&globals.user_map, userp.loc);
    object.set_prod(userp);
    return true;
}

fn find_cont() void {
    for (0..MAP_SIZE) |i| marked[i] = 0;

    ncont = 0;
    var mapi: i64 = 0;

    while (ncont < MAX_CONT) {
        if (!find_next(&mapi)) return;
    }
}

fn find_next(mapi: *i64) bool {
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

fn good_cont(mapi: i64) bool {
    mc_ncity = 0;
    mc_nland = 0;
    mc_nshore = 0;

    mark_cont(mapi);

    if (mc_nshore < 1 or mc_ncity < 2) return false;

    var val: i64 = undefined;
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

fn mark_cont(mapi: i64) void {
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
    var npair: i32 = 0;

    var i: i32 = 0;
    while (i < ncont) : (i += 1) {
        var j: i32 = 0;
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

const SAVE_MAGIC: u32 = 0x5A454D50; // "ZEMP"
const SAVE_VERSION: u32 = 2; // v2 = pool-based format

fn xwrite(f: std.fs.File, buf: [*]u8, size: usize) bool {
    f.writeAll(buf[0..size]) catch {
        std.debug.print("Write to save file failed\n", .{});
        return false;
    };
    return true;
}

fn xread(f: std.fs.File, buf: [*]u8, size: usize) bool {
    const n = f.readAll(buf[0..size]) catch {
        std.debug.print("Read from save file failed\n", .{});
        return false;
    };
    if (n != size) {
        std.debug.print("Read from save file failed: short read\n", .{});
        return false;
    }
    return true;
}

pub fn save_game() void {
    const savename = std.mem.span(globals.savefile orelse return);
    const f = std.fs.cwd().createFile(savename, .{}) catch {
        std.debug.print("Cannot save saved game\n", .{});
        return;
    };
    defer f.close();

    // Write saved pieces (portable format without pointers)
    var saved_pieces: [LIST_SIZE]types.SavedPiece = undefined;
    for (0..LIST_SIZE) |i| {
        const p = &globals.pool[i];
        saved_pieces[i] = .{
            .owner = p.owner,
            .type = p.type,
            .loc = p.loc,
            .func = p.func,
            .hits = p.hits,
            .moved = p.moved,
            .ship = p.ship,
            .count = p.count,
            .range = p.range,
            .alive = if (p.alive) 1 else 0,
        };
    }

    // Write saved map (without pointers)
    var saved_map: [MAP_SIZE]types.SavedMapCell = undefined;
    for (0..MAP_SIZE) |i| {
        saved_map[i] = .{
            .contents = globals.map[i].contents,
            .on_board = if (globals.map[i].on_board) 1 else 0,
        };
    }

    var magic = SAVE_MAGIC;
    var version = SAVE_VERSION;
    if (!xwrite(f, @ptrCast(&magic), @sizeOf(u32))) return;
    if (!xwrite(f, @ptrCast(&version), @sizeOf(u32))) return;
    if (!xwrite(f, @ptrCast(&saved_map), @sizeOf(@TypeOf(saved_map)))) return;
    if (!xwrite(f, @ptrCast(&globals.comp_map), @sizeOf(@TypeOf(globals.comp_map)))) return;
    if (!xwrite(f, @ptrCast(&globals.user_map), @sizeOf(@TypeOf(globals.user_map)))) return;
    if (!xwrite(f, @ptrCast(&globals.city), @sizeOf(@TypeOf(globals.city)))) return;
    if (!xwrite(f, @ptrCast(&saved_pieces), @sizeOf(@TypeOf(saved_pieces)))) return;
    if (!xwrite(f, @ptrCast(&globals.date), @sizeOf(@TypeOf(globals.date)))) return;
    if (!xwrite(f, @ptrCast(&globals.automove), @sizeOf(@TypeOf(globals.automove)))) return;
    if (!xwrite(f, @ptrCast(&globals.resigned), @sizeOf(@TypeOf(globals.resigned)))) return;
    if (!xwrite(f, @ptrCast(&globals.debug), @sizeOf(@TypeOf(globals.debug)))) return;
    if (!xwrite(f, @ptrCast(&globals.win), @sizeOf(@TypeOf(globals.win)))) return;
    if (!xwrite(f, @ptrCast(&globals.save_movie), @sizeOf(@TypeOf(globals.save_movie)))) return;
    if (!xwrite(f, @ptrCast(&globals.user_score), @sizeOf(@TypeOf(globals.user_score)))) return;
    if (!xwrite(f, @ptrCast(&globals.comp_score), @sizeOf(@TypeOf(globals.comp_score)))) return;

    terminal.topmsg(3, "Game saved.", .{});
}

fn restore_game() bool {
    const savename = std.mem.span(globals.savefile orelse return false);
    const f = std.fs.cwd().openFile(savename, .{}) catch {
        std.debug.print("Cannot open saved game\n", .{});
        return false;
    };
    defer f.close();

    var magic: u32 = 0;
    var version: u32 = 0;
    if (!xread(f, @ptrCast(&magic), @sizeOf(u32))) return false;
    if (!xread(f, @ptrCast(&version), @sizeOf(u32))) return false;
    if (magic != SAVE_MAGIC or version != SAVE_VERSION) {
        std.debug.print("Save file is incompatible (old format). Please delete it and start a new game.\n", .{});
        return false;
    }

    var saved_pieces: [LIST_SIZE]types.SavedPiece = undefined;
    var saved_map: [MAP_SIZE]types.SavedMapCell = undefined;

    if (!xread(f, @ptrCast(&saved_map), @sizeOf(@TypeOf(saved_map)))) return false;
    if (!xread(f, @ptrCast(&globals.comp_map), @sizeOf(@TypeOf(globals.comp_map)))) return false;
    if (!xread(f, @ptrCast(&globals.user_map), @sizeOf(@TypeOf(globals.user_map)))) return false;
    if (!xread(f, @ptrCast(&globals.city), @sizeOf(@TypeOf(globals.city)))) return false;
    if (!xread(f, @ptrCast(&saved_pieces), @sizeOf(@TypeOf(saved_pieces)))) return false;
    if (!xread(f, @ptrCast(&globals.date), @sizeOf(@TypeOf(globals.date)))) return false;
    if (!xread(f, @ptrCast(&globals.automove), @sizeOf(@TypeOf(globals.automove)))) return false;
    if (!xread(f, @ptrCast(&globals.resigned), @sizeOf(@TypeOf(globals.resigned)))) return false;
    if (!xread(f, @ptrCast(&globals.debug), @sizeOf(@TypeOf(globals.debug)))) return false;
    if (!xread(f, @ptrCast(&globals.win), @sizeOf(@TypeOf(globals.win)))) return false;
    if (!xread(f, @ptrCast(&globals.save_movie), @sizeOf(@TypeOf(globals.save_movie)))) return false;
    if (!xread(f, @ptrCast(&globals.user_score), @sizeOf(@TypeOf(globals.user_score)))) return false;
    if (!xread(f, @ptrCast(&globals.comp_score), @sizeOf(@TypeOf(globals.comp_score)))) return false;

    // Restore map from saved format
    for (0..MAP_SIZE) |i| {
        globals.map[i].contents = saved_map[i].contents;
        globals.map[i].on_board = saved_map[i].on_board != 0;
        globals.map[i].cityp = null;
        globals.map[i].obj_head = NO_PIECE;
    }

    // Restore pool from saved pieces
    for (0..LIST_SIZE) |i| {
        const sp = &saved_pieces[i];
        globals.pool[i] = .{
            .owner = sp.owner,
            .type = sp.type,
            .loc = sp.loc,
            .func = sp.func,
            .hits = sp.hits,
            .moved = sp.moved,
            .ship = sp.ship,
            .count = sp.count,
            .range = sp.range,
            .alive = sp.alive != 0,
        };
    }

    // Rebuild city pointers on map
    for (0..NUM_CITY) |i| {
        globals.map[@intCast(globals.city[i].loc)].cityp = &globals.city[i];
    }

    // Rebuild location chains, free stack, and cargo
    object.rebuild_loc_chains();
    object.rebuild_free_stack();
    object.rebuild_embark();

    // Reconcile view maps with actual game state to fix any stale entries
    object.refresh_view_maps();

    display.kill_display();
    terminal.topmsg(3, "Game restored from save file.", .{});
    return true;
}

// Movie

pub fn save_movie_screen() void {
    const f = std.fs.cwd().openFile("empmovie.dat", .{ .mode = .write_only }) catch
        std.fs.cwd().createFile("empmovie.dat", .{}) catch {
        std.debug.print("Cannot open empmovie.dat\n", .{});
        return;
    };
    defer f.close();
    f.seekFromEnd(0) catch return;

    for (0..MAP_SIZE) |i| {
        if (globals.map[i].cityp) |cp| {
            mapbuf[i] = object.city_char[cp.*.owner];
        } else {
            if (object.find_obj_at_loc(@intCast(i))) |p| {
                if (p.owner == USER) {
                    mapbuf[i] = data.piece_attr[@intCast(p.type)].sname;
                } else {
                    mapbuf[i] = data.piece_attr[@intCast(p.type)].sname | 0x20;
                }
            } else {
                mapbuf[i] = globals.map[i].contents;
            }
        }
    }
    _ = xwrite(f, &mapbuf, @sizeOf(@TypeOf(mapbuf)));
}

pub fn replay_movie() void {
    replay_movie_impl();
}

pub fn replay_movie_c() void {
    replay_movie_impl();
}

fn replay_movie_impl() void {
    const f = std.fs.cwd().openFile("empmovie.dat", .{}) catch {
        std.debug.print("Cannot open empmovie.dat\n", .{});
        return;
    };
    defer f.close();

    var round: i32 = 0;
    display.clear_screen();
    while (true) {
        const n = f.readAll(&mapbuf) catch break;
        if (n != @sizeOf(@TypeOf(mapbuf))) break;
        round += 1;

        stat_display(&mapbuf, round);

        const row_inc = @divTrunc(MAP_HEIGHT + globals.lines - 3 - 1, globals.lines - 3);
        const col_inc = @divTrunc(MAP_WIDTH + globals.cols - 1, globals.cols - 1);

        var r: i32 = 0;
        while (r < MAP_HEIGHT) : (r += row_inc) {
            var col: i32 = 0;
            while (col < MAP_WIDTH) : (col += col_inc) {
                display.print_movie_cell(&mapbuf, r, col, row_inc, col_inc);
            }
        }

        display.redisplay();
        display.delay();
    }
}

const pieces = "OAFPDSTCBZXafpdstcbz";

fn stat_display(mbuf: [*]u8, round: i32) void {
    var counts: [2 * NUM_OBJECTS + 2]i32 = std.mem.zeroes([2 * NUM_OBJECTS + 2]i32);

    for (0..MAP_SIZE) |i| {
        if (std.mem.indexOfScalar(u8, pieces, mbuf[i])) |idx| {
            counts[idx] += 1;
        }
    }

    var user_cost: i32 = 0;
    for (1..NUM_OBJECTS + 1) |i| {
        user_cost += counts[i] * @as(i32, data.piece_attr[i - 1].build_time);
    }

    var comp_cost: i32 = 0;
    for (NUM_OBJECTS + 2..2 * NUM_OBJECTS + 2) |i| {
        comp_cost += counts[i] * @as(i32, data.piece_attr[i - NUM_OBJECTS - 2].build_time);
    }

    var i: i32 = 0;
    while (i < NUM_OBJECTS + 1) : (i += 1) {
        const ui: usize = @intCast(i);
        display.pos_str(1, i * 6, "{d:2} {c}  ", .{ counts[ui], pieces[ui] });
        display.pos_str(2, i * 6, "{d:2} {c}  ", .{ counts[ui + NUM_OBJECTS + 1], pieces[ui + NUM_OBJECTS + 1] });
    }

    display.pos_str(1, i * 6, "{d:5}", .{user_cost});
    display.pos_str(2, i * 6, "{d:5}", .{comp_cost});
    display.pos_str(0, 0, "Round {d:3}", .{@divTrunc(round + 1, 2)});
}
