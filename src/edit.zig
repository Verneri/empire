const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const terminal = @import("terminal.zig");
const object = @import("object.zig");
const util = @import("util.zig");
const vx = @import("vx.zig");

const STRSIZE = globals.STRSIZE;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const NUM_SECTORS = globals.NUM_SECTORS;
const USER = @intFromEnum(globals.Ownership.User);
const NOPIECE: i32 = @intFromEnum(globals.PieceType.NoPiece);
const ARMY = @intFromEnum(globals.PieceType.Army);
const FIGHTER = @intFromEnum(globals.PieceType.Fighter);
const DESTROYER = @intFromEnum(globals.PieceType.Destroyer);
const TRANSPORT = @intFromEnum(globals.PieceType.Transport);
const CARRIER = @intFromEnum(globals.PieceType.Carrier);
const SATELLITE = @intFromEnum(globals.PieceType.Satellite);
const NOFUNC = @as(i64, @intFromEnum(globals.Function.NoFunc));
const RANDOM = @as(i64, @intFromEnum(globals.Function.Random));
const SENTRY = @as(i64, @intFromEnum(globals.Function.Sentry));
const FILL = @as(i64, @intFromEnum(globals.Function.Fill));
const LAND = @as(i64, @intFromEnum(globals.Function.Land));
const EXPLORE = @as(i64, @intFromEnum(globals.Function.Explore));
const ARMYATTACK = @as(i64, @intFromEnum(globals.Function.ArmyAttack));
const WFTRANSPORT = @as(i64, @intFromEnum(globals.Function.WFTransport));
const REPAIR = @as(i64, @intFromEnum(globals.Function.Repair));
const MOVE_N = @as(i64, @intFromEnum(globals.Function.Move_N));

fn funci(x: i64) usize {
    return @intCast(-x - 1);
}

pub fn edit(edit_cursor_init: i64) void {
    var edit_cursor = edit_cursor_init;
    var path_start: i64 = -1;
    var path_type: i32 = NOPIECE;

    terminal.comment("Edit mode...", .{});

    while (true) {
        display.display_loc_u(edit_cursor);
        const e = e_cursor(&edit_cursor);

        switch (e) {
            'B' => e_prod(edit_cursor),
            'F' => e_fill(edit_cursor),
            'G' => e_explore(edit_cursor),
            'H' => e_help(),
            'I' => e_stasis(edit_cursor),
            'K' => e_wake(edit_cursor),
            'L' => e_land(edit_cursor),
            'M' => {
                path_type = NOPIECE;
                e_move(&path_start, edit_cursor);
            },
            'N' => e_end(&path_start, edit_cursor, path_type),
            'O' => {
                e_leave();
                return;
            },
            'P' => e_print(&edit_cursor),
            'R' => e_random(edit_cursor),
            'S' => e_sleep(edit_cursor),
            'T' => e_transport(edit_cursor),
            'U' => e_repair(edit_cursor),
            'V' => e_city_func(&path_start, edit_cursor, &path_type),
            'Y' => e_attack(edit_cursor),
            '?' => e_info(edit_cursor),
            12 => display.redraw(), // control-L
            else => terminal.huh(),
        }
    }
}

fn e_cursor(edit_cursor: *i64) u8 {
    vx.render();
    var e: u21 = vx.getch();
    terminal.topini();

    while (true) {
        const p = display.direction(e);
        if (p == -1) break;

        if (!display.move_cursor(edit_cursor, data.dir_offset[@intCast(p)])) {
            vx.beep();
        }

        vx.render();
        e = vx.getch();
    }
    const ch: u8 = @truncate(e);
    return std.ascii.toUpper(ch);
}

fn e_leave() void {
    terminal.comment("Exiting edit mode.", .{});
}

fn e_print(edit_cursor: *i64) void {
    const sector = terminal.get_range("New Sector? ", 0, NUM_SECTORS - 1);
    edit_cursor.* = util.sector_loc(sector);
    display.sector_change();
}

pub fn e_set_func(loc: i64, func: i64) void {
    if (object.find_obj_at_loc(loc)) |obj| {
        if (obj.owner == USER) {
            obj.func = func;
            return;
        }
    }
    terminal.huh();
}

pub fn e_set_city_func(cityp: *types.city_info_t, piece_type: i32, func: i64) void {
    cityp.*.func[@intCast(piece_type)] = func;
}

pub fn e_random(loc: i64) void {
    e_set_func(loc, RANDOM);
}

pub fn e_city_random(cityp: *types.city_info_t, piece_type: i32) void {
    e_set_city_func(cityp, piece_type, RANDOM);
}

