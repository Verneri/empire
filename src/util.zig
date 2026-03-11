const globals = @import("globals.zig");
const types = @import("types.zig");
const std = @import("std");

const display = @import("display.zig");

pub fn empend() void {
    display.close_disp();
    std.c.exit(0);
}

pub fn assert(expression: [*:0]const u8, file: [*:0]const u8, line: i32) void {
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

const Piece = types.Piece;
const PieceIdx = types.PieceIdx;
const NO_PIECE = types.NO_PIECE;

pub fn check() void {
    var in_loc = [_]bool{false} ** LIST_SIZE;
    var in_cargo = [_]bool{false} ** LIST_SIZE;

    // Verify all alive pieces are reachable via loc chains
    for (0..MAP_SIZE) |ui| {
        const i: i64 = @intCast(ui);
        if (globals.map[ui].cityp) |cp| {
            std.debug.assert(cp.loc == i);
        }

        var idx = globals.map[ui].obj_head;
        while (idx != NO_PIECE) {
            const p = &globals.pool[idx];
            std.debug.assert(p.alive);
            std.debug.assert(p.loc == i);
            std.debug.assert(p.hits > 0);
            std.debug.assert(p.owner == USER or p.owner == COMP);
            std.debug.assert(!in_loc[idx]);
            in_loc[idx] = true;
            idx = p.loc_next;
        }
    }

    // Make sure all cities are on map
    for (0..NUM_CITY) |i| {
        const loc: usize = @intCast(globals.city[i].loc);
        std.debug.assert(globals.map[loc].cityp == &globals.city[i]);
    }

    // Verify cargo: for each piece with a ship, check consistency
    for (0..LIST_SIZE) |i| {
        const p = &globals.pool[i];
        if (!p.alive) continue;

        // Verify piece is in loc chain
        std.debug.assert(in_loc[i]);

        // Check cargo array consistency for ships
        if (p.type == TRANSPORT or p.type == CARRIER) {
            var count: i16 = 0;
            for (0..types.MAX_CARGO) |ci| {
                const cargo_idx = p.cargo[ci];
                if (cargo_idx == NO_PIECE) continue;
                count += 1;
                const cargo = &globals.pool[cargo_idx];
                std.debug.assert(cargo.alive);
                std.debug.assert(cargo.ship == @as(PieceIdx, @intCast(i)));
                std.debug.assert(cargo.loc == p.loc);
                std.debug.assert(!in_cargo[cargo_idx]);
                in_cargo[cargo_idx] = true;
            }
            std.debug.assert(count == p.count);
        }

        // If piece has a ship, verify it's in that ship's cargo
        if (p.ship != NO_PIECE) {
            std.debug.assert(in_cargo[i]);
        }
    }

    // Verify free stack: no alive pieces in free stack
    for (0..globals.free_count) |i| {
        const idx = globals.free_stack[i];
        std.debug.assert(!globals.pool[idx].alive);
    }
}

// Location helpers

pub inline fn row_col_loc(row: i32, col: i32) i64 {
    return @intCast(row * globals.MAP_WIDTH + col);
}

pub inline fn sector_row(sector: i32) i32 {
    return @rem(sector, globals.SECTOR_ROWS);
}

pub inline fn sector_col(sector: i32) i32 {
    return @divFloor(sector, globals.SECTOR_ROWS);
}

pub inline fn sector_loc(sector: i32) i64 {
    return row_col_loc(
        sector_row(sector) * globals.ROWS_PER_SECTOR + @divTrunc(globals.ROWS_PER_SECTOR, 2),
        sector_col(sector) * globals.COLS_PER_SECTOR + @divTrunc(globals.COLS_PER_SECTOR, 2),
    );
}

pub inline fn loc_row(loc: i64) i32 {
    return @intCast(@divTrunc(loc, globals.MAP_WIDTH));
}

pub inline fn loc_col(loc: i64) i32 {
    return @intCast(@rem(loc, globals.MAP_WIDTH));
}

pub inline fn row_col_sector(row: i32, col: i32) i32 {
    return col * globals.SECTOR_ROWS + row;
}

pub inline fn loc_sector(loc: i64) i32 {
    return row_col_sector(
        @divTrunc(loc_row(loc), globals.ROWS_PER_SECTOR),
        @divTrunc(loc_col(loc), globals.COLS_PER_SECTOR),
    );
}
