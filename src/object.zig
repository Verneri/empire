const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const terminal = @import("terminal.zig");
const math = @import("math.zig");

const Piece = types.Piece;
const PieceIdx = types.PieceIdx;
const NO_PIECE = types.NO_PIECE;
const city_info_t = types.city_info_t;
const view_map_t = types.view_map_t;

const STRSIZE = globals.STRSIZE;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const NUM_CITY = globals.NUM_CITY;
const MAP_SIZE = globals.MAP_SIZE;
const LIST_SIZE = globals.LIST_SIZE;
const INFINITY = 10000000;

const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);
const UNOWNED = @intFromEnum(globals.Ownership.Unowned);
const NOPIECE: i32 = @intFromEnum(globals.PieceType.NoPiece);
const ARMY = @intFromEnum(globals.PieceType.Army);
const FIGHTER = @intFromEnum(globals.PieceType.Fighter);
const TRANSPORT = @intFromEnum(globals.PieceType.Transport);
const CARRIER = @intFromEnum(globals.PieceType.Carrier);
const SATELLITE = @intFromEnum(globals.PieceType.Satellite);
const NOFUNC = @as(i64, @intFromEnum(globals.Function.NoFunc));

const MOVE_NW = @as(i64, @intFromEnum(globals.Function.Move_NW));
const MOVE_NE = @as(i64, @intFromEnum(globals.Function.Move_NE));
const MOVE_SW = @as(i64, @intFromEnum(globals.Function.Move_SW));
const MOVE_SE = @as(i64, @intFromEnum(globals.Function.Move_SE));
const MOVE_N = @as(i64, @intFromEnum(globals.Function.Move_N));

const MAP_CITY = data.MAP_CITY;

const sat_dir = [4]i64{ MOVE_NW, MOVE_SW, MOVE_NE, MOVE_SE };
pub var city_char: [3]u8 = .{ MAP_CITY, 'O', 'X' };

fn funci(x: i64) usize {
    return @intCast(-x - 1);
}

fn moveDir(a: i64) usize {
    return @intCast(-a + MOVE_N);
}

fn ownerMap(owner: i32) *[MAP_SIZE]view_map_t {
    return if (owner == USER) &globals.user_map else &globals.comp_map;
}

// ── Pool operations ─────────────────────────────────────────────────────

pub fn pool_init() void {
    for (0..LIST_SIZE) |i| {
        globals.pool[i] = .{};
        globals.free_stack[i] = @intCast(i);
    }
    globals.free_count = LIST_SIZE;
    for (0..MAP_SIZE) |i| {
        globals.map[i].obj_head = NO_PIECE;
    }
}

pub fn pool_spawn() PieceIdx {
    std.debug.assert(globals.free_count > 0);
    globals.free_count -= 1;
    const idx = globals.free_stack[globals.free_count];
    globals.pool[idx] = .{ .alive = true };
    return idx;
}

pub fn pool_kill(idx: PieceIdx) void {
    globals.pool[idx] = .{};
    globals.free_stack[globals.free_count] = idx;
    globals.free_count += 1;
}

pub fn pool_get(idx: PieceIdx) ?*Piece {
    if (idx == NO_PIECE) return null;
    const p = &globals.pool[idx];
    if (!p.alive) return null;
    return p;
}

pub fn pool_indexOf(piece: *const Piece) PieceIdx {
    const base = @intFromPtr(&globals.pool);
    const ptr = @intFromPtr(piece);
    return @intCast((ptr - base) / @sizeOf(Piece));
}

// ── Location chain operations ───────────────────────────────────────────

fn loc_link(loc: i64, idx: PieceIdx) void {
    const uloc: usize = @intCast(loc);
    globals.pool[idx].loc_next = globals.map[uloc].obj_head;
    globals.map[uloc].obj_head = idx;
}

fn loc_unlink(loc: i64, idx: PieceIdx) void {
    const uloc: usize = @intCast(loc);
    if (globals.map[uloc].obj_head == idx) {
        globals.map[uloc].obj_head = globals.pool[idx].loc_next;
    } else {
        var prev = globals.map[uloc].obj_head;
        while (prev != NO_PIECE) {
            if (globals.pool[prev].loc_next == idx) {
                globals.pool[prev].loc_next = globals.pool[idx].loc_next;
                break;
            }
            prev = globals.pool[prev].loc_next;
        }
    }
    globals.pool[idx].loc_next = NO_PIECE;
}

// ── Cargo operations ────────────────────────────────────────────────────

