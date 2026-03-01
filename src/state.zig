const std = @import("std");

const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const terminal = @import("terminal.zig");
const object = @import("object.zig");
const util = @import("util.zig");
const game = @import("game.zig");
const user = @import("user.zig");
const computer = @import("computer.zig");
const edit = @import("edit.zig");
const math = @import("math.zig");
const attack = @import("attack.zig");
const vx = @import("vx.zig");

const piece_info_t = types.piece_info_t;
const city_info_t = types.city_info_t;

const STRSIZE = globals.STRSIZE;
const NUM_OBJECTS = globals.NUM_OBJECTS;
const NUM_SECTORS = globals.NUM_SECTORS;
const NOPIECE: c_int = @intFromEnum(globals.PieceType.NoPiece);
const USER = @intFromEnum(globals.Ownership.User);

// ── Frame union ─────────────────────────────────────────────────────────

pub const Frame = union(enum) {
    idle,
    user_move: UserMoveCtx,
    piece_move: PieceMoveCtx,
    ask_user: AskUserCtx,
    yes_no: YesNoCtx,
    set_prod: SetProdCtx,
    edit_mode: EditCtx,
    get_range: GetRangeCtx,
    get_str: GetStrCtx,
    help_screen,
    debug_input: DebugInputCtx,
    delay: DelayCtx,
};

// ── Context structs ─────────────────────────────────────────────────────

pub const UserMoveCtx = struct {
    sector_idx: usize,
    obj_type_idx: usize,
    cur_obj: ?*piece_info_t,
    phase: enum { pre_produce, satellites, iterating, post },
    start: usize,
    city_idx: usize,
    cur_satellite: ?*piece_info_t,
    automove_loop: bool,
};

pub const PieceMoveCtx = struct {
    obj: *piece_info_t,
    changed_location: bool,
    need_input: bool,
};

pub const AskUserCtx = struct {
    obj: *piece_info_t,
    sub: AskUserSub = .command,

    const AskUserSub = union(enum) {
        command,
        awaiting_direction, // 'I' command: waiting for direction key
        awaiting_piece_name: struct { cityp: [*c]city_info_t }, // 'V' command step 1
        awaiting_city_func: struct { cityp: [*c]city_info_t, piece_t: c_int }, // 'V' step 2
        awaiting_city_stasis_dir: struct { cityp: [*c]city_info_t, piece_t: c_int }, // 'V' then 'I' step 3
    };
};

pub const YesNoAction = enum {
    quit,
    army_water,
    army_friendly,
    army_city,
    fighter_city,
    fighter_friendly,
    ship_city,
    ship_shore,
    ship_friendly,
    fatal_army_transport,
};

pub const YesNoCtx = struct {
    action: YesNoAction,
    obj: ?*piece_info_t,
    loc: c_long,
    response_msg: ?[*c]const u8,
    /// If true, N pops yes_no and stays in ask_user. If false, N finishes ask_user.
    stay_in_ask_on_no: bool,
};

pub const SetProdCtx = struct {
    cityp: [*c]city_info_t,
    caller: enum { user_move_production, user_build, edit_prod, city_attack },
};

pub const EditCtx = struct {
    edit_cursor: c_long,
    path_start: c_long,
    path_type: c_int,
    sub: EditSub = .input,

    const EditSub = union(enum) {
        input,
        awaiting_stasis_dir,
        awaiting_piece_name: struct { cityp: [*c]city_info_t },
        awaiting_city_func: struct { cityp: [*c]city_info_t, piece_t: c_int },
        awaiting_city_stasis_dir: struct { cityp: [*c]city_info_t, piece_t: c_int },
    };
};

pub const GetRangeCtx = struct {
    low: c_int,
    high: c_int,
    buf: [STRSIZE]u8 = std.mem.zeroes([STRSIZE]u8),
    len: usize = 0,
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    message: [*c]const u8,
    caller: GetRangeCaller,

    const GetRangeCaller = enum { sector, examine, edit_sector, free_moves };
};

pub const GetStrCtx = struct {
    buf: [STRSIZE]u8 = std.mem.zeroes([STRSIZE]u8),
    len: usize = 0,
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    caller: GetStrCaller,

    const GetStrCaller = enum { map_file };
};

pub const DebugInputCtx = struct {
    parent_cmd: u8,
};

pub const DelayCtx = struct {
    remaining_ms: c_int,
    last_tick: i128,
    cursor_col: c_int,
    cursor_row: c_int,
    next_star_ms: c_int, // countdown to next asterisk
};

// ── Stack ───────────────────────────────────────────────────────────────

const MAX_DEPTH = 12;

pub const Stack = struct {
    frames: [MAX_DEPTH]Frame = undefined,
    depth: usize = 0,

    pub fn push(self: *Stack, frame: Frame) void {
        std.debug.assert(self.depth < MAX_DEPTH);
        self.frames[self.depth] = frame;
        self.depth += 1;
    }

    pub fn pop(self: *Stack) void {
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
    }

    pub fn top(self: *Stack) *Frame {
        std.debug.assert(self.depth > 0);
        return &self.frames[self.depth - 1];
    }
};

// ── Global state ────────────────────────────────────────────────────────

pub var stack: Stack = .{};
var automove_turn: u16 = 0;

pub fn initState() void {
    stack = .{};
    stack.push(.idle);
}

// ── Key handling dispatch ───────────────────────────────────────────────

pub fn handleKey(key: vx.Key) void {
    if (key.codepoint == 'c' and key.mods.ctrl) {
        vx.deinit();
        std.c.exit(1);
    }

    const frame = stack.top();
    switch (frame.*) {
        .idle => handleIdleKey(key),
        .ask_user => handleAskUserKey(key),
        .yes_no => handleYesNoKey(key),
        .set_prod => handleSetProdKey(key),
        .edit_mode => handleEditKey(key),
        .get_range => handleGetRangeKey(key),
        .get_str => handleGetStrKey(key),
        .help_screen => handleHelpScreenPop(),
        .debug_input => handleDebugInputKey(key),
        .delay => {}, // ignore keys during delay
        .user_move, .piece_move => {}, // processing, ignore keys
    }
}