pub fn e_fill(loc: i64) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (contents == 'T' or contents == 'C') {
        e_set_func(loc, FILL);
    } else {
        terminal.huh();
    }
}

pub fn e_city_fill(cityp: *types.city_info_t, piece_type: i32) void {
    if (piece_type == TRANSPORT or piece_type == CARRIER) {
        e_set_city_func(cityp, piece_type, FILL);
    } else {
        terminal.huh();
    }
}

pub fn e_explore(loc: i64) void {
    e_set_func(loc, EXPLORE);
}

pub fn e_city_explore(cityp: *types.city_info_t, piece_type: i32) void {
    e_set_city_func(cityp, piece_type, EXPLORE);
}

pub fn e_land(loc: i64) void {
    if (globals.user_map[@intCast(loc)].contents == 'F') {
        e_set_func(loc, LAND);
    } else {
        terminal.huh();
    }
}

pub fn e_transport(loc: i64) void {
    if (globals.user_map[@intCast(loc)].contents == 'A') {
        e_set_func(loc, WFTRANSPORT);
    } else {
        terminal.huh();
    }
}

pub fn e_attack(loc: i64) void {
    if (globals.user_map[@intCast(loc)].contents == 'A') {
        e_set_func(loc, ARMYATTACK);
    } else {
        terminal.huh();
    }
}

pub fn e_city_attack(cityp: *types.city_info_t, piece_type: i32) void {
    if (piece_type == ARMY) {
        e_set_city_func(cityp, piece_type, ARMYATTACK);
    } else {
        terminal.huh();
    }
}

pub fn e_repair(loc: i64) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (contents == 'P' or contents == 'D' or contents == 'S' or contents == 'T' or contents == 'B' or contents == 'C') {
        e_set_func(loc, REPAIR);
    } else {
        terminal.huh();
    }
}

pub fn e_city_repair(cityp: *types.city_info_t, piece_type: i32) void {
    if (piece_type == ARMY or piece_type == FIGHTER or piece_type == SATELLITE) {
        terminal.huh();
    } else {
        e_set_city_func(cityp, piece_type, REPAIR);
    }
}

const dirs = "WEDCXZAQ";

fn e_stasis(loc: i64) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (!std.ascii.isUpper(contents)) {
        terminal.huh();
    } else if (contents == 'X') {
        terminal.huh();
    } else {
        const e = terminal.get_chx();
        if (std.mem.indexOfScalar(u8, dirs, e)) |i| {
            e_set_func(loc, MOVE_N - @as(i64, @intCast(i)));
        } else {
            terminal.huh();
        }
    }
}

pub fn e_city_stasis(cityp: *types.city_info_t, piece_type: i32) void {
    const e = terminal.get_chx();
    if (std.mem.indexOfScalar(u8, dirs, e)) |i| {
        e_set_city_func(cityp, piece_type, MOVE_N - @as(i64, @intCast(i)));
    } else {
        terminal.huh();
    }
}

pub fn e_wake(loc: i64) void {
    const uloc: usize = @intCast(loc);
    const maybe_cityp = object.find_city(loc);
    if (maybe_cityp) |cityp| {
        for (0..NUM_OBJECTS) |i| {
            cityp.*.func[i] = NOFUNC;
        }
    }
    var idx = globals.map[uloc].obj_head;
    while (idx != types.NO_PIECE) {
        const p = &globals.pool[idx];
        p.func = NOFUNC;
        idx = p.loc_next;
    }
}

pub fn e_city_wake(cityp: *types.city_info_t, piece_type: i32) void {
    e_set_city_func(cityp, piece_type, NOFUNC);
}

fn e_city_func(path_start: *i64, loc: i64, path_type: *i32) void {
    const cityp = object.find_city(loc);
    if (cityp == null or cityp.*.owner != USER) {
        terminal.huh();
        return;
    }

    const piece_type = object.get_piece_name();
    if (piece_type == NOPIECE) {
        terminal.huh();
        return;
    }

    const e = terminal.get_chx();

    switch (e) {
        'F' => e_city_fill(cityp, piece_type),
        'G' => e_city_explore(cityp, piece_type),
        'I' => e_city_stasis(cityp, piece_type),
        'K' => e_city_wake(cityp, piece_type),
        'M' => {
            path_type.* = piece_type;
            e_move(path_start, loc);
        },
        'R' => e_city_random(cityp, piece_type),
        'U' => e_city_repair(cityp, piece_type),
        'Y' => e_city_attack(cityp, piece_type),
        else => terminal.huh(),
    }
}

pub fn e_move(path_start: *i64, loc: i64) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (!std.ascii.isUpper(contents)) {
        terminal.huh();
    } else if (contents == 'X') {
        terminal.huh();
    } else {
        path_start.* = loc;
    }
}

