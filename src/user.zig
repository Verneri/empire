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
        while (cur != null) {
            cur.?.moved = 0;
            object.scan(&globals.user_map, cur.?.loc);
            cur = cur.?.piece_link.next;
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
    while (cur_satellite != null) {
        object.move_sat(cur_satellite.?);
        cur_satellite = cur_satellite.?.piece_link.next;
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
            while (cur != null) {
                const obj = cur.?;
                if (obj.moved == 0 and util.loc_sector(obj.loc) == sec) {
                    piece_move(obj);
                }
                cur = obj.piece_link.next;
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

extern fn piece_move(arg_obj: [*c]types.piece_info_t) void;
