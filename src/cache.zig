const std = @import("std");
const vaxis = @import("vaxis");

pub const cache = struct {
    cache: std.AutoHashMap(u16, vaxis.zigimg.Image),
};
