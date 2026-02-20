const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const terminal = @import("terminal.zig");
const math = @import("math.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("string.h");
});

const piece_info_t = types.piece_info_t;
const city_info_t = types.city_info_t;
const view_map_t = types.view_map_t;
const link_t = types.link_t;

const STRSIZE = globals.STRSIZE;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const NUM_CITY = globals.NUM_CITY;
const MAP_SIZE = globals.MAP_SIZE;
const INFINITY = 10000000;

const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);
const UNOWNED = @intFromEnum(globals.Ownership.Unowned);
const NOPIECE: c_int = @intFromEnum(globals.PieceType.NoPiece);
const ARMY = @intFromEnum(globals.PieceType.Army);
const FIGHTER = @intFromEnum(globals.PieceType.Fighter);
const TRANSPORT = @intFromEnum(globals.PieceType.Transport);
const CARRIER = @intFromEnum(globals.PieceType.Carrier);
const SATELLITE = @intFromEnum(globals.PieceType.Satellite);
const NOFUNC = @as(c_long, @intFromEnum(globals.Function.NoFunc));

const MOVE_NW = @as(c_long, @intFromEnum(globals.Function.Move_NW));
const MOVE_NE = @as(c_long, @intFromEnum(globals.Function.Move_NE));
const MOVE_SW = @as(c_long, @intFromEnum(globals.Function.Move_SW));
const MOVE_SE = @as(c_long, @intFromEnum(globals.Function.Move_SE));
const MOVE_N = @as(c_long, @intFromEnum(globals.Function.Move_N));

const MAP_CITY = data.MAP_CITY;

// ncurses
extern fn refresh() c_int;

// display.c
extern fn display_locx(whose: c_int, vmap: [*c]view_map_t, loc: c_long) void;

const sat_dir = [4]c_long{ MOVE_NW, MOVE_SW, MOVE_NE, MOVE_SE };
pub export var city_char: [3]u8 = .{ MAP_CITY, 'O', 'X' };

fn funci(x: c_long) usize {
    return @intCast(-x - 1);
}

fn moveDir(a: c_long) usize {
    return @intCast(-a + MOVE_N);
}

fn ownerMap(owner: c_int) [*c]view_map_t {
    return if (owner == USER) &globals.user_map else &globals.comp_map;
}

fn ownerList(owner: c_int) *[NUM_OBJECTS][*c]piece_info_t {
    return if (owner == USER) &globals.user_obj else &globals.comp_obj;
}

// Linked list operations (LINK/UNLINK macros from C)

const LinkField = enum { piece_link, loc_link, cargo_link };

fn getLink(obj: *piece_info_t, comptime field: LinkField) *link_t {
    return switch (field) {
        .piece_link => &obj.piece_link,
        .loc_link => &obj.loc_link,
        .cargo_link => &obj.cargo_link,
    };
}

fn link(head: *[*c]piece_info_t, obj: *piece_info_t, comptime field: LinkField) void {
    const lnk = getLink(obj, field);
    lnk.prev = null;
    lnk.next = @ptrCast(head.*);
    if (head.* != null) {
        const h: *piece_info_t = @ptrCast(head.*);
        getLink(h, field).prev = obj;
    }
    head.* = obj;
}

fn unlink(head: *[*c]piece_info_t, obj: *piece_info_t, comptime field: LinkField) void {
    const lnk = getLink(obj, field);
    if (lnk.next) |next| {
        getLink(next, field).prev = lnk.prev;
    }
    if (lnk.prev) |prev| {
        getLink(prev, field).next = lnk.next;
    } else {
        head.* = @ptrCast(lnk.next);
    }
    lnk.next = null;
    lnk.prev = null;
}

// Public API

