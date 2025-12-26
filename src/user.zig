const globals = @import("globals.zig");
const object = @import("object.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const terminal = @import("terminal.zig");
const display = @import("display.zig");
const util = @import("util.zig");
const game = @import("game.zig");

extern fn user_move() void;

pub fn move() void {
    // reset moved for units
    for (globals.user_obj) |obj| {
        var cur: ?*types.struct_piece_info = obj;
        while (cur != null) : (cur = cur.?.piece_link.next) {
            cur.?.moved = 0;
            object.scan(&globals.user_map, cur.?.loc);
        }
    }
    // produce
    for (&globals.city) |*city| {
        if (owned_by(city, globals.Ownership.User)) {
            object.scan(&globals.user_map, city.loc);
            const prod = city.prod;
            if (prod == @intFromEnum(globals.PieceType.NoPiece)) {
                object.set_prod(city);
            } else {
                city.work += 1;
                if (city.work >= data.piece_attr[prod].build_time) {
                    terminal.ksend("%s has been completed at city %d.\n", &data.piece_attr[prod].article, terminal.loc_disp(@as(c_int, @bitCast(@as(c_int, @truncate(city.loc))))));
                    terminal.comment("%s has been completed at city %d.\n", &data.piece_attr[prod].article, terminal.loc_disp(@as(c_int, @bitCast(@as(c_int, @truncate(city.loc))))));

                    object.produce(city);
                }
            }
        }
    }

    var cur_satellite: ?*types.struct_piece_info = globals.user_obj[@intFromEnum(globals.PieceType.Satellite)];
    while (cur_satellite != null) : (cur_satellite = cur_satellite.?.piece_link.next) {
        object.move_sat(cur_satellite.?);
    }

    var sec_start = display.cur_sector();
    if (sec_start < 0) sec_start = 0;
    const start: usize = @intCast(sec_start);
    const end: usize = start + globals.NUM_SECTORS;

    for (start..end) |i| {
        const sec = @rem(i, globals.NUM_SECTORS);
        display.sector_change();
        for (data.move_order[0..globals.NUM_OBJECTS]) |j| {
            var cur: ?*types.struct_piece_info = globals.user_obj[@as(usize, @intCast(j))];
            while (cur != null) : (cur = cur.?.piece_link.next) {
                const obj = cur.?;
                if (obj.moved == 0 and util.loc_sector(obj.loc) == sec) {
                    piece_move(obj);
                }
            }
        }
        if (display.cur_sector() == sec) {
            display.print_sector_u(@intCast(sec));
            display.redisplay();
        }
    }
    if (globals.save_movie) game.save_movie_screen();
}

pub inline fn owned_by(obj: anytype, owner: globals.Ownership) bool {
    return obj.owner == @intFromEnum(owner);
}

fn piece_move(obj: *types.piece_info_t) void {
    const city: ?*types.struct_city_info = object.find_city(obj.loc);
    if (city) |c| {
        const city_func = c.func[@intCast(obj.type)];
        if (city_func != @intFromEnum(globals.Function.NoFunc)) {
            obj.*.func = city_func;
        }
    }

    var changed_location = false;
    const obj_attr = data.piece_attr[@intCast(obj.type)];
    const speed = obj_attr.speed;
    const max_hits = obj_attr.max_hits;
    var need_input = false;

    while (obj.moved < object.moves(obj)) {
        const saved_moves = obj.moved;
        const saved_loc = obj.loc;
        if (awake(obj) or need_input) {
            ask_user(obj);
            terminal.topini();
            display.display_loc_u(obj.loc);
            display.redisplay();
            need_input = false;
        }

        if (obj.moved == saved_moves) {
            const func: globals.Function = @enumFromInt(obj.func);
            switch (func) {
                .NoFunc => {},
                .Random => {
                    move_random(obj);
                },
                .Sentry => {
                    obj.*.moved = speed;
                },
                .Fill => {
                    move_fill(obj);
                },
                .Land => {
                    move_land(obj);
                },
                .Explore => {
                    move_explore(obj);
                },
                .ArmyLoad => move_armyload(obj),
                .ArmyAttack => move_armyattack(obj),
                .TTLoad => move_ttload(obj),
                .Repair => move_repair(obj),
                .WFTransport => move_transport(obj),

                .Move_N, .Move_NE, .Move_E, .Move_SE, .Move_S, .Move_SW, .Move_W, .Move_NW => move_dir(obj),

                _ => move_path(obj),
            }
        }

        if (obj.moved == saved_moves) {
            need_input = true;
        }

        const obj_loc: usize = @intCast(obj.loc);
        if (obj.type == @intFromEnum(globals.PieceType.Fighter) and obj.hits > 0) {
            if ((globals.user_map[obj_loc].contents == 'O' or globals.user_map[obj_loc].contents == 'C') and obj.moved > 0) {
                obj.*.range = @intCast(obj_attr.range);
                obj.*.moved = speed;
                obj.*.func = @intFromEnum(globals.Function.NoFunc);
                terminal.comment("Landing confirmed");
            } else if (obj.range == 0) {
                terminal.comment("Fighter at %d crashed and burned.", terminal.loc_disp(@intCast(obj.loc)));
            }
        }

        if (saved_loc != obj.loc) {
            changed_location = true;
        }

        if (obj.hits > 0 and
            !changed_location and
            !(obj.type == @intFromEnum(globals.PieceType.Fighter) or obj.type == @intFromEnum(globals.PieceType.Army)) and
            obj.hits < max_hits and
            globals.user_map[obj_loc].contents == 'O')
        {
            obj.*.hits += 1;
        }
    }
}

extern fn awake(arg_obj: *types.piece_info_t) bool;
extern fn ask_user(obj: *types.piece_info_t) void;
extern fn move_random(obj: *types.piece_info_t) void;
extern fn move_fill(obj: *types.piece_info_t) void;
extern fn move_land(obj: *types.piece_info_t) void;
extern fn move_explore(obj: *types.piece_info_t) void;
extern fn move_armyload(obj: *types.piece_info_t) void;
extern fn move_armyattack(obj: *types.piece_info_t) void;
extern fn move_ttload(obj: *types.piece_info_t) void;
extern fn move_repair(obj: *types.piece_info_t) void;
extern fn move_transport(obj: *types.piece_info_t) void;
extern fn move_dir(obj: *types.piece_info_t) void;
extern fn move_path(obj: *types.piece_info_t) void;
