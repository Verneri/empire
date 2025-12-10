pub const loc_t = c_long;
pub const uchar = u8;
pub const struct_real_map = extern struct {
    contents: u8 = @import("std").mem.zeroes(u8),
    on_board: bool = @import("std").mem.zeroes(bool),
    cityp: [*c]city_info_t = @import("std").mem.zeroes([*c]city_info_t),
    objp: [*c]piece_info_t = @import("std").mem.zeroes([*c]piece_info_t),
};
pub const real_map_t = struct_real_map;
pub const struct_view_map = extern struct {
    contents: u8 = @import("std").mem.zeroes(u8),
    seen: c_long = @import("std").mem.zeroes(c_long),
};
pub const view_map_t = struct_view_map;
pub const struct_city_info = extern struct {
    loc: loc_t = @import("std").mem.zeroes(loc_t),
    owner: uchar = @import("std").mem.zeroes(uchar),
    func: [9]c_long = @import("std").mem.zeroes([9]c_long),
    work: c_long = @import("std").mem.zeroes(c_long),
    prod: u8 = @import("std").mem.zeroes(u8),
};
pub const city_info_t = struct_city_info;
pub const struct_piece_info = extern struct {
    piece_link: link_t = @import("std").mem.zeroes(link_t),
    loc_link: link_t = @import("std").mem.zeroes(link_t),
    cargo_link: link_t = @import("std").mem.zeroes(link_t),
    owner: c_int = @import("std").mem.zeroes(c_int),
    type: c_int = @import("std").mem.zeroes(c_int),
    loc: loc_t = @import("std").mem.zeroes(loc_t),
    func: c_long = @import("std").mem.zeroes(c_long),
    hits: c_short = @import("std").mem.zeroes(c_short),
    moved: c_int = @import("std").mem.zeroes(c_int),
    ship: [*c]struct_piece_info = @import("std").mem.zeroes([*c]struct_piece_info),
    cargo: [*c]struct_piece_info = @import("std").mem.zeroes([*c]struct_piece_info),
    count: c_short = @import("std").mem.zeroes(c_short),
    range: c_short = @import("std").mem.zeroes(c_short),
};
pub const link_t = extern struct {
    next: [*c]struct_piece_info = @import("std").mem.zeroes([*c]struct_piece_info),
    prev: [*c]struct_piece_info = @import("std").mem.zeroes([*c]struct_piece_info),
};
pub const piece_info_t = struct_piece_info;