pub export fn find_nearest_city(loc: c_long, owner: c_int, city_loc: [*c]c_long) c_int {
    var best_loc: c_long = loc;
    var best_dist: c_long = INFINITY;

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

pub export fn find_city(loc: c_long) [*c]city_info_t {
    return globals.map[@intCast(loc)].cityp;
}

pub export fn obj_moves(obj: [*c]piece_info_t) c_int {
    const t: usize = @intCast(obj.*.type);
    return @divTrunc(@as(c_int, data.piece_attr[t].speed) * obj.*.hits +
        @as(c_int, data.piece_attr[t].max_hits) - 1, @as(c_int, data.piece_attr[t].max_hits));
}

pub export fn obj_capacity(obj: [*c]piece_info_t) c_int {
    const t: usize = @intCast(obj.*.type);
    return @divTrunc(@as(c_int, data.piece_attr[t].capacity) * obj.*.hits +
        @as(c_int, data.piece_attr[t].max_hits) - 1, @as(c_int, data.piece_attr[t].max_hits));
}

pub fn moves(obj: *piece_info_t) c_int {
    return obj_moves(obj);
}

pub fn capacity(obj: *piece_info_t) c_int {
    return obj_capacity(obj);
}

pub export fn find_obj(@"type": c_int, loc: c_long) [*c]piece_info_t {
    var p: [*c]piece_info_t = globals.map[@intCast(loc)].objp;
    while (p != null) : (p = @ptrCast(p.*.loc_link.next)) {
        if (p.*.type == @"type") return p;
    }
    return null;
}

pub export fn find_nfull(@"type": c_int, loc: c_long) [*c]piece_info_t {
    var p: [*c]piece_info_t = globals.map[@intCast(loc)].objp;
    while (p != null) : (p = @ptrCast(p.*.loc_link.next)) {
        if (p.*.type == @"type") {
            if (obj_capacity(p) > p.*.count) return p;
        }
    }
    return null;
}

pub export fn find_transport(owner: c_int, loc: c_long) c_long {
    for (0..8) |i| {
        const new_loc = loc + data.dir_offset[i];
        const t = find_nfull(TRANSPORT, new_loc);
        if (t != null and t.*.owner == owner) return new_loc;
    }
    return loc;
}

pub export fn find_obj_at_loc(loc: c_long) [*c]piece_info_t {
    var best: [*c]piece_info_t = globals.map[@intCast(loc)].objp;
    if (best == null) return null;

    var p: [*c]piece_info_t = @ptrCast(best.*.loc_link.next);
    while (p != null) : (p = @ptrCast(p.*.loc_link.next)) {
        if (p.*.type > best.*.type and p.*.type != SATELLITE) best = p;
    }
    return best;
}

pub export fn disembark(obj: *piece_info_t) void {
    if (obj.ship != null) {
        const ship: *piece_info_t = @ptrCast(obj.ship);
        unlink(&ship.cargo, obj, .cargo_link);
        ship.count -= 1;
        obj.ship = null;
    }
}

pub export fn embark(ship: *piece_info_t, obj: *piece_info_t) void {
    obj.ship = ship;
    link(&ship.cargo, obj, .cargo_link);
    ship.count += 1;
}

pub export fn kill_obj(obj: [*c]piece_info_t, loc: c_long) void {
    const o: *piece_info_t = @ptrCast(obj);
    const vmap = ownerMap(o.owner);
    const list = ownerList(o.owner);

    while (o.cargo != null) {
        kill_one(list, @ptrCast(o.cargo));
    }

    kill_one(list, o);
    scan(vmap, loc);
}

fn kill_one(list: *[NUM_OBJECTS][*c]piece_info_t, obj: *piece_info_t) void {
    const t: usize = @intCast(obj.type);
    unlink(&list[t], obj, .piece_link);
    unlink(&globals.map[@intCast(obj.loc)].objp, obj, .loc_link);
    disembark(obj);

    link(&globals.free_list, obj, .piece_link);
    obj.hits = 0;
    obj.moved = data.piece_attr[t].speed;
}

pub export fn kill_city(cityp: [*c]city_info_t) void {
    var p: [*c]piece_info_t = globals.map[@intCast(cityp.*.loc)].objp;
    while (p != null) {
        const next_p: [*c]piece_info_t = @ptrCast(p.*.loc_link.next);

        if (p.*.type == ARMY) {
            kill_obj(p, cityp.*.loc);
        } else if (p.*.type != SATELLITE) {
            if (p.*.type == TRANSPORT) {
                const tlist = ownerList(p.*.owner);
                while (p.*.cargo != null) {
                    kill_one(tlist, @ptrCast(p.*.cargo));
                }
            }
            const list1 = ownerList(p.*.owner);
            const t: usize = @intCast(p.*.type);
            unlink(&list1[t], @ptrCast(p), .piece_link);
            p.*.owner = if (p.*.owner == USER) COMP else USER;
            const list2 = ownerList(p.*.owner);
            link(&list2[t], @ptrCast(p), .piece_link);

            p.*.func = NOFUNC;
        }

        p = next_p;
    }

    if (cityp.*.owner != UNOWNED) {
        const vmap = ownerMap(@intCast(cityp.*.owner));
        cityp.*.owner = UNOWNED;
        cityp.*.work = 0;
        cityp.*.prod = @intCast(NOPIECE);

        for (0..NUM_OBJECTS) |i| {
            cityp.*.func[i] = NOFUNC;
        }

        scan(vmap, cityp.*.loc);
    }
}

pub export fn produce(cityp: [*c]city_info_t) void {
    const list = ownerList(@intCast(cityp.*.owner));
    const prod: usize = @intCast(cityp.*.prod);

    cityp.*.work -= data.piece_attr[prod].build_time;

    std.debug.assert(globals.free_list != null);
    const new_piece: *piece_info_t = @ptrCast(globals.free_list);
    unlink(&globals.free_list, new_piece, .piece_link);
    link(&list[prod], new_piece, .piece_link);
    link(&globals.map[@intCast(cityp.*.loc)].objp, new_piece, .loc_link);
    new_piece.cargo_link.next = null;
    new_piece.cargo_link.prev = null;

    new_piece.loc = cityp.*.loc;
    new_piece.func = NOFUNC;
    new_piece.hits = data.piece_attr[prod].max_hits;
    new_piece.owner = @intCast(cityp.*.owner);
    new_piece.type = cityp.*.prod;
    new_piece.moved = 0;
    new_piece.cargo = null;
    new_piece.ship = null;
    new_piece.count = 0;
    new_piece.range = @truncate(data.piece_attr[prod].range);

    if (new_piece.type == SATELLITE) {
        new_piece.func = sat_dir[@intCast(math.irand(4))];
    }
}

pub export fn move_obj(obj: [*c]piece_info_t, new_loc: c_long) void {
    const o: *piece_info_t = @ptrCast(obj);
    std.debug.assert(o.hits > 0);
    const vmap = ownerMap(o.owner);

    const old_loc = o.loc;
    o.moved += 1;
    o.loc = new_loc;
    o.range -= 1;

    disembark(o);

    unlink(&globals.map[@intCast(old_loc)].objp, o, .loc_link);
    link(&globals.map[@intCast(new_loc)].objp, o, .loc_link);

    // move any objects contained in object
    var p: [*c]piece_info_t = o.cargo;
    while (p != null) : (p = @ptrCast(p.*.cargo_link.next)) {
        p.*.loc = new_loc;
        unlink(&globals.map[@intCast(old_loc)].objp, @ptrCast(p), .loc_link);
        link(&globals.map[@intCast(new_loc)].objp, @ptrCast(p), .loc_link);
    }

    // board new ship
    switch (o.type) {
        FIGHTER => {
            if (globals.map[@intCast(o.loc)].cityp == null) {
                const carrier = find_nfull(CARRIER, o.loc);
                if (carrier != null) embark(@ptrCast(carrier), o);
            }
        },
        ARMY => {
            const transport = find_nfull(TRANSPORT, o.loc);
            if (transport != null) embark(@ptrCast(transport), o);
        },
        else => {},
    }

    if (o.type == SATELLITE) scan_sat(vmap, o.loc);
    scan(vmap, o.loc);
}

fn bounce(loc: c_long, dir1: c_long, dir2: c_long, dir3: c_long) c_long {
    var new_loc = loc + data.dir_offset[moveDir(dir1)];
    if (globals.map[@intCast(new_loc)].on_board) return dir1;

    new_loc = loc + data.dir_offset[moveDir(dir2)];
    if (globals.map[@intCast(new_loc)].on_board) return dir2;

    return dir3;
}

fn move_sat1(obj: *piece_info_t) void {
    var dir = moveDir(obj.func);
    var new_loc = obj.loc + data.dir_offset[dir];

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
        new_loc = obj.loc + data.dir_offset[dir];
    }
    move_obj(obj, new_loc);
}

