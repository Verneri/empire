const std = @import("std");

const globals = @import("globals.zig");
const types = @import("types.zig");
const display = @import("display.zig");
const math = @import("math.zig");
const game = @import("game.zig");
const user = @import("user.zig");
const computer = @import("computer.zig");
const terminal = @import("terminal.zig");
const data = @import("data.zig");
const edit = @import("edit.zig");
const util = @import("util.zig");
const object = @import("object.zig");
const attack = @import("attack.zig");
comptime {
    _ = &attack; // ensure attack exports are compiled for C callers
}

pub fn empire() void {
    var turn: u16 = 0;
    display.ttinit();
    math.rndini();
    display.clear_screen();
    display.pos_str(@as(c_int, 7), @as(c_int, 0), "EMPIRE, Version 5.00 site Amdahl 1-Apr-1988");
    display.pos_str(@as(c_int, 8), @as(c_int, 0), "Detailed directions are in EMPIRE.DOC\n");
    display.redisplay();
    game.restore() catch {
        game.init();
    };
    while (true) {
        if (globals.automove) {
            user.move();
            computer.move(1);
            turn += 1;
            if (turn % globals.save_interval == 0) {
                game.save();
            }
        } else {
            terminal.prompt("");
            display.redisplay();
            terminal.prompt("Your orders? ");
            const order = terminal.get_chx();
            do_command(order);
        }
    }
}

fn do_command(orders: u8) void {
    switch (orders) {
        'A' => {
            globals.automove = true;
            terminal.error_msg("Now in Auto-Mode");
            user.move();
            computer.move(1);
            game.save();
        },
        'C' => {
            c_give();
        },
        'D' => {
            terminal.fmt_error("Round #%d", .{globals.date});
        },
        'E' => {
            if (globals.resigned) {
                c_examine();
            } else {
                terminal.huh();
            }
        },
        'F' => {
            c_map();
        },
        'G' => {
            computer.move(1);
        },
        'H' => {
            terminal.help(data.help_cmd, data.cmd_lines);
        },
        'J' => {
            var ncycle = display.cur_sector();
            if (ncycle == -1) ncycle = 0;
            edit.edit(util.sector_loc(ncycle));
        },
        'M' => {
            user.move();
            computer.move(1);
            game.save();
        },
        'N' => {
            const ncycle = @as(u8, @intCast(terminal.getint("Number of free enemy moves: ")));
            computer.move(ncycle);
            game.save();
        },
        'P' => {
            c_sector();
        },
        22, 'Q' => {
            c_quit();
        },
        'R' => {
            display.clear_screen();
            game.restore() catch {};
        },
        'S' => {
            game.save();
        },
        'T' => {
            globals.save_movie = !globals.save_movie;
            if (globals.save_movie) {
                terminal.comment("Saving movie screens to 'empmovie.dat'.");
            } else {
                terminal.comment("No longer saving movie screens.");
            }
        },
        'W' => {
            if (globals.resigned or globals.debug) {
                game.replay_movie();
            } else {
                terminal.error_msg("You cannot watch movie until computer resigns.");
            }
        },
        'Z' => {
            display.print_zoom(&globals.user_map);
        },
        12 => {
            display.redraw();
        },
        '+' => {
            const e = terminal.get_chx();

            switch (e) {
                '+' => globals.debug = true,
                '-' => globals.debug = false,
                else => terminal.huh(),
            }
        },

        else => {
            if (globals.debug) {
                c_debug(orders);
            } else {
                terminal.huh();
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
            const e = terminal.get_chx();
            switch (e) {
                '+' => globals.trace_pmap = true,
                '-' => globals.trace_pmap = false,
                else => terminal.huh(),
            }
        },
        '$' => {
            const e = terminal.get_chx();
            switch (e) {
                '+' => globals.print_debug = true,
                '-' => globals.print_debug = false,
                else => terminal.huh(),
            }
        },
        '&' => {
            globals.print_vmap = terminal.get_chx();
        },
        else => {
            terminal.huh();
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
        terminal.error_msg("There are no unowned cities.");
        terminal.ksend("There are no unowned cities.");
        return;
    }
    const i: usize = @intCast(math.irand(@intCast(count)));
    const given_i = unowned[i];
    globals.city[given_i].owner = @intFromEnum(globals.Ownership.Comp);
    globals.city[given_i].prod = @intFromEnum(globals.PieceType.NoPiece);
    globals.city[given_i].work = 0;
    object.scan(&globals.comp_map, globals.city[given_i].loc);
}

fn c_quit() void {
    if (terminal.getyn("QUIT - Are you sure? ")) {
        util.empend();
    }
}

fn c_sector() void {
    const num = terminal.get_range("Sector number? ", 0, globals.NUM_SECTORS - 1);
    display.print_sector_u(num);
}

fn c_map() void {
    terminal.prompt("Filename? ");
    var jnkbuf: [globals.STRSIZE]u8 = undefined;
    terminal.get_str(jnkbuf[0..], globals.STRSIZE);
    var idx: usize = 0;
    while (jnkbuf[idx] != 0) : (idx += 1) {}
    var f = std.fs.cwd().createFile(jnkbuf[0..idx], .{}) catch {
        terminal.error_msg("I can't open that file.");
        return;
    };
    defer f.close();
    var line: [globals.MAP_HEIGHT + 2]u8 = undefined;
    for (0..globals.MAP_WIDTH) |i| {
        var j = globals.MAP_HEIGHT - 1;
        while (j >= 0) : (j -= 1) {
            line[@intCast(globals.MAP_HEIGHT - 1 - j)] = globals.user_map[@intCast(util.row_col_loc(@intCast(j), @intCast(i)))].contents;
        }
        j = globals.MAP_HEIGHT - 1;
        while (j >= 0 and line[@intCast(j)] == ' ') : (j -= 1) {}
        line[@intCast(j + 1)] = '\n';
        line[@intCast(j + 2)] = 0;
        f.writeAll(line[0..@intCast(j + 2)]) catch {
            terminal.error_msg("Write failed.");
        };
    }
}

fn c_examine() void {
    const num = terminal.get_range("Sector number? ", 0, globals.NUM_SECTORS - 1);
    display.print_sector_c(num);
}

fn c_movie() void {
    while (true) {
        computer.move(1);
        display.print_zoom(&globals.comp_map);
        game.save();
    }
}
