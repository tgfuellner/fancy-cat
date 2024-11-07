const std = @import("std");
const vaxis = @import("vaxis");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

pub fn createImg(
    ctx: [*c]c.fz_context,
    doc: [*c]c.fz_document,
    page_number: u16,
    allocator: std.mem.Allocator,
) !vaxis.zigimg.Image {
    var ctm = c.fz_scale(1.5, 1.5);
    ctm = c.fz_pre_translate(ctm, 0, 0);
    ctm = c.fz_pre_rotate(ctm, 0);

    const pix = c.fz_new_pixmap_from_page_number(
        ctx,
        doc,
        page_number,
        ctm,
        c.fz_device_rgb(ctx),
        0,
    ) orelse return error.PixmapCreationFailed;
    defer c.fz_drop_pixmap(ctx, pix);

    const width = c.fz_pixmap_width(ctx, pix);
    const height = c.fz_pixmap_height(ctx, pix);
    const samples = c.fz_pixmap_samples(ctx, pix);

    return try vaxis.zigimg.Image.fromRawPixels(
        allocator,
        @intCast(width),
        @intCast(height),
        samples[0..@intCast(width * height * 3)],
        .rgb24,
    );
}