// ── Timer tick ──────────────────────────────────────────────────────────

pub fn tick() void {
    if (stack.depth == 0) return;
    const frame = stack.top();
    if (frame.* != .delay) return;

    const ctx = &frame.delay;
    const now = std.time.nanoTimestamp();
    const elapsed_ns = now - ctx.last_tick;
    ctx.last_tick = now;
    const elapsed_ms: c_int = @intCast(@min(@divTrunc(elapsed_ns, std.time.ns_per_ms), 100000));
    ctx.remaining_ms -= elapsed_ms;
    ctx.next_star_ms -= elapsed_ms;

    if (ctx.next_star_ms <= 0 and ctx.remaining_ms > 0) {
        vx.writeCell(@intCast(ctx.cursor_col), @intCast(ctx.cursor_row), '*', .{});
        ctx.cursor_col += 1;
        ctx.next_star_ms += 500;
    }

    if (ctx.remaining_ms <= 0) {
        stack.pop(); // pop delay
    }
}

pub fn isIdle() bool {
    if (stack.depth == 0) return true;
    return stack.top().* == .idle;
}

pub fn hasActiveTimer() bool {
    if (stack.depth == 0) return false;
    return stack.top().* == .delay;
}

fn pushDelay() void {
    const row: c_int = @intCast(vx.lines() - 1);
    stack.push(.{ .delay = .{
        .remaining_ms = globals.delay_time,
        .last_tick = std.time.nanoTimestamp(),
        .cursor_col = 0,
        .cursor_row = row,
        .next_star_ms = 500,
    } });
    terminal.clear_need_delay();
}

pub fn showIdlePrompt() void {
    if (display.cur_sector() == -1) {
        // No sector displayed — find a user city and show its sector
        var sector: c_int = 0;
        for (&globals.city) |*city| {
            if (city.owner == @intFromEnum(globals.Ownership.User)) {
                sector = util.loc_sector(city.loc);
                break;
            }
        }
        display.print_sector_u(sector);
    }
    terminal.prompt("");
    display.redisplay();
    terminal.prompt("Your orders? ");
}

// ── Idle key handler ────────────────────────────────────────────────────

fn handleIdleKey(key: vx.Key) void {
    const ch = upperKey(key);
    switch (ch) {
        'A' => {
            globals.automove = true;
            terminal.error_msg("Now in Auto-Mode");
            automove_turn = 0;
            startUserMove(true);
        },
        'C' => c_give(),
        'D' => terminal.fmt_error("Round #%d", .{globals.date}),
        'E' => {
            if (globals.resigned) {
                pushGetRange("Sector number? ", 0, NUM_SECTORS - 1, .examine);
            } else {
                terminal.huh();
            }
        },
        'F' => pushGetStr(.map_file),
        'G' => {
            computer.move(1);
            showIdlePrompt();
        },
        'H' => {
            terminal.help(&data.help_cmd, data.cmd_lines);
            stack.push(.help_screen);
        },
        'J' => {
            var ncycle = display.cur_sector();
            if (ncycle == -1) ncycle = 0;
            pushEditMode(util.sector_loc(ncycle));
        },
        'M' => startUserMove(false),
        'N' => pushGetRange("Number of free enemy moves: ", 0, 9999, .free_moves),
        'P' => pushGetRange("Sector number? ", 0, NUM_SECTORS - 1, .sector),
        22, 'Q' => {
            terminal.prompt("QUIT - Are you sure? ");
            stack.push(.{ .yes_no = .{
                .action = .quit,
                .obj = null,
                .loc = 0,
                .response_msg = null,
                .stay_in_ask_on_no = false,
            } });
        },
        'R' => {
            display.clear_screen();
            game.restore() catch {};
            showIdlePrompt();
        },
        'S' => game.save(),
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
        'Z' => display.print_zoom(&globals.user_map),
        12 => display.redraw(),
        '+' => stack.push(.{ .debug_input = .{ .parent_cmd = '+' } }),
        else => {
            if (globals.debug) {
                handleDebugCmd(ch);
            } else {
                terminal.huh();
            }
        },
    }
}

fn handleDebugCmd(ch: u8) void {
    switch (ch) {
        '#' => pushGetRange("Sector number? ", 0, NUM_SECTORS - 1, .examine),
        '%' => c_movie(),
        '@', '$', '&' => stack.push(.{ .debug_input = .{ .parent_cmd = ch } }),
        else => terminal.huh(),
    }
}

fn handleDebugInputKey(key: vx.Key) void {
    const parent = stack.top().debug_input.parent_cmd;
    const ch = upperKey(key);
    stack.pop();

    switch (parent) {
        '+' => switch (ch) {
            '+' => globals.debug = true,
            '-' => globals.debug = false,
            else => terminal.huh(),
        },
        '@' => switch (ch) {
            '+' => globals.trace_pmap = true,
            '-' => globals.trace_pmap = false,
            else => terminal.huh(),
        },
        '$' => switch (ch) {
            '+' => globals.print_debug = true,
            '-' => globals.print_debug = false,
            else => terminal.huh(),
        },
        '&' => globals.print_vmap = ch,
        else => terminal.huh(),
    }
}

fn handleHelpScreenPop() void {
    stack.pop();
    display.sector_change();
    // Re-show context depending on what's below
    if (stack.depth > 0) {
        const below = stack.top();
        switch (below.*) {
            .idle => showIdlePrompt(),
            .ask_user => redisplayAskUser(below.ask_user.obj),
            .edit_mode => display.display_loc_u(below.edit_mode.edit_cursor),
            else => {},
        }
    }
}

// ── User move flow ──────────────────────────────────────────────────────

