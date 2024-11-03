const std = @import("std");
const vaxis = @import("vaxis");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

pub const panic = vaxis.panic_handler;

const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    focus_in,
    focus_out,
    paste_start,
    paste_end,
    paste: []const u8,
    color_report: vaxis.Color.Report,
    color_scheme: vaxis.Color.Scheme,
    winsize: vaxis.Winsize,
};

const FileReader = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    current_page: u16,
    path: []const u8,
    ctx: [*c]c.fz_context,
    doc: [*c]c.fz_document,
    total_pages: u16,
    current_image: ?vaxis.Image,

    pub fn init(allocator: std.mem.Allocator, args: [][]const u8) !FileReader {
        const ctx = c.fz_new_context(null, null, c.FZ_STORE_UNLIMITED) orelse {
            std.debug.print("Failed to create mupdf context\n", .{});
            return error.FailedToCreateContext;
        };
        errdefer c.fz_drop_context(ctx);
        c.fz_register_document_handlers(ctx);

        const path = args[1];
        const doc = c.fz_open_document(ctx, path.ptr) orelse {
            const err_msg = c.fz_caught_message(ctx);
            std.debug.print("Failed to open document: {s}\n", .{err_msg});
            return error.FailedToOpenDocument;
        };
        errdefer c.fz_drop_document(ctx, doc);

        const total_pages = @as(u16, @intCast(c.fz_count_pages(ctx, doc)));
        const current_page = blk: {
            if (args.len == 3) {
                const page = try std.fmt.parseInt(u16, args[2], 10);
                if (page < 1 or page > total_pages) {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.writeAll("Invalid page number\n");
                    return error.InvalidPageNumber;
                }
                break :blk page - 1;
            }
            break :blk 0;
        };

        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .mouse = null,
            .current_page = current_page,
            .path = path,
            .ctx = ctx,
            .doc = doc,
            .total_pages = total_pages,
            .current_image = null,
        };
    }

    pub fn deinit(self: *FileReader) void {
        if (self.current_image) |img| {
            self.vx.freeImage(self.tty.anyWriter(), img.id);
        }
        c.fz_drop_document(self.ctx, self.doc);
        c.fz_drop_context(self.ctx);
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *FileReader) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        while (!self.should_quit) {
            loop.pollEvent();

            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            try self.draw();

            var buffered = self.tty.bufferedWriter();
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    pub fn update(self: *FileReader, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                } else if (key.matches('j', .{})) {
                    if (self.current_page < self.total_pages - 1) {
                        self.current_page += 1;
                        if (self.current_image) |img| {
                            self.vx.freeImage(self.tty.anyWriter(), img.id);
                            self.current_image = null;
                        }
                    }
                } else if (key.matches('k', .{})) {
                    if (self.current_page > 0) {
                        self.current_page -= 1;
                        if (self.current_image) |img| {
                            self.vx.freeImage(self.tty.anyWriter(), img.id);
                            self.current_image = null;
                        }
                    }
                }
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
        }
    }

    pub fn draw(self: *FileReader) !void {
        const win = self.vx.window();
        win.clear();

        if (self.current_image == null) {
            var ctm = c.fz_scale(1.5, 1.5);
            ctm = c.fz_pre_translate(ctm, 0, 0);
            ctm = c.fz_pre_rotate(ctm, 0);

            const pix = c.fz_new_pixmap_from_page_number(
                self.ctx,
                self.doc,
                self.current_page,
                ctm,
                c.fz_device_rgb(self.ctx),
                0,
            ) orelse return error.PixmapCreationFailed;
            defer c.fz_drop_pixmap(self.ctx, pix);

            const width = c.fz_pixmap_width(self.ctx, pix);
            const height = c.fz_pixmap_height(self.ctx, pix);
            const samples = c.fz_pixmap_samples(self.ctx, pix);

            var img = try vaxis.zigimg.Image.fromRawPixels(
                self.allocator,
                @intCast(width),
                @intCast(height),
                samples[0..@intCast(width * height * 3)],
                .rgb24,
            );
            defer img.deinit();

            self.current_image = try self.vx.transmitImage(
                self.allocator,
                self.tty.anyWriter(),
                &img,
                .rgb,
            );
        }

        if (self.current_image) |img| {
            const dims = try img.cellSize(win);
            const center = vaxis.widgets.alignment.center(win, dims.cols, dims.rows);
            try img.draw(center, .{ .scale = .contain });
        }
    }
};

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2 or args.len > 3) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("Usage: pdf-viewer <path-to-pdf> <optional-page-number>\n");
        return error.InvalidArguments;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();

    var app = try FileReader.init(allocator, args);
    defer app.deinit();

    try app.run();
}
