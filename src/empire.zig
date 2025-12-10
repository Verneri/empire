const std = @import("std");

const globals = @import("globals.zig");
const types = @import("types.zig");

pub fn empire() void {
    var turn: u16 = 0;
    ttinit();
    rndini();
    clear_screen();
    pos_str(@as(c_int, 7), @as(c_int, 0), "EMPIRE, Version 5.00 site Amdahl 1-Apr-1988");
    pos_str(@as(c_int, 8), @as(c_int, 0), "Detailed directions are in EMPIRE.DOC\n");
    redisplay();
    if (!(restore_game() != 0)) {
        init_game();
    }
    while (true) {
        if (globals.automove) {
            user_move();
            comp_move(@as(c_int, 1));
            turn += 1;
            if (turn % globals.save_interval == 0) {
                save_game();
            }
        } else {
            prompt("");
            redisplay();
            prompt("Your orders? ");
            const order = get_chx();
            do_command(order);
        }
    }
}

fn do_command(orders: u8) void {
    switch (orders) {
        'A' => {
            globals.automove = true;
            @"error"("Now in Auto-Mode");
            user_move();
            comp_move(@as(c_int, 1));
            save_game();
        },
        'C' => {
            c_give();
        },
        'D' => {
            @"error"("Round #%d", globals.date);
        },
        'E' => {
            if (globals.resigned) {
                c_examine();
            } else {
                huh();
            }
        },
        'F' => {
            c_map();
        },
        'G' => {
            comp_move(@as(c_int, 1));
        },
        'H' => {
            help(help_cmd, cmd_lines);
        },
        'J' => {
            var ncycle = cur_sector();
            if (ncycle == -1) ncycle = 0;
            edit(sector_loc(ncycle));
        },
        'M' => {
            user_move();
            comp_move(1);
            save_game();
        },
        'N' => {
            const ncycle = getint("Number of free enemy moves: ");
            comp_move(ncycle);
            save_game();
        },
        'P' => {
            c_sector();
        },
        22, 'Q' => {
            c_quit();
        },
        'R' => {
            clear_screen();
            _ = restore_game();
        },
        'S' => {
            save_game();
        },
        'T' => {
            globals.save_movie = !globals.save_movie;
            if (globals.save_movie) {
                comment("Saving movie screens to 'empmovie.dat'.");
            } else {
                comment("No longer saving movie screens.");
            }
        },
        'W' => {
            if (globals.resigned or globals.debug) {
                replay_movie();
            } else {
                @"error"("You cannot watch movie until computer resigns.");
            }
        },
        'Z' => {
            print_zoom(&globals.user_map);
        },
        12 => {
            redraw();
        },
        '+' => {
            const e = get_chx();

            switch (e) {
                '+' => globals.debug = true,
                '-' => globals.debug = false,
                else => huh(),
            }
        },

        else => {
            if (globals.debug) {
                c_debug(orders);
            } else {
                huh();
            }
        },
    }
}

fn c_debug(orders: u8) void {
    switch (orders) {
        '#' => {
            c_examine();
        },
        '%' => {
            c_movie();
        },
        '@' => {
            const e = get_chx();
            switch (e) {
                '+' => globals.trace_pmap = true,
                '-' => globals.trace_pmap = false,
                else => huh(),
            }
        },
        '$' => {
            const e = get_chx();
            switch (e) {
                '+' => globals.print_debug = true,
                '-' => globals.print_debug = false,
                else => huh(),
            }
        },
        '&' => {
            globals.print_vmap = get_chx();
        },
        else => {
            huh();
        },
    }
}

fn c_give() void {
    var unowned: [globals.NUM_CITY]usize = undefined;
    var count: usize = 0;
    for (&globals.city, 0..) |*city, i| {
        if (city.owner == @intFromEnum(globals.Ownership.Unowned)) {
            unowned[count] = i;
            count += 1;
        }
    }
    if (count == 0) {
        @"error"("There are no unowned cities.");
        ksend("There are no unowned cities.");
        return;
    }
    const i: usize = @intCast(irand(@intCast(count)));
    const given_i = unowned[i];
    globals.city[given_i].owner = @intFromEnum(globals.Ownership.Comp);
    globals.city[given_i].prod = @intFromEnum(globals.PieceType.NoPiece);
    globals.city[given_i].work = 0;
    scan(&globals.comp_map, globals.city[given_i].loc);
}