fn startUserMove(automove_loop: bool) void {
    // Reset moved for units
    for (globals.user_obj) |obj| {
        var cur: ?*types.struct_piece_info = obj;
        while (cur != null) : (cur = cur.?.piece_link.next) {
            cur.?.moved = 0;
            object.scan(&globals.user_map, cur.?.loc);
        }
    }

    var sec_start = display.cur_sector();
    if (sec_start < 0) sec_start = 0;
    const start: usize = @intCast(sec_start);

    stack.push(.{ .user_move = .{
        .sector_idx = start,
        .obj_type_idx = 0,
        .cur_obj = null,
        .phase = .pre_produce,
        .start = start,
        .city_idx = 0,
        .cur_satellite = globals.user_obj[@intFromEnum(globals.PieceType.Satellite)],
        .automove_loop = automove_loop,
    } });
    advanceUserMove();
}

fn advanceUserMove() void {
    const ctx = &stack.top().user_move;

    switch (ctx.phase) {
        .pre_produce => {
            while (ctx.city_idx < globals.NUM_CITY) {
                const city = &globals.city[ctx.city_idx];
                if (user.owned_by(city, globals.Ownership.User)) {
                    object.scan(&globals.user_map, city.loc);
                    const prod = city.prod;
                    if (prod == @intFromEnum(globals.PieceType.NoPiece)) {
                        stack.push(.{ .set_prod = .{
                            .cityp = city,
                            .caller = .user_move_production,
                        } });
                        pushSetProdPrompt(city);
                        return; // wait for set_prod key
                    } else {
                        city.work += 1;
                        if (city.work >= data.piece_attr[prod].build_time) {
                            terminal.ksend("%s has been completed at city %d.\n", &data.piece_attr[prod].article, terminal.loc_disp(@as(c_int, @bitCast(@as(c_int, @truncate(city.loc))))));
                            terminal.comment("%s has been completed at city %d.\n", &data.piece_attr[prod].article, terminal.loc_disp(@as(c_int, @bitCast(@as(c_int, @truncate(city.loc))))));
                            object.produce(city);
                        }
                    }
                }
                ctx.city_idx += 1;
            }
            ctx.phase = .satellites;
            return advanceUserMove();
        },
        .satellites => {
            while (ctx.cur_satellite != null) {
                const sat = ctx.cur_satellite.?;
                ctx.cur_satellite = sat.piece_link.next;
                object.move_sat(sat);
            }
            ctx.phase = .iterating;
            ctx.sector_idx = ctx.start;
            ctx.obj_type_idx = 0;
            ctx.cur_obj = null;
            return advanceUserMove();
        },
        .iterating => {
            const end = ctx.start + globals.NUM_SECTORS;
            while (ctx.sector_idx < end) {
                const sec = @rem(ctx.sector_idx, globals.NUM_SECTORS);
                if (ctx.obj_type_idx == 0 and ctx.cur_obj == null) {
                    display.sector_change();
                }

                while (ctx.obj_type_idx < globals.NUM_OBJECTS) {
                    const j = data.move_order[ctx.obj_type_idx];
                    if (ctx.cur_obj == null) {
                        ctx.cur_obj = globals.user_obj[@as(usize, @intCast(j))];
                    }

                    while (ctx.cur_obj != null) {
                        const obj = ctx.cur_obj.?;
                        ctx.cur_obj = obj.piece_link.next;

                        if (obj.moved == 0 and util.loc_sector(obj.loc) == sec) {
                            pushPieceMove(obj);
                            return; // resume when piece_move completes
                        }
                    }
                    ctx.obj_type_idx += 1;
                    ctx.cur_obj = null;
                }

                if (display.cur_sector() == sec) {
                    display.print_sector_u(@intCast(sec));
                    display.redisplay();
                }

                ctx.sector_idx += 1;
                ctx.obj_type_idx = 0;
                ctx.cur_obj = null;
            }
            ctx.phase = .post;
            return advanceUserMove();
        },
        .post => {
            if (globals.save_movie) game.save_movie_screen();
            const automove_loop = ctx.automove_loop;
            stack.pop(); // pop user_move

            // Run computer move synchronously
            computer.move(1);
            game.save();

            if (automove_loop and globals.automove) {
                automove_turn += 1;
                if (automove_turn % globals.save_interval == 0) {
                    game.save();
                }
                startUserMove(true);
            } else {
                globals.automove = false;
                showIdlePrompt();
            }
        },
    }
}

// ── Piece move ──────────────────────────────────────────────────────────

fn pushPieceMove(obj: *piece_info_t) void {
    const city: ?*types.struct_city_info = object.find_city(obj.loc);
    if (city) |c| {
        const city_func = c.func[@intCast(obj.type)];
        if (city_func != @intFromEnum(globals.Function.NoFunc)) {
            obj.*.func = city_func;
        }
    }

    stack.push(.{ .piece_move = .{
        .obj = obj,
        .changed_location = false,
        .need_input = false,
    } });
    advancePieceMove();
}