pub fn embark(ship: *Piece, obj: *Piece) void {
    const obj_idx = pool_indexOf(obj);
    const ship_idx = pool_indexOf(ship);
    obj.ship = ship_idx;
    const ci: usize = @intCast(ship.count);
    ship.cargo[ci] = obj_idx;
    ship.count += 1;
}

pub fn disembark(obj: *Piece) void {
    if (obj.ship == NO_PIECE) return;
    const ship = &globals.pool[obj.ship];
    const obj_idx = pool_indexOf(obj);
    var i: usize = 0;
    while (i < @as(usize, @intCast(ship.count))) : (i += 1) {
        if (ship.cargo[i] == obj_idx) {
            ship.count -= 1;
            ship.cargo[i] = ship.cargo[@intCast(ship.count)];
            ship.cargo[@intCast(ship.count)] = NO_PIECE;
            break;
        }
    }
    obj.ship = NO_PIECE;
}

// ── Public API ──────────────────────────────────────────────────────────

pub fn find_nearest_city(loc: i64, owner: i32, city_loc: *i64) i32 {
    var best_loc: i64 = loc;
    var best_dist: i64 = INFINITY;

    for (0..NUM_CITY) |i| {
        if (globals.city[i].owner == @as(u8, @intCast(owner))) {
            const new_dist = math.dist(loc, globals.city[i].loc);
            if (new_dist < best_dist) {
                best_dist = new_dist;
                best_loc = globals.city[i].loc;
            }
        }
    }
    city_loc.* = best_loc;
    return @intCast(best_dist);
}

pub fn find_city(loc: i64) ?*city_info_t {
    return globals.map[@intCast(loc)].cityp;
}

pub fn obj_moves(obj: *const Piece) i32 {
    const t: usize = @intCast(obj.type);
    return @divTrunc(@as(i32, data.piece_attr[t].speed) * obj.hits +
        @as(i32, data.piece_attr[t].max_hits) - 1, @as(i32, data.piece_attr[t].max_hits));
}

pub fn obj_capacity(obj: *const Piece) i32 {
    const t: usize = @intCast(obj.type);
    return @divTrunc(@as(i32, data.piece_attr[t].capacity) * obj.hits +
        @as(i32, data.piece_attr[t].max_hits) - 1, @as(i32, data.piece_attr[t].max_hits));
}

pub fn moves(obj: *const Piece) i32 {
    return obj_moves(obj);
}

pub fn capacity(obj: *const Piece) i32 {
    return obj_capacity(obj);
}

pub fn find_obj(piece_type: i32, loc: i64) ?*Piece {
    var idx = globals.map[@intCast(loc)].obj_head;
    while (idx != NO_PIECE) {
        const p = &globals.pool[idx];
        if (p.type == piece_type) return p;
        idx = p.loc_next;
    }
    return null;
}

pub fn find_nfull(piece_type: i32, loc: i64) ?*Piece {
    var idx = globals.map[@intCast(loc)].obj_head;
    while (idx != NO_PIECE) {
        const p = &globals.pool[idx];
        if (p.type == piece_type and obj_capacity(p) > p.count) return p;
        idx = p.loc_next;
    }
    return null;
}

pub fn find_transport(owner: i32, loc: i64) i64 {
    for (0..8) |i| {
        const new_loc = loc + @as(i64, data.dir_offset[i]);
        if (find_nfull(TRANSPORT, new_loc)) |t| {
            if (t.owner == owner) return new_loc;
        }
    }
    return loc;
}

pub fn find_obj_at_loc(loc: i64) ?*Piece {
    var idx = globals.map[@intCast(loc)].obj_head;
    if (idx == NO_PIECE) return null;
    var best = &globals.pool[idx];
    idx = best.loc_next;
    while (idx != NO_PIECE) {
        const p = &globals.pool[idx];
        if (p.type > best.type and p.type != SATELLITE) best = p;
        idx = p.loc_next;
    }
    return best;
}

pub fn kill_obj(obj: *Piece, loc: i64) void {
    const vmap = ownerMap(obj.owner);

    // Kill cargo first
    while (obj.count > 0) {
        const cargo_idx = obj.cargo[0];
        kill_one(&globals.pool[cargo_idx]);
    }

    kill_one(obj);
    scan(vmap, loc);
}

fn kill_one(obj: *Piece) void {
    const idx = pool_indexOf(obj);
    const t: usize = @intCast(obj.type);
    loc_unlink(obj.loc, idx);
    disembark(obj);
    obj.hits = 0;
    obj.moved = data.piece_attr[t].speed;
    pool_kill(idx);
}

