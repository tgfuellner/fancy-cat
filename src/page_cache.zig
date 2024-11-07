const std = @import("std");
const vaxis = @import("vaxis");
const config = @import("config");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

pub const PageCache = struct {
    const Page = struct {
        image: vaxis.Image,
        last_access: i64,
    };

    allocator: std.mem.Allocator,
    ctx: [*c]c.fz_context,
    doc: [*c]c.fz_document,
    cache: std.AutoHashMap(u16, Page),

    pub fn init(allocator: std.mem.Allocator, ctx: [*c]c.fz_context, doc: [*c]c.fz_document) !PageCache {
        return PageCache{
            .allocator = allocator,
            .ctx = ctx,
            .doc = doc,
            .cache = std.AutoHashMap(u16, Page).init(allocator),
        };
    }

    pub fn deinit(self: *PageCache, vx: *vaxis.Vaxis, writer: anytype) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            vx.freeImage(writer, entry.value_ptr.image.id);
        }
        self.cache.deinit();
    }

    pub fn getPage(self: *PageCache, current_page: u16) ?vaxis.Image {
        if (self.cache.getPtr(current_page)) |cached| {
            cached.last_access = std.time.milliTimestamp();
            return cached.image;
        }
        return null;
    }
};