fn advancePieceMove() void {
    const ctx = &stack.top().piece_move;
    const obj = ctx.obj;
    const obj_attr = data.piece_attr[@intCast(obj.type)];

    while (obj.moved < object.moves(obj)) {
        const saved_moves = obj.moved;
        const saved_loc = obj.loc;

        if (user.awake(obj) or ctx.need_input) {
            ctx.need_input = false;
            // Push ask_user - will resume when it pops
            stack.push(.{ .ask_user = .{ .obj = obj } });
            redisplayAskUser(obj);
            return;
        }

        if (obj.moved == saved_moves) {
            const func: globals.Function = @enumFromInt(obj.func);
            switch (func) {
                .NoFunc => {},
                .Random => user.move_random(obj),
                .Sentry => obj.*.moved = obj_attr.speed,
                .Fill => user.move_fill(obj),
                .Land => user.move_land(obj),
                .Explore => user.move_explore(obj),
                .ArmyLoad => user.move_armyload(obj),
                .ArmyAttack => user.move_armyattack(obj),
                .TTLoad => user.move_ttload(obj),
                .Repair => user.move_repair(obj),
                .WFTransport => user.move_transport(obj),
                .Move_N, .Move_NE, .Move_E, .Move_SE, .Move_S, .Move_SW, .Move_W, .Move_NW => user.move_dir(obj),
                _ => user.move_path(obj),
            }
        }

        if (obj.moved == saved_moves) {
            ctx.need_input = true;
            continue;
        }

        const obj_loc: usize = @intCast(obj.loc);
        if (obj.type == @intFromEnum(globals.PieceType.Fighter) and obj.hits > 0) {
            if ((globals.user_map[obj_loc].contents == 'O' or globals.user_map[obj_loc].contents == 'C') and obj.moved > 0) {
                obj.*.range = @intCast(obj_attr.range);
                obj.*.moved = obj_attr.speed;
                obj.*.func = @intFromEnum(globals.Function.NoFunc);
                terminal.comment("Landing confirmed");
            } else if (obj.range == 0) {
                terminal.comment("Fighter at %d crashed and burned.", terminal.loc_disp(@intCast(obj.loc)));
            }
        }

        if (saved_loc != obj.loc) ctx.changed_location = true;

        if (obj.hits > 0 and
            !ctx.changed_location and
            !(obj.type == @intFromEnum(globals.PieceType.Fighter) or obj.type == @intFromEnum(globals.PieceType.Army)) and
            obj.hits < obj_attr.max_hits and
            globals.user_map[obj_loc].contents == 'O')
        {
            obj.*.hits += 1;
        }
    }

    // Piece done
    stack.pop(); // pop piece_move
    advanceUserMove();
}

// ── Ask user ────────────────────────────────────────────────────────────

fn redisplayAskUser(obj: *piece_info_t) void {
    display.display_loc_u(obj.loc);
    object.describe_obj(obj);
    display.display_score();
    display.display_loc_u(obj.loc);
}

fn handleAskUserKey(key: vx.Key) void {
    const ctx = &stack.top().ask_user;
    const obj = ctx.obj;

    switch (ctx.sub) {
        .command => handleAskUserCommand(ctx, obj, key),
        .awaiting_direction => {
            const ch = upperKey(key);
            const dirs = "QWEDCXZA";
            const funcs = [8]globals.Function{
                .Move_NW, .Move_N, .Move_NE, .Move_E,
                .Move_SE, .Move_S, .Move_SW, .Move_W,
            };
            if (std.mem.indexOfScalar(u8, dirs, ch)) |i| {
                obj.*.func = @intFromEnum(funcs[i]);
            } else {
                display.complain();
            }
            finishAskUser(obj);
        },
        .awaiting_piece_name => {
            const ch = upperKey(key);
            var found: c_int = NOPIECE;
            for (0..NUM_OBJECTS) |i| {
                if (data.piece_attr[i].sname == ch) {
                    found = @intCast(i);
                    break;
                }
            }
            if (found == NOPIECE) {
                display.complain();
                finishAskUser(obj);
            } else {
                const info = ctx.sub.awaiting_piece_name;
                ctx.sub = .{ .awaiting_city_func = .{ .cityp = info.cityp, .piece_t = found } };
            }
        },
        .awaiting_city_func => |info| {
            const ch = upperKey(key);
            switch (ch) {
                'F' => edit.e_city_fill(info.cityp, info.piece_t),
                'G' => edit.e_city_explore(info.cityp, info.piece_t),
                'I' => {
                    ctx.sub = .{ .awaiting_city_stasis_dir = .{ .cityp = info.cityp, .piece_t = info.piece_t } };
                    return;
                },
                'K' => edit.e_city_wake(info.cityp, info.piece_t),
                'R' => edit.e_city_random(info.cityp, info.piece_t),
                'U' => edit.e_city_repair(info.cityp, info.piece_t),
                'Y' => edit.e_city_attack(info.cityp, info.piece_t),
                else => display.complain(),
            }
            user.reset_func(obj);
            finishAskUser(obj);
        },
        .awaiting_city_stasis_dir => |info| {
            const ch = upperKey(key);
            const dirs = "WEDCXZAQ";
            const MOVE_N_VAL = @as(c_long, @intFromEnum(globals.Function.Move_N));
            if (std.mem.indexOfScalar(u8, dirs, ch)) |i| {
                edit.e_set_city_func(info.cityp, info.piece_t, MOVE_N_VAL - @as(c_long, @intCast(i)));
            } else {
                display.complain();
            }
            user.reset_func(obj);
            finishAskUser(obj);
        },
    }
}

fn handleAskUserCommand(ctx: *AskUserCtx, obj: *piece_info_t, key: vx.Key) void {
    const ch = upperKey(key);
    switch (ch) {
        'Q' => askUserDirection(obj, .Northwest),
        'W' => askUserDirection(obj, .North),
        'E' => askUserDirection(obj, .Northeast),
        'D' => askUserDirection(obj, .East),
        'C' => askUserDirection(obj, .Southeast),
        'X' => askUserDirection(obj, .South),
        'Z' => askUserDirection(obj, .Southwest),
        'A' => askUserDirection(obj, .West),
        'J' => {
            // Enter edit mode; when it returns, reset_func and finish
            pushEditMode(obj.loc);
        },
        'V' => {
            const cityp = object.find_city(obj.loc);
            if (cityp == null or cityp.*.owner != USER) {
                display.complain();
            } else {
                ctx.sub = .{ .awaiting_piece_name = .{ .cityp = cityp } };
            }
        },
        ' ' => {
            user.user_skip(obj);
            finishAskUser(obj);
        },
        'F' => {
            user.user_fill(obj);
            finishAskUser(obj);
        },
        'I' => {
            ctx.sub = .awaiting_direction;
        },
        'R' => {
            user.user_random(obj);
            finishAskUser(obj);
        },
        'S' => {
            user.user_sentry(obj);
            finishAskUser(obj);
        },
        'L' => {
            user.user_land(obj);
            finishAskUser(obj);
        },
        'G' => {
            user.user_explore(obj);
            finishAskUser(obj);
        },
        'T' => {
            user.user_transport(obj);
            finishAskUser(obj);
        },
        'U' => {
            user.user_repair(obj);
            finishAskUser(obj);
        },
        'Y' => {
            user.user_armyattack(obj);
            finishAskUser(obj);
        },
        'B' => {
            if (globals.user_map[@intCast(obj.loc)].contents != 'O') {
                display.complain();
            } else {
                const cityp = object.find_city(obj.loc);
                std.debug.assert(cityp != null);
                stack.push(.{ .set_prod = .{ .cityp = cityp, .caller = .user_build } });
                pushSetProdPrompt(cityp);
            }
        },
        'H' => {
            terminal.help(&data.help_user, data.user_lines);
            terminal.prompt("Press any key to continue: ");
            stack.push(.help_screen);
        },
        'K' => {
            user.user_wake(obj);
            // Stay in ask_user
        },
        'O' => {
            user.user_cancel_auto();
            // Stay in ask_user
        },
        12, 'P' => display.redraw(),
        '?' => object.describe_obj(obj),
        else => display.complain(),
    }
}