pub fn kill_city(cityp: *city_info_t) void {
    // Collect all piece indices at this location first (iteration-safe)
    var pieces: [128]PieceIdx = undefined;
    var npieces: usize = 0;
    var idx = globals.map[@intCast(cityp.loc)].obj_head;
    while (idx != NO_PIECE) {
        pieces[npieces] = idx;
        npieces += 1;
        idx = globals.pool[idx].loc_next;
    }

    for (pieces[0..npieces]) |pidx| {
        const p = &globals.pool[pidx];
        if (!p.alive) continue;

        if (p.type == ARMY) {
            kill_obj(p, cityp.loc);
        } else if (p.type != SATELLITE) {
            if (p.type == TRANSPORT) {
                while (p.count > 0) {
                    kill_one(&globals.pool[p.cargo[0]]);
                }
            }
            // Transfer ownership
            p.owner = if (p.owner == USER) COMP else USER;
            p.func = NOFUNC;
        }
    }

    if (cityp.owner != UNOWNED) {
        const vmap = ownerMap(@intCast(cityp.owner));
        cityp.owner = UNOWNED;
        cityp.work = 0;
        cityp.prod = @intCast(NOPIECE);

        for (0..NUM_OBJECTS) |i| {
            cityp.func[i] = NOFUNC;
        }

        scan(vmap, cityp.loc);
    }
}

pub fn produce(cityp: *city_info_t) void {
    const prod: usize = @intCast(cityp.prod);
    cityp.work -= data.piece_attr[prod].build_time;

    std.debug.assert(globals.free_count > 0);
    const new_idx = pool_spawn();
    const new_piece = &globals.pool[new_idx];

    new_piece.loc = cityp.loc;
    new_piece.func = NOFUNC;
    new_piece.hits = data.piece_attr[prod].max_hits;
    new_piece.owner = @intCast(cityp.owner);
    new_piece.type = cityp.prod;
    new_piece.moved = 0;
    new_piece.ship = NO_PIECE;
    new_piece.count = 0;
    new_piece.range = @truncate(data.piece_attr[prod].range);

    if (new_piece.type == SATELLITE) {
        new_piece.func = sat_dir[@intCast(math.irand(4))];
    }

    loc_link(cityp.loc, new_idx);
}

pub fn move_obj(obj: *Piece, new_loc: i64) void {
    std.debug.assert(obj.hits > 0);
    const vmap = ownerMap(obj.owner);
    const idx = pool_indexOf(obj);

    const old_loc = obj.loc;
    obj.moved += 1;
    obj.loc = new_loc;
    obj.range -= 1;

    disembark(obj);

    loc_unlink(old_loc, idx);
    loc_link(new_loc, idx);

    // Move cargo
    var i: usize = 0;
    while (i < @as(usize, @intCast(obj.count))) : (i += 1) {
        const cargo_idx = obj.cargo[i];
        const cargo_piece = &globals.pool[cargo_idx];
        cargo_piece.loc = new_loc;
        loc_unlink(old_loc, cargo_idx);
        loc_link(new_loc, cargo_idx);
    }

    // Board new ship
    switch (obj.type) {
        FIGHTER => {
            if (globals.map[@intCast(obj.loc)].cityp == null) {
                if (find_nfull(CARRIER, obj.loc)) |carrier| {
                    embark(carrier, obj);
                }
            }
        },
        ARMY => {
            if (find_nfull(TRANSPORT, obj.loc)) |transport| {
                embark(transport, obj);
            }
        },
        else => {},
    }

    if (obj.type == SATELLITE) scan_sat(vmap, obj.loc);
    update(vmap, old_loc);
    scan(vmap, obj.loc);
}

fn bounce(loc: i64, dir1: i64, dir2: i64, dir3: i64) i64 {
    var new_loc = loc + @as(i64, data.dir_offset[moveDir(dir1)]);
    if (globals.map[@intCast(new_loc)].on_board) return dir1;

    new_loc = loc + @as(i64, data.dir_offset[moveDir(dir2)]);
    if (globals.map[@intCast(new_loc)].on_board) return dir2;

    return dir3;
}

fn move_sat1(obj: *Piece) void {
    var dir = moveDir(obj.func);
    var new_loc = obj.loc + @as(i64, data.dir_offset[dir]);

    if (!globals.map[@intCast(new_loc)].on_board) {
        if (obj.func == MOVE_NE) {
            obj.func = bounce(obj.loc, MOVE_NW, MOVE_SE, MOVE_SW);
        } else if (obj.func == MOVE_NW) {
            obj.func = bounce(obj.loc, MOVE_NE, MOVE_SW, MOVE_SE);
        } else if (obj.func == MOVE_SE) {
            obj.func = bounce(obj.loc, MOVE_SW, MOVE_NE, MOVE_NW);
        } else if (obj.func == MOVE_SW) {
            obj.func = bounce(obj.loc, MOVE_SE, MOVE_NW, MOVE_NE);
        } else {
            unreachable;
        }
        dir = moveDir(obj.func);
        new_loc = obj.loc + @as(i64, data.dir_offset[dir]);
    }
    move_obj(obj, new_loc);
}