pub export fn move_sat(obj: [*c]piece_info_t) void {
    const o: *piece_info_t = @ptrCast(obj);
    o.moved = 0;

    while (o.moved < obj_moves(obj)) {
        move_sat1(o);
        if (o.range == 0) {
            if (o.owner == USER)
                terminal.comment("Satellite at %d crashed and burned.", terminal.loc_disp(@intCast(o.loc)));
            terminal.ksend("Satellite at %d crashed and burned.", terminal.loc_disp(@intCast(o.loc)));
            kill_obj(obj, o.loc);
            return;
        }
    }
}

pub export fn good_loc(obj: [*c]piece_info_t, loc: c_long) bool {
    const uloc: usize = @intCast(loc);
    if (!globals.map[uloc].on_board) return false;

    const vmap = ownerMap(obj.*.owner);
    const t: usize = @intCast(obj.*.type);
    const terrain = &data.piece_attr[t].terrain;
    const contents = vmap[@intCast(loc)].contents;

    // check if terrain matches
    for (terrain) |ch| {
        if (ch == 0) break;
        if (ch == contents) return true;
    }

    // armies can move into unfull transports
    if (obj.*.type == ARMY) {
        const p = find_nfull(TRANSPORT, loc);
        return (p != null and p.*.owner == obj.*.owner);
    }

    // ships and fighters can move into cities
    if (globals.map[uloc].cityp != null and globals.map[uloc].cityp.*.owner == @as(u8, @intCast(obj.*.owner)))
        return true;

    // fighters can move onto unfull carriers
    if (obj.*.type == FIGHTER) {
        const p = find_nfull(CARRIER, loc);
        return (p != null and p.*.owner == obj.*.owner);
    }

    return false;
}