fn finishAskUser(obj: *piece_info_t) void {
    stack.pop(); // pop ask_user
    terminal.topini();
    display.display_loc_u(obj.loc);
    display.redisplay();
    // Check for pending city production from attack
    if (attack.pending_set_prod_city) |cityp| {
        attack.pending_set_prod_city = null;
        stack.push(.{ .set_prod = .{ .cityp = cityp, .caller = .city_attack } });
        pushSetProdPrompt(cityp);
        return;
    }
    advancePieceMove();
}

// ── Direction handling ──────────────────────────────────────────────────

fn askUserDirection(obj: *piece_info_t, dir: globals.Direction) void {
    const loc = obj.loc + user.dir_offset(dir);

    if (object.good_loc(obj, loc)) {
        object.move_obj(obj, loc);
        finishAskUser(obj);
        return;
    }
    if (!globals.map[@intCast(loc)].on_board) {
        terminal.@"error"("You cannot move to the edge of the world.");
        pushDelay();
        // Stay in ask_user - delay frame on top; when it pops, user picks another direction
        return;
    }
    switch (@as(globals.PieceType, @enumFromInt(obj.type))) {
        .Army => dirArmy(obj, loc),
        .Fighter => dirFighter(obj, loc),
        else => dirShip(obj, loc),
    }
}

fn dirArmy(obj: *piece_info_t, loc: c_long) void {
    const uloc: usize = @intCast(loc);

    if (globals.user_map[uloc].contents == 'O') {
        const tt = object.find_nfull(@intFromEnum(globals.PieceType.Transport), loc);
        if (tt != null) {
            object.move_obj(obj, loc);
            finishAskUser(obj);
        } else {
            terminal.prompt("That's our city, sir!  Do you really want to attack the garrison? ");
            stack.push(.{ .yes_no = .{
                .action = .army_city,
                .obj = obj,
                .loc = loc,
                .response_msg = "Your rebel army was liquidated.",
                .stay_in_ask_on_no = false,
            } });
        }
    } else if (globals.user_map[uloc].contents == 'T') {
        terminal.prompt("Sorry, sir.  There is no more room on the transport.  Do you insist? ");
        stack.push(.{ .yes_no = .{
            .action = .fatal_army_transport,
            .obj = obj,
            .loc = loc,
            .response_msg = "Your army jumped into the briny and drowned.",
            .stay_in_ask_on_no = false,
        } });
    } else if (globals.map[uloc].contents == data.MAP_SEA) {
        terminal.prompt("Troops can't walk on water, sir.  Do you really want to go to sea? ");
        stack.push(.{ .yes_no = .{
            .action = .army_water,
            .obj = obj,
            .loc = loc,
            .response_msg = null,
            .stay_in_ask_on_no = false,
        } });
    } else if (std.ascii.isUpper(globals.user_map[uloc].contents) and
        globals.user_map[uloc].contents != 'X')
    {
        terminal.prompt("Sir, those are our men!  Do you really want to attack them? ");
        stack.push(.{ .yes_no = .{
            .action = .army_friendly,
            .obj = obj,
            .loc = loc,
            .response_msg = null,
            .stay_in_ask_on_no = false,
        } });
    } else {
        attack.attack(obj, loc);
        finishAskUser(obj);
    }
}

fn dirFighter(obj: *piece_info_t, loc: c_long) void {
    const uloc: usize = @intCast(loc);

    if (globals.map[uloc].contents == data.MAP_CITY) {
        terminal.prompt("That's never worked before, sir.  Do you really want to try? ");
        stack.push(.{ .yes_no = .{
            .action = .fighter_city,
            .obj = obj,
            .loc = loc,
            .response_msg = "Your fighter was shot down.",
            .stay_in_ask_on_no = false,
        } });
    } else if (std.ascii.isUpper(globals.user_map[uloc].contents)) {
        terminal.prompt("Sir, those are our men!  Do you really want to attack them? ");
        stack.push(.{ .yes_no = .{
            .action = .fighter_friendly,
            .obj = obj,
            .loc = loc,
            .response_msg = null,
            .stay_in_ask_on_no = false,
        } });
    } else {
        attack.attack(obj, loc);
        finishAskUser(obj);
    }
}

fn dirShip(obj: *piece_info_t, loc: c_long) void {
    const uloc: usize = @intCast(loc);
    const snprintf = @cImport({ @cInclude("stdio.h"); }).snprintf;

    if (globals.map[uloc].contents == data.MAP_CITY) {
        _ = snprintf(&globals.jnkbuf, globals.STRSIZE, "Your %s broke up on shore.",
            @as([*c]const u8, &data.piece_attr[@intCast(obj.type)].name));
        terminal.prompt("That's never worked before, sir.  Do you really want to try? ");
        stack.push(.{ .yes_no = .{
            .action = .ship_city,
            .obj = obj,
            .loc = loc,
            .response_msg = &globals.jnkbuf,
            .stay_in_ask_on_no = false,
        } });
    } else if (globals.map[uloc].contents == data.MAP_LAND) {
        terminal.prompt("Ships need sea to float, sir.  Do you really want to go ashore? ");
        stack.push(.{ .yes_no = .{
            .action = .ship_shore,
            .obj = obj,
            .loc = loc,
            .response_msg = null,
            .stay_in_ask_on_no = false,
        } });
    } else if (std.ascii.isUpper(globals.user_map[uloc].contents)) {
        terminal.prompt("Sir, those are our men!  Do you really want to attack them? ");
        stack.push(.{ .yes_no = .{
            .action = .ship_friendly,
            .obj = obj,
            .loc = loc,
            .response_msg = null,
            .stay_in_ask_on_no = false,
        } });
    } else {
        attack.attack(obj, loc);
        finishAskUser(obj);
    }
}

