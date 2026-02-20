const types = @import("types.zig");
const piece_info_t = types.piece_info_t;
pub extern fn scan(vmap: [*c]types.view_map_t, loc: c_long) void;
pub extern fn set_prod(cityp: [*c]types.city_info_t) void;
pub extern fn produce(cityp: [*c]types.city_info_t) void;
pub extern fn move_sat(obj: [*c]piece_info_t) void;
pub extern fn find_city(loc: c_long) [*c]types.city_info_t;
pub extern fn find_nearest_city(loc: c_long, owner: c_int, city_loc: [*c]c_long) c_int;
pub extern fn find_obj_at_loc(loc: c_long) [*c]piece_info_t;
pub extern fn describe_obj(obj: [*c]piece_info_t) void;
pub extern fn good_loc(obj: [*c]piece_info_t, loc: c_long) bool;
pub extern fn move_obj(obj: [*c]piece_info_t, new_loc: c_long) void;
pub extern fn kill_obj(obj: [*c]piece_info_t, loc: c_long) void;
pub extern fn kill_city(cityp: [*c]types.city_info_t) void;
pub extern fn find_transport(owner: c_int, loc: c_long) c_long;
pub extern fn find_obj(@"type": c_int, loc: c_long) [*c]piece_info_t;
pub extern fn get_piece_name() c_int;

extern fn obj_capacity(obj: [*c]piece_info_t) c_int;
extern fn obj_moves(obj: [*c]piece_info_t) c_int;

pub fn moves(obj: *piece_info_t) c_int {
    return obj_moves(obj);
}

pub fn capacity(obj: *piece_info_t) c_int {
    return obj_capacity(obj);
}