pub export fn describe_obj(obj: [*c]piece_info_t) void {
    var func_buf: [STRSIZE]u8 = undefined;
    var other: [STRSIZE]u8 = undefined;

    if (obj.*.func >= 0) {
        _ = c.snprintf(&func_buf, STRSIZE, "%d", terminal.loc_disp(@intCast(obj.*.func)));
    } else {
        _ = c.snprintf(&func_buf, STRSIZE, "%s", data.func_name[funci(obj.*.func)]);
    }

    other[0] = 0;

    const t = obj.*.type;
    if (t == FIGHTER) {
        _ = c.snprintf(&other, STRSIZE, "; range = %d", @as(c_int, obj.*.range));
    } else if (t == TRANSPORT) {
        _ = c.snprintf(&other, STRSIZE, "; armies = %d", @as(c_int, obj.*.count));
    } else if (t == CARRIER) {
        _ = c.snprintf(&other, STRSIZE, "; fighters = %d", @as(c_int, obj.*.count));
    }

    const ti: usize = @intCast(t);
    terminal.prompt(
        "%s at %d:  moves = %d; hits = %d; func = %s%s",
        @as([*c]const u8, &data.piece_attr[ti].name),
        terminal.loc_disp(@intCast(obj.*.loc)),
        obj_moves(obj) - obj.*.moved,
        @as(c_int, obj.*.hits),
        @as([*c]const u8, &func_buf),
        @as([*c]const u8, &other),
    );
}

pub export fn scan(vmap: [*c]view_map_t, loc: c_long) void {
    std.debug.assert(globals.map[@intCast(loc)].on_board);

    for (0..8) |i| {
        const xloc = loc + data.dir_offset[i];
        update(vmap, xloc);
    }
    update(vmap, loc);
}

fn scan_sat(vmap: [*c]view_map_t, loc: c_long) void {
    std.debug.assert(globals.map[@intCast(loc)].on_board);

    for (0..8) |i| {
        const xloc = loc + 2 * data.dir_offset[i];
        if (xloc >= 0 and xloc < MAP_SIZE and globals.map[@intCast(xloc)].on_board)
            scan(vmap, xloc);
    }
    scan(vmap, loc);
}

fn update(vmap: [*c]view_map_t, loc: c_long) void {
    const uloc: usize = @intCast(loc);
    vmap[uloc].seen = globals.date;

    if (globals.map[uloc].cityp != null) {
        vmap[uloc].contents = city_char[globals.map[uloc].cityp.*.owner];
    } else {
        const p = find_obj_at_loc(loc);
        if (p == null) {
            vmap[uloc].contents = globals.map[uloc].contents;
        } else if (p.*.owner == USER) {
            vmap[uloc].contents = data.piece_attr[@intCast(p.*.type)].sname;
        } else {
            vmap[uloc].contents = data.piece_attr[@intCast(p.*.type)].sname | 0x20;
        }
    }

    if (vmap == @as([*c]view_map_t, &globals.comp_map))
        display_locx(COMP, &globals.comp_map, loc)
    else if (vmap == @as([*c]view_map_t, &globals.user_map))
        display_locx(USER, &globals.user_map, loc);
}

pub export fn set_prod(cityp: [*c]city_info_t) void {
    scan(&globals.user_map, cityp.*.loc);
    display.display_loc_u(cityp.*.loc);

    while (true) {
        terminal.prompt("What do you want the city at %d to produce? ",
            terminal.loc_disp(@intCast(cityp.*.loc)));

        const i = get_piece_name();

        if (i == NOPIECE) {
            terminal.@"error"("I don't know how to build those.");
        } else {
            cityp.*.prod = @intCast(i);
            cityp.*.work = -@divTrunc(@as(c_long, data.piece_attr[@intCast(i)].build_time), 5);
            return;
        }
    }
}

pub export fn get_piece_name() c_int {
    const ch = terminal.get_chx();

    for (0..NUM_OBJECTS) |i| {
        if (data.piece_attr[i].sname == ch) {
            return @intCast(i);
        }
    }
    return NOPIECE;
}