// ── Yes/No handler ──────────────────────────────────────────────────────

fn handleYesNoKey(key: vx.Key) void {
    const ch = upperKey(key);
    if (ch != 'Y' and ch != 'N') {
        terminal.@"error"("Please answer Y or N.");
        return;
    }

    const ctx = stack.top().yes_no;
    stack.pop(); // pop yes_no

    if (ch == 'Y') {
        executeYesAction(ctx);
    } else {
        // N pressed
        if (ctx.action == .quit) {
            // Just return to idle
            return;
        }
        // For direction confirmations: finish ask_user (piece didn't move)
        if (ctx.obj) |obj| finishAskUser(obj);
    }
}

fn executeYesAction(ctx: YesNoCtx) void {
    switch (ctx.action) {
        .quit => util.empend(),
        .army_city, .fatal_army_transport, .fighter_city, .ship_city => {
            if (ctx.response_msg) |msg| terminal.comment(msg);
            if (ctx.obj) |obj| {
                object.kill_obj(obj, ctx.loc);
                finishAskUser(obj);
            }
        },
        .army_water => {
            if (ctx.obj) |obj| {
                const uloc: usize = @intCast(ctx.loc);
                const obj_uloc: usize = @intCast(obj.loc);
                var enemy_killed = false;

                if (globals.user_map[obj_uloc].contents == 'T') {
                    terminal.comment("Your army jumped into the briny and drowned.");
                    terminal.ksend("Your army jumped into the briny and drowned.\n");
                } else if (globals.user_map[uloc].contents == data.MAP_SEA) {
                    terminal.comment("Your army marched dutifully into the sea and drowned.");
                    terminal.ksend("Your army marched dutifully into the sea and drowned.\n");
                } else {
                    enemy_killed = std.ascii.isLower(globals.user_map[uloc].contents);
                    attack.attack(obj, ctx.loc);
                    if (obj.hits > 0) {
                        terminal.comment("Your army regretfully drowns after its successful assault.");
                        terminal.ksend("Your army regretfully drowns after its successful assault.");
                    }
                }
                if (obj.hits > 0) {
                    object.kill_obj(obj, ctx.loc);
                    if (enemy_killed) object.scan(&globals.comp_map, ctx.loc);
                }
                finishAskUser(obj);
            }
        },
        .army_friendly, .fighter_friendly, .ship_friendly => {
            if (ctx.obj) |obj| {
                attack.attack(obj, ctx.loc);
                finishAskUser(obj);
            }
        },
        .ship_shore => {
            if (ctx.obj) |obj| {
                const uloc: usize = @intCast(ctx.loc);
                var enemy_killed = false;

                if (globals.user_map[uloc].contents == data.MAP_LAND) {
                    terminal.comment("Your %s broke up on shore.", @as([*c]const u8, &data.piece_attr[@intCast(obj.type)].name));
                    terminal.ksend("Your %s broke up on shore.", @as([*c]const u8, &data.piece_attr[@intCast(obj.type)].name));
                } else {
                    enemy_killed = std.ascii.isLower(globals.user_map[uloc].contents);
                    attack.attack(obj, ctx.loc);
                    if (obj.hits > 0) {
                        terminal.comment("Your %s breaks up after its successful assault.",
                            @as([*c]const u8, &data.piece_attr[@intCast(obj.type)].name));
                        terminal.ksend("Your %s breaks up after its successful assault.",
                            @as([*c]const u8, &data.piece_attr[@intCast(obj.type)].name));
                    }
                }
                if (obj.hits > 0) {
                    object.kill_obj(obj, ctx.loc);
                    if (enemy_killed) object.scan(&globals.comp_map, ctx.loc);
                }
                finishAskUser(obj);
            }
        },
    }
}

// ── Set prod ────────────────────────────────────────────────────────────

fn pushSetProdPrompt(cityp: [*c]city_info_t) void {
    object.scan(&globals.user_map, cityp.*.loc);
    display.display_loc_u(cityp.*.loc);
    terminal.prompt("What do you want the city at %d to produce? ",
        terminal.loc_disp(@intCast(cityp.*.loc)));
}

fn handleSetProdKey(key: vx.Key) void {
    const ch = upperKey(key);
    const ctx = stack.top().set_prod;

    var found: c_int = NOPIECE;
    for (0..NUM_OBJECTS) |i| {
        if (data.piece_attr[i].sname == ch) {
            found = @intCast(i);
            break;
        }
    }

    if (found == NOPIECE) {
        terminal.@"error"("I don't know how to build those.");
        pushSetProdPrompt(ctx.cityp);
        return;
    }

    const cityp = ctx.cityp;
    const caller = ctx.caller;
    cityp.*.prod = @intCast(found);
    cityp.*.work = -@divTrunc(@as(c_long, data.piece_attr[@intCast(found)].build_time), 5);
    stack.pop(); // pop set_prod

    switch (caller) {
        .user_move_production => {
            const umctx = &stack.top().user_move;
            umctx.city_idx += 1;
            advanceUserMove();
        },
        .user_build => {
            // Stay in ask_user (original doesn't return after B)
            const ask_ctx = &stack.top().ask_user;
            redisplayAskUser(ask_ctx.obj);
        },
        .edit_prod => {
            // Stay in edit mode
        },
        .city_attack => {
            // City conquered, production set
            object.scan(&globals.user_map, cityp.*.loc);
            // Now finish the ask_user that was interrupted
            if (stack.top().* == .ask_user) {
                const obj = stack.top().ask_user.obj;
                finishAskUser(obj);
            } else {
                advancePieceMove();
            }
        },
    }
}

