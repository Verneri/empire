const globals = @import("globals.zig");
const types = @import("types.zig");
const std = @import("std");

const display = @import("display.zig");

pub fn empend() void {
    display.close_disp();
    std.c.exit(0);
}

pub fn assert(expression: [*c]const u8, file: [*c]const u8, line: c_int) void {
    display.close_disp();
    std.debug.print("assert failed: file {s} line {d}: {s}\n", .{ file, line, expression });
    std.posix.raise(std.posix.SIG.SEGV) catch {};
}

// Database consistency check

const LIST_SIZE = globals.LIST_SIZE;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const MAP_SIZE = globals.MAP_SIZE;
const NUM_CITY = globals.NUM_CITY;
const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);
const TRANSPORT = @intFromEnum(globals.PieceType.Transport);
const CARRIER = @intFromEnum(globals.PieceType.Carrier);
const ARMY = @intFromEnum(globals.PieceType.Army);
const FIGHTER = @intFromEnum(globals.PieceType.Fighter);

const Ptr = [*c]types.piece_info_t;

fn objIndex(p: Ptr) usize {
    return (@intFromPtr(p) - @intFromPtr(&globals.object)) / @sizeOf(types.piece_info_t);
}

pub fn check() void {
    var in_free = [_]bool{false} ** LIST_SIZE;
    var in_obj = [_]bool{false} ** LIST_SIZE;
    var in_loc = [_]bool{false} ** LIST_SIZE;
    var in_cargo = [_]bool{false} ** LIST_SIZE;

    // Mark all objects in free list
    var p: Ptr = globals.free_list;
    while (p != null) : (p = ptrOrNull(p.*.piece_link.next)) {
        const i = objIndex(p);
        std.debug.assert(!in_free[i]);
        in_free[i] = true;
        std.debug.assert(p.*.hits == 0);
        if (p.*.piece_link.prev) |prev| {
            std.debug.assert(prev.piece_link.next == @as(?*types.piece_info_t, @ptrCast(p)));
        }
    }

    // Mark all objects in the map
    for (0..MAP_SIZE) |ui| {
        const i: c_long = @intCast(ui);
        if (globals.map[ui].cityp != null) {
            std.debug.assert(globals.map[ui].cityp.*.loc == i);
        }

        var q: Ptr = globals.map[ui].objp;
        while (q != null) : (q = ptrOrNull(q.*.loc_link.next)) {
            std.debug.assert(q.*.loc == i);
            std.debug.assert(q.*.hits > 0);
            std.debug.assert(q.*.owner == USER or q.*.owner == COMP);

            const j = objIndex(q);
            std.debug.assert(!in_loc[j]);
            in_loc[j] = true;

            if (q.*.loc_link.prev) |prev| {
                std.debug.assert(prev.loc_link.next == @as(?*types.piece_info_t, @ptrCast(q)));
            }
        }
    }

    // Make sure all cities are on map
    for (0..NUM_CITY) |i| {
        const loc: usize = @intCast(globals.city[i].loc);
        std.debug.assert(globals.map[loc].cityp == &globals.city[i]);
    }

    // Scan object lists
    check_obj(&globals.comp_obj, COMP, &in_obj);
    check_obj(&globals.user_obj, USER, &in_obj);

    // Scan cargo lists
    check_cargo(globals.comp_obj[TRANSPORT], ARMY, &in_cargo);
    check_cargo(globals.user_obj[TRANSPORT], ARMY, &in_cargo);
    check_cargo(globals.comp_obj[CARRIER], FIGHTER, &in_cargo);
    check_cargo(globals.user_obj[CARRIER], FIGHTER, &in_cargo);

    // Make sure all objects with ship pointers are in cargo
    check_obj_cargo(&globals.comp_obj, &in_cargo);
    check_obj_cargo(&globals.user_obj, &in_cargo);

    // Make sure every object is either free or in loc and obj list
    for (0..LIST_SIZE) |i| {
        std.debug.assert(in_free[i] != (in_loc[i] and in_obj[i]));
    }
}