fn c_quit() void {
    if (getyn("QUIT - Are you sure? ")) {
        empend();
    }
}

fn c_sector() void {
    const num = get_range("Sector number? ", 0, globals.NUM_SECTORS - 1);
    print_sector_u(num);
}

fn c_map() void {
    prompt("Filename? ");
    var jnkbuf: [globals.STRSIZE]u8 = undefined;
    get_str(jnkbuf[0..], globals.STRSIZE);
    var idx: usize = 0;
    while (jnkbuf[idx] != 0) : (idx += 1) {}
    var f = std.fs.cwd().createFile(jnkbuf[0..idx], .{}) catch {
        @"error"("I can't open that file.");
        return;
    };
    defer f.close();
    var line: [globals.MAP_HEIGHT + 2]u8 = undefined;
    for (0..globals.MAP_WIDTH) |i| {
        var j = globals.MAP_HEIGHT - 1;
        while (j >= 0) : (j -= 1) {
            line[@intCast(globals.MAP_HEIGHT - 1 - j)] = globals.user_map[@intCast(row_col_loc(@intCast(j), @intCast(i)))].contents;
        }
        j = globals.MAP_HEIGHT - 1;
        while (j >= 0 and line[@intCast(j)] == ' ') : (j -= 1) {}
        line[@intCast(j + 1)] = '\n';
        line[@intCast(j + 2)] = 0;
        f.writeAll(line[0..@intCast(j + 2)]) catch {
            @"error"("Write failed.");
        };
    }
}

pub extern fn c_examine() void;
pub extern fn c_movie() void;

pub extern fn ttinit() void;
pub extern fn rndini() void;

pub extern fn clear_screen() void;

pub extern fn pos_str(row: c_int, col: c_int, str: [*c]const u8, ...) void;

pub extern fn redisplay() void;

pub extern fn restore_game() c_int;

pub extern fn init_game() void;

pub extern fn save_game() void;

pub extern fn user_move() void;

pub extern fn comp_move(nmoves: c_int) void;

pub extern fn prompt(fmt: [*c]const u8, ...) void;

pub extern fn get_chx() u8;

pub extern fn @"error"(fmt: [*c]const u8, ...) void;

pub extern fn huh() void;
pub extern fn help(text: [*c][*c]u8, nlines: c_int) void;

pub const help_cmd: [*c][*c]u8 = @extern([*c][*c]u8, .{
    .name = "help_cmd",
});

pub extern var cmd_lines: c_int;
pub extern fn cur_sector() c_int;
pub extern fn edit(edit_cursor: c_long) void;

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

pub extern fn getint(message: [*c]const u8) c_int;
pub extern fn comment(fmt: [*c]const u8, ...) void;
pub extern fn ksend(fmt: [*c]const u8, ...) void;

pub extern fn replay_movie() void;

pub extern fn print_zoom(vmap: [*c]types.view_map_t) void;
pub extern fn redraw() void;

pub extern fn irand(high: c_long) c_long;
pub extern fn scan(vmap: [*c]types.view_map_t, loc: c_long) void;
pub extern fn getyn(message: [*c]const u8) bool;

pub extern fn empend() void;
pub extern fn get_range(message: [*c]const u8, low: c_int, high: c_int) c_int;

pub inline fn print_sector_u(sector: c_int) void {
    print_sector(@intFromEnum(globals.Ownership.User), &globals.user_map, sector);
}

pub inline fn print_sector_c(sector: c_int) void {
    print_sector(@intFromEnum(globals.Ownership.Comp), &globals.comp_map, sector);
}
pub extern fn print_sector(whose: c_int, vmap: [*c]types.view_map_t, sector: c_int) void;
pub extern fn get_str(buf: [*c]u8, sizep: c_int) void;