// ── Edit mode ───────────────────────────────────────────────────────────

fn pushEditMode(loc: c_long) void {
    terminal.comment("Edit mode...");
    stack.push(.{ .edit_mode = .{
        .edit_cursor = loc,
        .path_start = -1,
        .path_type = NOPIECE,
    } });
    display.display_loc_u(loc);
}

fn handleEditKey(key: vx.Key) void {
    const ctx = &stack.top().edit_mode;

    switch (ctx.sub) {
        .input => {
            // Check direction first
            const dir = display.direction(key.codepoint);
            if (dir != -1) {
                if (!display.move_cursor(&ctx.edit_cursor, data.dir_offset[@intCast(dir)])) {
                    vx.beep();
                }
                display.display_loc_u(ctx.edit_cursor);
                return;
            }

            const ch = upperKey(key);
            switch (ch) {
                'B' => {
                    const cityp = object.find_city(ctx.edit_cursor);
                    if (cityp == null) {
                        terminal.huh();
                    } else {
                        stack.push(.{ .set_prod = .{ .cityp = cityp, .caller = .edit_prod } });
                        pushSetProdPrompt(cityp);
                    }
                },
                'F' => edit.e_fill(ctx.edit_cursor),
                'G' => edit.e_explore(ctx.edit_cursor),
                'H' => {
                    terminal.help(&data.help_edit, data.edit_lines);
                    terminal.prompt("Press any key to continue: ");
                    stack.push(.help_screen);
                },
                'I' => {
                    const contents = globals.user_map[@intCast(ctx.edit_cursor)].contents;
                    if (!std.ascii.isUpper(contents) or contents == 'X') {
                        terminal.huh();
                    } else {
                        ctx.sub = .awaiting_stasis_dir;
                    }
                },
                'K' => edit.e_wake(ctx.edit_cursor),
                'L' => edit.e_land(ctx.edit_cursor),
                'M' => {
                    ctx.path_type = NOPIECE;
                    edit.e_move(&ctx.path_start, ctx.edit_cursor);
                },
                'N' => edit.e_end(&ctx.path_start, ctx.edit_cursor, ctx.path_type),
                'O' => exitEditMode(),
                'P' => pushGetRange("New Sector? ", 0, NUM_SECTORS - 1, .edit_sector),
                'R' => edit.e_random(ctx.edit_cursor),
                'S' => edit.e_sleep(ctx.edit_cursor),
                'T' => edit.e_transport(ctx.edit_cursor),
                'U' => edit.e_repair(ctx.edit_cursor),
                'V' => {
                    const cityp = object.find_city(ctx.edit_cursor);
                    if (cityp == null or cityp.*.owner != USER) {
                        terminal.huh();
                    } else {
                        ctx.sub = .{ .awaiting_piece_name = .{ .cityp = cityp } };
                    }
                },
                'Y' => edit.e_attack(ctx.edit_cursor),
                '?' => edit.e_info(ctx.edit_cursor),
                12 => display.redraw(),
                else => terminal.huh(),
            }
        },
        .awaiting_stasis_dir => {
            const ch = upperKey(key);
            const dirs = "WEDCXZAQ";
            const MOVE_N = @as(c_long, @intFromEnum(globals.Function.Move_N));
            if (std.mem.indexOfScalar(u8, dirs, ch)) |i| {
                edit.e_set_func(ctx.edit_cursor, MOVE_N - @as(c_long, @intCast(i)));
            } else {
                terminal.huh();
            }
            ctx.sub = .input;
        },
        .awaiting_piece_name => |info| {
            const ch = upperKey(key);
            var found: c_int = NOPIECE;
            for (0..NUM_OBJECTS) |i| {
                if (data.piece_attr[i].sname == ch) {
                    found = @intCast(i);
                    break;
                }
            }
            if (found == NOPIECE) {
                terminal.huh();
                ctx.sub = .input;
            } else {
                ctx.sub = .{ .awaiting_city_func = .{ .cityp = info.cityp, .piece_t = found } };
            }
        },
        .awaiting_city_func => |info| {
            const ch = upperKey(key);
            const MOVE_N = @as(c_long, @intFromEnum(globals.Function.Move_N));
            switch (ch) {
                'F' => edit.e_city_fill(info.cityp, info.piece_t),
                'G' => edit.e_city_explore(info.cityp, info.piece_t),
                'I' => {
                    ctx.sub = .{ .awaiting_city_stasis_dir = .{ .cityp = info.cityp, .piece_t = info.piece_t } };
                    return;
                },
                'K' => edit.e_city_wake(info.cityp, info.piece_t),
                'M' => {
                    ctx.path_type = info.piece_t;
                    edit.e_move(&ctx.path_start, ctx.edit_cursor);
                },
                'R' => edit.e_city_random(info.cityp, info.piece_t),
                'U' => edit.e_city_repair(info.cityp, info.piece_t),
                'Y' => edit.e_city_attack(info.cityp, info.piece_t),
                else => terminal.huh(),
            }
            ctx.sub = .input;
            _ = MOVE_N;
        },
        .awaiting_city_stasis_dir => |info| {
            const ch = upperKey(key);
            const dirs = "WEDCXZAQ";
            const MOVE_N = @as(c_long, @intFromEnum(globals.Function.Move_N));
            if (std.mem.indexOfScalar(u8, dirs, ch)) |i| {
                edit.e_set_city_func(info.cityp, info.piece_t, MOVE_N - @as(c_long, @intCast(i)));
            } else {
                terminal.huh();
            }
            ctx.sub = .input;
        },
    }
}