pub fn e_end(path_start: *i64, loc: i64, path_type: i32) void {
    if (path_start.* == -1) {
        terminal.huh();
    } else if (path_type == NOPIECE) {
        e_set_func(path_start.*, loc);
    } else {
        const cityp = object.find_city(path_start.*);
        e_set_city_func(cityp.?, path_type, loc);
    }
    path_start.* = -1;
}

pub fn e_sleep(loc: i64) void {
    if (globals.user_map[@intCast(loc)].contents == 'O') {
        terminal.huh();
    } else {
        e_set_func(loc, SENTRY);
    }
}

pub fn e_info(edit_cursor: i64) void {
    const ab = globals.user_map[@intCast(edit_cursor)].contents;

    if (ab == 'O') {
        e_city_info(edit_cursor);
    } else if (ab == 'X' and globals.debug) {
        e_city_info(edit_cursor);
    } else if (ab >= 'A' and ab <= 'T') {
        e_piece_info(edit_cursor, ab);
    } else if (ab >= 'a' and ab <= 't' and globals.debug) {
        e_piece_info(edit_cursor, ab);
    } else {
        terminal.huh();
    }
}

fn e_piece_info(edit_cursor: i64, ab: u8) void {
    const upper = std.ascii.toUpper(ab);
    if (std.mem.indexOfScalar(u8, &data.type_chars, upper)) |piece_type| {
        const obj = object.find_obj(@intCast(piece_type), edit_cursor).?;
        object.describe_obj(obj);
    }
}

fn e_city_info(edit_cursor: i64) void {
    terminal.@"error"("", .{});

    const uloc2: usize = @intCast(edit_cursor);
    var f: i32 = 0;
    var s: i32 = 0;
    var idx2 = globals.map[uloc2].obj_head;
    while (idx2 != types.NO_PIECE) {
        const p = &globals.pool[idx2];
        if (p.type == FIGHTER) f += 1;
        if (p.type >= DESTROYER) s += 1;
        idx2 = p.loc_next;
    }

    const dock_msg = if (f == 1 and s == 1)
        std.fmt.bufPrintZ(&globals.jnkbuf, "1 fighter landed, 1 ship docked", .{}) catch unreachable
    else if (f == 1)
        std.fmt.bufPrintZ(&globals.jnkbuf, "1 fighter landed, {d} ships docked", .{s}) catch unreachable
    else if (s == 1)
        std.fmt.bufPrintZ(&globals.jnkbuf, "{d} fighters landed, 1 ship docked", .{f}) catch unreachable
    else
        std.fmt.bufPrintZ(&globals.jnkbuf, "{d} fighters landed, {d} ships docked", .{ f, s }) catch unreachable;

    const maybe_cityp = object.find_city(edit_cursor);
    const cityp = maybe_cityp.?;

    var func_buf: [STRSIZE]u8 = undefined;
    var junk_buf2: [STRSIZE]u8 = undefined;
    var func_pos: usize = 0;

    for (0..NUM_OBJECTS) |si| {
        if (cityp.*.func[si] < 0) {
            const fname = std.mem.sliceTo(data.func_name[funci(cityp.*.func[si])], 0);
            const written = std.fmt.bufPrint(func_buf[func_pos..], "{c}:{s}; ", .{ data.piece_attr[si].sname, fname }) catch break;
            func_pos += written.len;
        } else {
            const written = std.fmt.bufPrint(func_buf[func_pos..], "{c}: {d};", .{ data.piece_attr[si].sname, terminal.loc_disp(@intCast(cityp.*.func[si])) }) catch break;
            func_pos += written.len;
        }
    }
    if (func_pos < func_buf.len) func_buf[func_pos] = 0;

    const prod: usize = @intCast(cityp.*.prod);
    const article = std.mem.sliceTo(&data.piece_attr[prod].article, 0);
    const completion_round = globals.date + @as(i64, data.piece_attr[prod].build_time) - cityp.*.work;
    const prod_msg = std.fmt.bufPrintZ(&junk_buf2, "City at location {d} will complete {s} on round {d}", .{
        terminal.loc_disp(@intCast(cityp.*.loc)),
        article,
        completion_round,
    }) catch unreachable;

    terminal.info(prod_msg.ptr, dock_msg.ptr, @ptrCast(@as([*]u8, &func_buf)));
}

fn e_prod(loc: i64) void {
    const cityp = object.find_city(loc);
    if (cityp == null) {
        terminal.huh();
    } else {
        object.set_prod(cityp);
    }
}

fn e_help() void {
    terminal.help(&data.help_edit, data.edit_lines);
    terminal.prompt("Press any key to continue: ", .{});
    _ = terminal.get_chx();
}
