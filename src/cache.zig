const std = @import("std");
const vaxis = @import("vaxis");

pub const Cache = struct {
    cache: std.AutoHashMap(u16, vaxis.zigimg.Image),

    pub fn init(allocator: std.mem.Allocator) Cache {
        return .{
            .cache = std.AutoHashMap(u16, vaxis.zigimg.Image).init(allocator),
        };
    }

    pub fn get(self: *Cache, page_number: u16) ?*vaxis.zigimg.Image {
        if (self.cache.get(page_number)) |img| {
            return img;
        }
        return null;
    }
};
