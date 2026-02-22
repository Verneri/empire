const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const terminal = @import("terminal.zig");
const object = @import("object.zig");
const util = @import("util.zig");
const vx = @import("vx.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("string.h");
});

const STRSIZE = globals.STRSIZE;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const NUM_SECTORS = globals.NUM_SECTORS;
const USER = @intFromEnum(globals.Ownership.User);
const NOPIECE: c_int = @intFromEnum(globals.PieceType.NoPiece);
const ARMY = @intFromEnum(globals.PieceType.Army);
const FIGHTER = @intFromEnum(globals.PieceType.Fighter);
const DESTROYER = @intFromEnum(globals.PieceType.Destroyer);
const TRANSPORT = @intFromEnum(globals.PieceType.Transport);
const CARRIER = @intFromEnum(globals.PieceType.Carrier);
const SATELLITE = @intFromEnum(globals.PieceType.Satellite);
const NOFUNC = @as(c_long, @intFromEnum(globals.Function.NoFunc));
const RANDOM = @as(c_long, @intFromEnum(globals.Function.Random));
const SENTRY = @as(c_long, @intFromEnum(globals.Function.Sentry));
const FILL = @as(c_long, @intFromEnum(globals.Function.Fill));
const LAND = @as(c_long, @intFromEnum(globals.Function.Land));
const EXPLORE = @as(c_long, @intFromEnum(globals.Function.Explore));
const ARMYATTACK = @as(c_long, @intFromEnum(globals.Function.ArmyAttack));
const WFTRANSPORT = @as(c_long, @intFromEnum(globals.Function.WFTransport));
const REPAIR = @as(c_long, @intFromEnum(globals.Function.Repair));
const MOVE_N = @as(c_long, @intFromEnum(globals.Function.Move_N));

fn funci(x: c_long) usize {
    return @intCast(-x - 1);
}

pub fn edit(edit_cursor_init: c_long) void {
    var edit_cursor = edit_cursor_init;
    var path_start: c_long = -1;
    var path_type: c_int = NOPIECE;

    terminal.comment("Edit mode...");

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

fn e_cursor(edit_cursor: *c_long) u8 {
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
    terminal.comment("Exiting edit mode.");
}

fn e_print(edit_cursor: *c_long) void {
    const sector = terminal.get_range("New Sector? ", 0, NUM_SECTORS - 1);
    edit_cursor.* = util.sector_loc(sector);
    display.sector_change();
}

fn e_set_func(loc: c_long, func: c_long) void {
    const obj = object.find_obj_at_loc(loc);
    if (obj != null and obj.*.owner == USER) {
        obj.*.func = func;
        return;
    }
    terminal.huh();
}

fn e_set_city_func(cityp: [*c]types.city_info_t, piece_type: c_int, func: c_long) void {
    cityp.*.func[@intCast(piece_type)] = func;
}

fn e_random(loc: c_long) void {
    e_set_func(loc, RANDOM);
}

pub fn e_city_random(cityp: [*c]types.city_info_t, piece_type: c_int) void {
    e_set_city_func(cityp, piece_type, RANDOM);
}

fn e_fill(loc: c_long) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (contents == 'T' or contents == 'C') {
        e_set_func(loc, FILL);
    } else {
        terminal.huh();
    }
}

pub fn e_city_fill(cityp: [*c]types.city_info_t, piece_type: c_int) void {
    if (piece_type == TRANSPORT or piece_type == CARRIER) {
        e_set_city_func(cityp, piece_type, FILL);
    } else {
        terminal.huh();
    }
}

fn e_explore(loc: c_long) void {
    e_set_func(loc, EXPLORE);
}

pub fn e_city_explore(cityp: [*c]types.city_info_t, piece_type: c_int) void {
    e_set_city_func(cityp, piece_type, EXPLORE);
}

fn e_land(loc: c_long) void {
    if (globals.user_map[@intCast(loc)].contents == 'F') {
        e_set_func(loc, LAND);
    } else {
        terminal.huh();
    }
}

fn e_transport(loc: c_long) void {
    if (globals.user_map[@intCast(loc)].contents == 'A') {
        e_set_func(loc, WFTRANSPORT);
    } else {
        terminal.huh();
    }
}

fn e_attack(loc: c_long) void {
    if (globals.user_map[@intCast(loc)].contents == 'A') {
        e_set_func(loc, ARMYATTACK);
    } else {
        terminal.huh();
    }
}

pub fn e_city_attack(cityp: [*c]types.city_info_t, piece_type: c_int) void {
    if (piece_type == ARMY) {
        e_set_city_func(cityp, piece_type, ARMYATTACK);
    } else {
        terminal.huh();
    }
}

fn e_repair(loc: c_long) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (contents == 'P' or contents == 'D' or contents == 'S' or contents == 'T' or contents == 'B' or contents == 'C') {
        e_set_func(loc, REPAIR);
    } else {
        terminal.huh();
    }
}

pub fn e_city_repair(cityp: [*c]types.city_info_t, piece_type: c_int) void {
    if (piece_type == ARMY or piece_type == FIGHTER or piece_type == SATELLITE) {
        terminal.huh();
    } else {
        e_set_city_func(cityp, piece_type, REPAIR);
    }
}

const dirs = "WEDCXZAQ";

fn e_stasis(loc: c_long) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (!std.ascii.isUpper(contents)) {
        terminal.huh();
    } else if (contents == 'X') {
        terminal.huh();
    } else {
        const e = terminal.get_chx();
        if (std.mem.indexOfScalar(u8, dirs, e)) |i| {
            e_set_func(loc, MOVE_N - @as(c_long, @intCast(i)));
        } else {
            terminal.huh();
        }
    }
}

