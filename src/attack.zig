const std = @import("std");
const types = @import("types.zig");
const globals = @import("globals.zig");
const data = @import("data.zig");
const math = @import("math.zig");
const object = @import("object.zig");
const terminal = @import("terminal.zig");

const Piece = types.Piece;

const USER: i32 = @intFromEnum(globals.Ownership.User);
const UNOWNED: i32 = @intFromEnum(globals.Ownership.Unowned);

pub var pending_set_prod_city: ?*types.city_info_t = null;

pub fn attack(att_obj: *Piece, loc: i64) void {
    if (globals.map[@intCast(loc)].contents == data.MAP_CITY)
        attack_city(att_obj, loc)
    else
        attack_obj(att_obj, loc);
}

fn attack_city(att_obj: *Piece, loc: i64) void {
    const maybe_cityp = object.find_city(loc);
    const cityp = maybe_cityp.?;
    const att_owner = att_obj.owner;
    const city_owner: i32 = @intCast(cityp.*.owner);

    if (math.irand(2) == 0) { // attack fails
        if (att_owner == USER) {
            terminal.comment("The scum defending the city crushed your attacking blitzkrieger.", .{});
            terminal.ksend("The scum defending the city crushed your attacking blitzkrieger.\n", .{});
        } else if (city_owner == USER) {
            terminal.ksend("Your city at {} is under attack.\n", .{terminal.loc_disp(@intCast(cityp.*.loc))});
            terminal.comment("Your city at {} is under attack.", .{terminal.loc_disp(@intCast(cityp.*.loc))});
        }
        object.kill_obj(att_obj, loc);
    } else { // attack succeeded
        object.kill_city(cityp);
        cityp.*.owner = @intCast(att_owner);
        object.kill_obj(att_obj, loc);

        if (att_owner == USER) {
            terminal.ksend("City at {} has been subjugated!\n", .{terminal.loc_disp(@intCast(cityp.*.loc))});
            terminal.@"error"("City at {} has been subjugated!", .{terminal.loc_disp(@intCast(cityp.*.loc))});
            terminal.extra("Your army has been dispersed to enforce control.", .{});
            terminal.ksend("Your army has been dispersed to enforce control.\n", .{});
            pending_set_prod_city = cityp;
        } else if (city_owner == USER) {
            terminal.ksend("City at {} has been lost to the enemy!\n", .{terminal.loc_disp(@intCast(cityp.*.loc))});
            terminal.comment("City at {} has been lost to the enemy!", .{terminal.loc_disp(@intCast(cityp.*.loc))});
        }
    }
    // let city owner see all results
    if (city_owner != UNOWNED) object.scan(ownerMap(city_owner), loc);
}

fn attack_obj(att_obj: *Piece, loc: i64) void {
    const def_obj = object.find_obj_at_loc(loc).?;

    if (def_obj.type == @intFromEnum(globals.PieceType.Satellite)) return;

    while (att_obj.hits > 0 and def_obj.hits > 0) {
        if (math.irand(2) == 0) // defender hits
            att_obj.hits -= data.piece_attr[@intCast(def_obj.type)].strength
        else
            def_obj.hits -= data.piece_attr[@intCast(att_obj.type)].strength;
    }

    if (att_obj.hits > 0) { // attacker won
        describe(att_obj, def_obj, loc);
        const owner = def_obj.owner;
        object.kill_obj(def_obj, loc);
        survive(att_obj, loc);
        object.scan(ownerMap(owner), loc);
    } else { // defender won
        describe(def_obj, att_obj, loc);
        const owner = att_obj.owner;
        object.kill_obj(att_obj, loc);
        survive(def_obj, loc);
        object.scan(ownerMap(owner), loc);
    }
}

fn survive(obj: *Piece, loc: i64) void {
    while (object.capacity(obj) < obj.count) {
        const cargo_idx = obj.cargo[0];
        object.kill_obj(&globals.pool[cargo_idx], loc);
    }
    object.move_obj(obj, loc);
}

fn describe(win_obj: *Piece, lose_obj: *Piece, loc: i64) void {
    if (win_obj.owner != lose_obj.owner) {
        if (win_obj.owner == USER) {
            globals.user_score += data.piece_attr[@intCast(lose_obj.type)].build_time;
            terminal.ksend("Enemy {s} at {} destroyed.\n", .{ &data.piece_attr[@intCast(lose_obj.type)].name, terminal.loc_disp(@intCast(loc)) });
            terminal.topmsg(1, "Enemy {s} at {} destroyed.", .{ &data.piece_attr[@intCast(lose_obj.type)].name, terminal.loc_disp(@intCast(loc)) });
            terminal.ksend("Your {s} has {} hits left\n", .{ &data.piece_attr[@intCast(win_obj.type)].name, win_obj.hits });
            terminal.topmsg(2, "Your {s} has {} hits left.", .{ &data.piece_attr[@intCast(win_obj.type)].name, win_obj.hits });

            const diff = win_obj.count - object.capacity(win_obj);
            if (diff > 0) {
                const first_cargo = &globals.pool[win_obj.cargo[0]];
                switch (first_cargo.type) {
                    @intFromEnum(globals.PieceType.Army) => {
                        terminal.ksend("{} armies fell overboard and drowned in the assault.\n", .{diff});
                        terminal.topmsg(3, "{} armies fell overboard and drowned in the assault.", .{diff});
                    },
                    @intFromEnum(globals.PieceType.Fighter) => {
                        terminal.ksend("{} fighters fell overboard and were lost in the assault.\n", .{diff});
                        terminal.topmsg(3, "{} fighters fell overboard and were lost in the assault.", .{diff});
                    },
                    else => {},
                }
            }
        } else {
            globals.comp_score += data.piece_attr[@intCast(lose_obj.type)].build_time;
            terminal.ksend("Your {s} at {} destroyed.\n", .{ &data.piece_attr[@intCast(lose_obj.type)].name, terminal.loc_disp(@intCast(loc)) });
            terminal.topmsg(3, "Your {s} at {} destroyed.", .{ &data.piece_attr[@intCast(lose_obj.type)].name, terminal.loc_disp(@intCast(loc)) });
        }
        terminal.set_need_delay();
    }
}

fn ownerMap(owner: i32) *[globals.MAP_SIZE]types.view_map_t {
    return if (owner == USER) &globals.user_map else &globals.comp_map;
}