pub fn move_sat(obj: *Piece) void {
    obj.moved = 0;

    while (obj.moved < obj_moves(obj)) {
        move_sat1(obj);
        if (obj.range == 0) {
            if (obj.owner == USER)
                terminal.comment("Satellite at {d} crashed and burned.", .{terminal.loc_disp(@intCast(obj.loc))});
            terminal.ksend("Satellite at {d} crashed and burned.", .{terminal.loc_disp(@intCast(obj.loc))});
            kill_obj(obj, obj.loc);
            return;
        }
    }
}

pub fn good_loc(obj: *const Piece, loc: i64) bool {
    const uloc: usize = @intCast(loc);
    if (!globals.map[uloc].on_board) return false;

    const vmap = ownerMap(obj.owner);
    const t: usize = @intCast(obj.type);
    const terrain = &data.piece_attr[t].terrain;
    const contents = vmap[@intCast(loc)].contents;

    for (terrain) |ch| {
        if (ch == 0) break;
        if (ch == contents) return true;
    }

    if (obj.type == ARMY) {
        const p = find_nfull(TRANSPORT, loc);
        return (p != null and p.?.owner == obj.owner);
    }

    if (globals.map[uloc].cityp) |cp| {
        if (cp.owner == @as(u8, @intCast(obj.owner))) return true;
    }

    if (obj.type == FIGHTER) {
        const p = find_nfull(CARRIER, loc);
        return (p != null and p.?.owner == obj.owner);
    }

    return false;
}

pub fn describe_obj(obj: *const Piece) void {
    const ti: usize = @intCast(obj.type);
    const name = std.mem.sliceTo(&data.piece_attr[ti].name, 0);
    const loc = terminal.loc_disp(@intCast(obj.loc));
    const remaining_moves = obj_moves(obj) - obj.moved;

    var func_buf: [64]u8 = undefined;
    const func_str = if (obj.func >= 0)
        std.fmt.bufPrintZ(&func_buf, "{d}", .{terminal.loc_disp(@intCast(obj.func))}) catch ""
    else
        std.fmt.bufPrintZ(&func_buf, "{s}", .{data.func_name[funci(obj.func)]}) catch "";

    var other_buf: [64]u8 = undefined;
    const other_str = if (obj.type == FIGHTER)
        std.fmt.bufPrintZ(&other_buf, "; range = {d}", .{obj.range}) catch ""
    else if (obj.type == TRANSPORT)
        std.fmt.bufPrintZ(&other_buf, "; armies = {d}", .{obj.count}) catch ""
    else if (obj.type == CARRIER)
        std.fmt.bufPrintZ(&other_buf, "; fighters = {d}", .{obj.count}) catch ""
    else
        "";

    var buf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{s} at {d}:  moves = {d}; hits = {d}; func = {s}{s}", .{
        name, loc, remaining_moves, @as(i32, obj.hits), func_str, other_str,
    }) catch return;
    terminal.writeTopmsg(1, s);
}

pub fn scan(vmap: *[MAP_SIZE]view_map_t, loc: i64) void {
    std.debug.assert(globals.map[@intCast(loc)].on_board);

    for (0..8) |i| {
        const xloc = loc + @as(i64, data.dir_offset[i]);
        update(vmap, xloc);
    }
    update(vmap, loc);
}

fn scan_sat(vmap: *[MAP_SIZE]view_map_t, loc: i64) void {
    std.debug.assert(globals.map[@intCast(loc)].on_board);

    for (0..8) |i| {
        const xloc = loc + @as(i64, 2 * data.dir_offset[i]);
        if (xloc >= 0 and xloc < MAP_SIZE and globals.map[@intCast(xloc)].on_board)
            scan(vmap, xloc);
    }
    scan(vmap, loc);
}