pub fn e_city_stasis(cityp: [*c]types.city_info_t, piece_type: c_int) void {
    const e = terminal.get_chx();
    if (std.mem.indexOfScalar(u8, dirs, e)) |i| {
        e_set_city_func(cityp, piece_type, MOVE_N - @as(c_long, @intCast(i)));
    } else {
        terminal.huh();
    }
}

fn e_wake(loc: c_long) void {
    const uloc: usize = @intCast(loc);
    const cityp = object.find_city(loc);
    if (cityp != null) {
        for (0..NUM_OBJECTS) |i| {
            cityp.*.func[i] = NOFUNC;
        }
    }
    var obj: [*c]types.piece_info_t = globals.map[uloc].objp;
    while (obj != null) : (obj = @ptrCast(obj.*.loc_link.next)) {
        obj.*.func = NOFUNC;
    }
}

pub fn e_city_wake(cityp: [*c]types.city_info_t, piece_type: c_int) void {
    e_set_city_func(cityp, piece_type, NOFUNC);
}

fn e_city_func(path_start: *c_long, loc: c_long, path_type: *c_int) void {
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

fn e_move(path_start: *c_long, loc: c_long) void {
    const contents = globals.user_map[@intCast(loc)].contents;
    if (!std.ascii.isUpper(contents)) {
        terminal.huh();
    } else if (contents == 'X') {
        terminal.huh();
    } else {
        path_start.* = loc;
    }
}

fn e_end(path_start: *c_long, loc: c_long, path_type: c_int) void {
    if (path_start.* == -1) {
        terminal.huh();
    } else if (path_type == NOPIECE) {
        e_set_func(path_start.*, loc);
    } else {
        const cityp = object.find_city(path_start.*);
        std.debug.assert(cityp != null);
        e_set_city_func(cityp, path_type, loc);
    }
    path_start.* = -1;
}

fn e_sleep(loc: c_long) void {
    if (globals.user_map[@intCast(loc)].contents == 'O') {
        terminal.huh();
    } else {
        e_set_func(loc, SENTRY);
    }
}

fn e_info(edit_cursor: c_long) void {
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

fn e_piece_info(edit_cursor: c_long, ab: u8) void {
    const upper = std.ascii.toUpper(ab);
    if (std.mem.indexOfScalar(u8, &data.type_chars, upper)) |piece_type| {
        const obj = object.find_obj(@intCast(piece_type), edit_cursor);
        std.debug.assert(obj != null);
        object.describe_obj(obj);
    }
}

fn e_city_info(edit_cursor: c_long) void {
    terminal.@"error"("");

    var f: c_int = 0;
    var obj: [*c]types.piece_info_t = globals.map[@intCast(edit_cursor)].objp;
    while (obj != null) : (obj = @ptrCast(obj.*.loc_link.next)) {
        if (obj.*.type == FIGHTER) f += 1;
    }

    var s: c_int = 0;
    obj = globals.map[@intCast(edit_cursor)].objp;
    while (obj != null) : (obj = @ptrCast(obj.*.loc_link.next)) {
        if (obj.*.type >= DESTROYER) s += 1;
    }

    if (f == 1 and s == 1) {
        _ = c.snprintf(&globals.jnkbuf, STRSIZE, "1 fighter landed, 1 ship docked");
    } else if (f == 1) {
        _ = c.snprintf(&globals.jnkbuf, STRSIZE, "1 fighter landed, %d ships docked", s);
    } else if (s == 1) {
        _ = c.snprintf(&globals.jnkbuf, STRSIZE, "%d fighters landed, 1 ship docked", f);
    } else {
        _ = c.snprintf(&globals.jnkbuf, STRSIZE, "%d fighters landed, %d ships docked", f, s);
    }

    const cityp = object.find_city(edit_cursor);
    std.debug.assert(cityp != null);

    var func_buf: [STRSIZE]u8 = undefined;
    var temp_buf: [STRSIZE]u8 = undefined;
    var junk_buf2: [STRSIZE]u8 = undefined;
    func_buf[0] = 0;

    for (0..NUM_OBJECTS) |si| {
        if (cityp.*.func[si] < 0) {
            _ = c.snprintf(&temp_buf, STRSIZE, "%c:%s; ", @as(c_int, data.piece_attr[si].sname), data.func_name[funci(cityp.*.func[si])]);
        } else {
            _ = c.snprintf(&temp_buf, STRSIZE, "%c: %d;", @as(c_int, data.piece_attr[si].sname), terminal.loc_disp(@intCast(cityp.*.func[si])));
        }
        _ = c.strcat(&func_buf, &temp_buf);
    }

    const prod: usize = @intCast(cityp.*.prod);
    _ = c.snprintf(
        &junk_buf2,
        STRSIZE,
        "City at location %d will complete %s on round %ld",
        terminal.loc_disp(@intCast(cityp.*.loc)),
        @as([*c]const u8, &data.piece_attr[prod].article),
        globals.date + @as(c_long, data.piece_attr[prod].build_time) - cityp.*.work,
    );

    terminal.info(&junk_buf2, &globals.jnkbuf, &func_buf);
}

fn e_prod(loc: c_long) void {
    const cityp = object.find_city(loc);
    if (cityp == null) {
        terminal.huh();
    } else {
        object.set_prod(cityp);
    }
}

fn e_help() void {
    terminal.help(&data.help_edit, data.edit_lines);
    terminal.prompt("Press any key to continue: ");
    _ = terminal.get_chx();
}
