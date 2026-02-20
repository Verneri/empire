const std = @import("std");
const types = @import("types.zig");
const globals = @import("globals.zig");
const data = @import("data.zig");
const math = @import("math.zig");
const object = @import("object.zig");
const terminal = @import("terminal.zig");

const USER: c_int = @intFromEnum(globals.Ownership.User);
const UNOWNED: c_int = @intFromEnum(globals.Ownership.Unowned);

pub fn attack(att_obj: [*c]types.piece_info_t, loc: c_long) void {
    if (globals.map[@intCast(loc)].contents == data.MAP_CITY)
        attack_city(att_obj, loc)
    else
        attack_obj(att_obj, loc);
}

fn attack_city(att_obj: [*c]types.piece_info_t, loc: c_long) void {
    const cityp = object.find_city(loc);
    std.debug.assert(cityp != null);

    const att_owner = att_obj.*.owner;
    const city_owner: c_int = @intCast(cityp.*.owner);

    if (math.irand(2) == 0) { // attack fails
        if (att_owner == USER) {
            terminal.comment("The scum defending the city crushed your attacking blitzkrieger.");
            terminal.ksend("The scum defending the city crushed your attacking blitzkrieger.\n");
        } else if (city_owner == USER) {
            terminal.ksend("Your city at %d is under attack.\n", terminal.loc_disp(@intCast(cityp.*.loc)));
            terminal.comment("Your city at %d is under attack.", terminal.loc_disp(@intCast(cityp.*.loc)));
        }
        object.kill_obj(att_obj, loc);
    } else { // attack succeeded
        object.kill_city(cityp);
        cityp.*.owner = @intCast(att_owner);
        object.kill_obj(att_obj, loc);

        if (att_owner == USER) {
            terminal.ksend("City at %d has been subjugated!\n", terminal.loc_disp(@intCast(cityp.*.loc)));
            terminal.@"error"("City at %d has been subjugated!", terminal.loc_disp(@intCast(cityp.*.loc)));
            terminal.extra("Your army has been dispersed to enforce control.");
            terminal.ksend("Your army has been dispersed to enforce control.\n");
            object.set_prod(cityp);
        } else if (city_owner == USER) {
            terminal.ksend("City at %d has been lost to the enemy!\n", terminal.loc_disp(@intCast(cityp.*.loc)));
            terminal.comment("City at %d has been lost to the enemy!", terminal.loc_disp(@intCast(cityp.*.loc)));
        }
    }
    // let city owner see all results
    if (city_owner != UNOWNED) object.scan(ownerMap(city_owner), loc);
}

fn attack_obj(att_obj: [*c]types.piece_info_t, loc: c_long) void {
    const def_obj = object.find_obj_at_loc(loc);
    std.debug.assert(def_obj != null);

    if (def_obj.*.type == @intFromEnum(globals.PieceType.Satellite)) return;

    while (att_obj.*.hits > 0 and def_obj.*.hits > 0) {
        if (math.irand(2) == 0) // defender hits
            att_obj.*.hits -= data.piece_attr[@intCast(def_obj.*.type)].strength
        else
            def_obj.*.hits -= data.piece_attr[@intCast(att_obj.*.type)].strength;
    }

    if (att_obj.*.hits > 0) { // attacker won
        describe(att_obj, def_obj, loc);
        const owner = def_obj.*.owner;
        object.kill_obj(def_obj, loc);
        survive(att_obj, loc);
        object.scan(ownerMap(owner), loc);
    } else { // defender won
        describe(def_obj, att_obj, loc);
        const owner = att_obj.*.owner;
        object.kill_obj(att_obj, loc);
        survive(def_obj, loc);
        object.scan(ownerMap(owner), loc);
    }
}

fn survive(obj: [*c]types.piece_info_t, loc: c_long) void {
    while (object.capacity(obj) < obj.*.count)
        object.kill_obj(obj.*.cargo, loc);

    object.move_obj(obj, loc);
}

fn describe(win_obj: [*c]types.piece_info_t, lose_obj: [*c]types.piece_info_t, loc: c_long) void {
    if (win_obj.*.owner != lose_obj.*.owner) {
        if (win_obj.*.owner == USER) {
            globals.user_score += data.piece_attr[@intCast(lose_obj.*.type)].build_time;
            terminal.ksend("Enemy %s at %d destroyed.\n", &data.piece_attr[@intCast(lose_obj.*.type)].name, terminal.loc_disp(@intCast(loc)));
            terminal.topmsg(1, "Enemy %s at %d destroyed.", &data.piece_attr[@intCast(lose_obj.*.type)].name, terminal.loc_disp(@intCast(loc)));
            terminal.ksend("Your %s has %d hits left\n", &data.piece_attr[@intCast(win_obj.*.type)].name, win_obj.*.hits);
            terminal.topmsg(2, "Your %s has %d hits left.", &data.piece_attr[@intCast(win_obj.*.type)].name, win_obj.*.hits);

            const diff = win_obj.*.count - object.capacity(win_obj);
            if (diff > 0) switch (win_obj.*.cargo.*.type) {
                @intFromEnum(globals.PieceType.Army) => {
                    terminal.ksend("%d armies fell overboard and drowned in the assault.\n", diff);
                    terminal.topmsg(3, "%d armies fell overboard and drowned in the assault.", diff);
                },
                @intFromEnum(globals.PieceType.Fighter) => {
                    terminal.ksend("%d fighters fell overboard and were lost in the assault.\n", diff);
                    terminal.topmsg(3, "%d fighters fell overboard and were lost in the assault.", diff);
                },
                else => {},
            };
        } else {
            globals.comp_score += data.piece_attr[@intCast(lose_obj.*.type)].build_time;
            terminal.ksend("Your %s at %d destroyed.\n", &data.piece_attr[@intCast(lose_obj.*.type)].name, terminal.loc_disp(@intCast(loc)));
            terminal.topmsg(3, "Your %s at %d destroyed.", &data.piece_attr[@intCast(lose_obj.*.type)].name, terminal.loc_disp(@intCast(loc)));
        }
        terminal.set_need_delay();
    }
}

fn ownerMap(owner: c_int) [*c]types.view_map_t {
    return if (owner == USER) &globals.user_map else &globals.comp_map;
}