fn exitEditMode() void {
    terminal.comment("Exiting edit mode.");
    stack.pop(); // pop edit_mode

    if (stack.depth > 0) {
        const below = stack.top();
        switch (below.*) {
            .ask_user => {
                const obj = below.ask_user.obj;
                user.reset_func(obj);
                finishAskUser(obj);
            },
            .idle => showIdlePrompt(),
            else => {},
        }
    }
}

// ── Get range ───────────────────────────────────────────────────────────

fn pushGetRange(message: [*c]const u8, low: c_int, high: c_int, caller: GetRangeCtx.GetRangeCaller) void {
    terminal.prompt(message);
    vx.render();
    stack.push(.{ .get_range = .{
        .low = low,
        .high = high,
        .message = message,
        .caller = caller,
        .cursor_y = vx.screenCursorRow(),
        .cursor_x = vx.screenCursorCol(),
    } });
    vx.setCursorVisible(true);
}

fn handleGetRangeKey(key: vx.Key) void {
    const ctx = &stack.top().get_range;

    if (key.codepoint == '\r' or key.codepoint == '\n') {
        vx.setCursorVisible(false);
        if (ctx.len == 0) {
            terminal.@"error"("Please enter an integer.");
            restartGetRange(ctx);
            return;
        }
        var valid = true;
        for (ctx.buf[0..ctx.len]) |c| {
            if (c < '0' or c > '9') { valid = false; break; }
        }
        if (!valid) {
            terminal.@"error"("Please enter an integer.");
            restartGetRange(ctx);
            return;
        }
        const result = std.fmt.parseInt(c_int, ctx.buf[0..ctx.len], 10) catch {
            terminal.@"error"("Please enter a small integer.");
            restartGetRange(ctx);
            return;
        };
        if (result < ctx.low or result > ctx.high) {
            terminal.@"error"("Please enter an integer in the range %d..%d.", ctx.low, ctx.high);
            restartGetRange(ctx);
            return;
        }

        const caller = ctx.caller;
        stack.pop();
        terminal.topini();

        switch (caller) {
            .sector => display.print_sector_u(result),
            .examine => display.print_sector_c(result),
            .edit_sector => {
                if (stack.top().* == .edit_mode) {
                    stack.top().edit_mode.edit_cursor = util.sector_loc(result);
                    display.sector_change();
                }
            },
            .free_moves => {
                const n: u8 = @intCast(result);
                computer.move(n);
                game.save();
                showIdlePrompt();
            },
        }
        return;
    }

    if (key.codepoint == 127 or key.codepoint == 8) {
        if (ctx.len > 0) {
            ctx.len -= 1;
            if (ctx.cursor_x > 0) ctx.cursor_x -= 1;
            vx.clearCell(ctx.cursor_x, ctx.cursor_y);
            vx.setScreenCursor(ctx.cursor_y, ctx.cursor_x);
        }
        return;
    }

    if (key.codepoint >= '0' and key.codepoint <= '9') {
        if (ctx.len < STRSIZE - 1) {
            ctx.buf[ctx.len] = @truncate(key.codepoint);
            ctx.len += 1;
            vx.writeCell(ctx.cursor_x, ctx.cursor_y, @intCast(key.codepoint), .{});
            ctx.cursor_x +|= 1;
            vx.setScreenCursor(ctx.cursor_y, ctx.cursor_x);
        }
    }
}

fn restartGetRange(ctx: *GetRangeCtx) void {
    ctx.len = 0;
    terminal.prompt(ctx.message);
    vx.render();
    ctx.cursor_y = vx.screenCursorRow();
    ctx.cursor_x = vx.screenCursorCol();
    vx.setCursorVisible(true);
}

// ── Get str ─────────────────────────────────────────────────────────────

fn pushGetStr(caller: GetStrCtx.GetStrCaller) void {
    terminal.prompt("Filename? ");
    vx.render();
    stack.push(.{ .get_str = .{
        .caller = caller,
        .cursor_y = vx.screenCursorRow(),
        .cursor_x = vx.screenCursorCol(),
    } });
    vx.setCursorVisible(true);
}

fn handleGetStrKey(key: vx.Key) void {
    const ctx = &stack.top().get_str;

    if (key.codepoint == '\r' or key.codepoint == '\n') {
        vx.setCursorVisible(false);
        ctx.buf[ctx.len] = 0;
        const caller = ctx.caller;
        var buf_copy: [STRSIZE]u8 = ctx.buf;
        const len = ctx.len;
        stack.pop();
        terminal.topini();

        switch (caller) {
            .map_file => writeMapFile(buf_copy[0..len]),
        }
        return;
    }

    if (key.codepoint == 127 or key.codepoint == 8) {
        if (ctx.len > 0) {
            ctx.len -= 1;
            if (ctx.cursor_x > 0) ctx.cursor_x -= 1;
            vx.clearCell(ctx.cursor_x, ctx.cursor_y);
            vx.setScreenCursor(ctx.cursor_y, ctx.cursor_x);
        }
        return;
    }

    if (key.codepoint >= 0x20 and key.codepoint < 0x7F) {
        if (ctx.len < STRSIZE - 1) {
            ctx.buf[ctx.len] = @truncate(key.codepoint);
            ctx.len += 1;
            vx.writeCell(ctx.cursor_x, ctx.cursor_y, @intCast(key.codepoint), .{});
            ctx.cursor_x +|= 1;
            vx.setScreenCursor(ctx.cursor_y, ctx.cursor_x);
        }
    }
}

fn writeMapFile(name: []u8) void {
    var f = std.fs.cwd().createFile(name, .{}) catch {
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

// ── Helpers ─────────────────────────────────────────────────────────────

fn upperKey(key: vx.Key) u8 {
    if (key.mods.ctrl and key.codepoint >= 'a' and key.codepoint <= 'z')
        return @truncate(key.codepoint - 'a' + 1);
    const ch: u8 = @truncate(key.codepoint);
    if (ch >= 'a' and ch <= 'z') return ch - 'a' + 'A';
    return ch;
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

fn c_movie() void {
    while (true) {
        computer.move(1);
        display.print_zoom(&globals.comp_map);
        game.save();
    }
}
