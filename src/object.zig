const types = @import("types.zig");
pub extern fn scan(vmap: [*c]types.view_map_t, loc: c_long) void;
pub extern fn set_prod(cityp: [*c]types.city_info_t) void;
pub extern fn produce(cityp: [*c]types.city_info_t) void;
pub extern fn move_sat(obj: [*c]types.piece_info_t) void;
pub extern fn find_city(loc: c_long) [*c]types.city_info_t;
pub extern fn find_nearest_city(loc: c_long, owner: c_int, city_loc: [*c]c_long) c_int;

extern fn obj_moves(obj: [*c]types.piece_info_t) c_int;

pub fn moves(obj: *types.piece_info_t) c_int {
    return obj_moves(obj);
}
