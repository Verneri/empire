extern fn restore_game() c_int;
extern fn init_game() void;
extern fn save_game() void;
pub extern fn replay_movie() void;
pub extern fn save_movie_screen() void;

pub const LoadError = error{NotLoaded};

pub fn restore() LoadError!void {
    const res = restore_game();
    if (res == 0) return LoadError.NotLoaded;
}

pub fn init() void {
    init_game();
}

pub fn save() void {
    save_game();
}