fn update(vmap: *[MAP_SIZE]view_map_t, loc: i64) void {
    const uloc: usize = @intCast(loc);
    vmap[uloc].seen = globals.date;

    if (globals.map[uloc].cityp) |cp| {
        vmap[uloc].contents = city_char[cp.owner];
    } else {
        const p = find_obj_at_loc(loc);
        if (p == null) {
            vmap[uloc].contents = globals.map[uloc].contents;
        } else if (p.?.owner == USER) {
            vmap[uloc].contents = data.piece_attr[@intCast(p.?.type)].sname;
        } else {
            vmap[uloc].contents = data.piece_attr[@intCast(p.?.type)].sname | 0x20;
        }
    }

    if (vmap == &globals.comp_map)
        display.display_locx(COMP, &globals.comp_map, loc)
    else if (vmap == &globals.user_map)
        display.display_locx(USER, &globals.user_map, loc);
}

pub fn set_prod(cityp: *city_info_t) void {
    scan(&globals.user_map, cityp.loc);
    display.display_loc_u(cityp.loc);

    while (true) {
        terminal.prompt("What do you want the city at {d} to produce? ", .{terminal.loc_disp(@intCast(cityp.loc))});

        const i = get_piece_name();

        if (i == NOPIECE) {
            terminal.@"error"("I don't know how to build those.", .{});
        } else {
            cityp.prod = @intCast(i);
            cityp.work = -@divTrunc(@as(i64, data.piece_attr[@intCast(i)].build_time), 5);
            return;
        }
    }
}

pub fn get_piece_name() i32 {
    const ch = terminal.get_chx();

    for (0..NUM_OBJECTS) |i| {
        if (data.piece_attr[i].sname == ch) {
            return @intCast(i);
        }
    }
    return NOPIECE;
}

// ── Rebuild helpers (for save/restore) ──────────────────────────────────

pub fn rebuild_loc_chains() void {
    // Clear all obj_head
    for (0..MAP_SIZE) |i| {
        globals.map[i].obj_head = NO_PIECE;
    }
    // Clear all loc_next
    for (0..LIST_SIZE) |i| {
        globals.pool[i].loc_next = NO_PIECE;
    }
    // Build chains from alive pieces
    for (0..LIST_SIZE) |i| {
        if (globals.pool[i].alive) {
            loc_link(globals.pool[i].loc, @intCast(i));
        }
    }
}

pub fn refresh_view_maps() void {
    for (0..MAP_SIZE) |i| {
        if (globals.user_map[i].seen > 0) {
            update(&globals.user_map, @intCast(i));
        }
        if (globals.comp_map[i].seen > 0) {
            update(&globals.comp_map, @intCast(i));
        }
    }
}

pub fn rebuild_free_stack() void {
    globals.free_count = 0;
    for (0..LIST_SIZE) |i| {
        if (!globals.pool[i].alive) {
            globals.free_stack[globals.free_count] = @intCast(i);
            globals.free_count += 1;
        }
    }
}

pub fn rebuild_cargo() void {
    // Clear all cargo arrays and counts
    for (0..LIST_SIZE) |i| {
        globals.pool[i].cargo = [_]PieceIdx{NO_PIECE} ** types.MAX_CARGO;
        // Note: don't clear count here - we need it for validation
    }

    // Build cargo arrays from ship references
    for (0..LIST_SIZE) |i| {
        if (globals.pool[i].alive and globals.pool[i].ship != NO_PIECE) {
            const ship = &globals.pool[globals.pool[i].ship];
            // Find first empty cargo slot
            for (0..types.MAX_CARGO) |ci| {
                if (ship.cargo[ci] == NO_PIECE) {
                    ship.cargo[ci] = @intCast(i);
                    break;
                }
            }
        }
    }
}

pub fn rebuild_embark() void {
    // Clear ship references and cargo
    for (0..LIST_SIZE) |i| {
        globals.pool[i].ship = NO_PIECE;
        globals.pool[i].cargo = [_]PieceIdx{NO_PIECE} ** types.MAX_CARGO;
    }

    // Re-embark based on count fields (same logic as old read_embark)
    for (0..LIST_SIZE) |ship_i| {
        const ship = &globals.pool[ship_i];
        if (!ship.alive) continue;
        if (ship.type != TRANSPORT and ship.type != CARRIER) continue;

        const cargo_type: i32 = if (ship.type == TRANSPORT) ARMY else FIGHTER;
        var remaining = ship.count;
        ship.count = 0;

        if (remaining <= 0) continue;

        // Find matching pieces at the same location
        var idx = globals.map[@intCast(ship.loc)].obj_head;
        while (idx != NO_PIECE and remaining > 0) {
            const p = &globals.pool[idx];
            idx = p.loc_next;
            if (p.ship == NO_PIECE and p.type == cargo_type and p.alive) {
                embark(ship, p);
                remaining -= 1;
            }
        }
    }
}