fn check_obj(list: *const [NUM_OBJECTS]Ptr, owner: c_int, in_obj: *[LIST_SIZE]bool) void {
    for (0..NUM_OBJECTS) |i| {
        var p: Ptr = list[i];
        while (p != null) : (p = ptrOrNull(p.*.piece_link.next)) {
            std.debug.assert(p.*.owner == owner);
            std.debug.assert(p.*.type == @as(c_int, @intCast(i)));
            std.debug.assert(p.*.hits > 0);

            const j = objIndex(p);
            std.debug.assert(!in_obj[j]);
            in_obj[j] = true;

            if (p.*.piece_link.prev) |prev| {
                std.debug.assert(prev.piece_link.next == @as(?*types.piece_info_t, @ptrCast(p)));
            }
        }
    }
}

fn check_cargo(list: Ptr, cargo_type: c_int, in_cargo: *[LIST_SIZE]bool) void {
    var p: Ptr = list;
    while (p != null) : (p = ptrOrNull(p.*.piece_link.next)) {
        var count: c_short = 0;
        var q: Ptr = p.*.cargo;
        while (q != null) : (q = ptrOrNull(q.*.cargo_link.next)) {
            count += 1;
            std.debug.assert(q.*.type == cargo_type);
            std.debug.assert(q.*.owner == p.*.owner);
            std.debug.assert(q.*.hits > 0);
            std.debug.assert(q.*.ship == @as(Ptr, @ptrCast(p)));
            std.debug.assert(q.*.loc == p.*.loc);

            const j = objIndex(q);
            std.debug.assert(!in_cargo[j]);
            in_cargo[j] = true;

            if (q.*.cargo_link.prev) |prev| {
                std.debug.assert(prev.cargo_link.next == @as(?*types.piece_info_t, @ptrCast(q)));
            }
        }
        std.debug.assert(count == p.*.count);
    }
}

fn check_obj_cargo(list: *const [NUM_OBJECTS]Ptr, in_cargo: *const [LIST_SIZE]bool) void {
    for (0..NUM_OBJECTS) |i| {
        var p: Ptr = list[i];
        while (p != null) : (p = ptrOrNull(p.*.piece_link.next)) {
            if (p.*.ship != null) {
                std.debug.assert(in_cargo[objIndex(p)]);
            }
        }
    }
}

fn ptrOrNull(opt: ?*types.piece_info_t) Ptr {
    return @ptrCast(opt);
}

// Location helpers

pub inline fn row_col_loc(row: c_int, col: c_int) c_long {
    return @intCast(row * globals.MAP_WIDTH + col);
}

pub inline fn sector_row(sector: c_int) c_int {
    return std.zig.c_translation.signedRemainder(sector, globals.SECTOR_ROWS);
}

pub inline fn sector_col(sector: c_int) c_int {
    return @divFloor(sector, globals.SECTOR_ROWS);
}

pub inline fn sector_loc(sector: c_int) c_long {
    return row_col_loc(sector_row(sector) * globals.ROWS_PER_SECTOR + globals.ROWS_PER_SECTOR / 2, sector_col(sector) * globals.COLS_PER_SECTOR + globals.COLS_PER_SECTOR / 2);
}

pub inline fn loc_row(loc: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.div(loc, globals.MAP_WIDTH)) {
    _ = &loc;
    return @import("std").zig.c_translation.MacroArithmetic.div(loc, globals.MAP_WIDTH);
}
pub inline fn loc_col(loc: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.rem(loc, globals.MAP_WIDTH)) {
    _ = &loc;
    return @import("std").zig.c_translation.MacroArithmetic.rem(loc, globals.MAP_WIDTH);
}
pub inline fn row_col_sector(row: anytype, col: anytype) c_int {
    return std.zig.c_translation.cast(c_int, (col * globals.SECTOR_ROWS) + row);
}
pub inline fn loc_sector(loc: anytype) c_int {
    return row_col_sector(std.zig.c_translation.MacroArithmetic.div(loc_row(loc), globals.ROWS_PER_SECTOR), std.zig.c_translation.MacroArithmetic.div(loc_col(loc), globals.COLS_PER_SECTOR));
}
