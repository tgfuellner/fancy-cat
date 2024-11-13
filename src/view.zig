const std = @import("std");
const vaxis = @import("vaxis");
const fzwatch = @import("fzwatch");
const config = @import("config");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

pub const panic = vaxis.panic_handler;

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    file_changed,
};

// TODO split pdf and view
pub const FileView = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    current_page_number: u16,
    path: []const u8,
    ctx: [*c]c.fz_context,
    doc: [*c]c.fz_document,
    temp_doc: ?[*c]c.fz_document,
    total_pages: u16,
    current_page: ?vaxis.Image,
    watcher: ?fzwatch.Watcher,
    thread: ?std.Thread,
    zoom: f32,
    y_offset: f32,
    x_offset: f32,

    pub fn init(allocator: std.mem.Allocator, args: [][]const u8) !FileView {
        const ctx = c.fz_new_context(null, null, c.FZ_STORE_UNLIMITED) orelse {
            std.debug.print("Failed to create mupdf context\n", .{});
            return error.FailedToCreateContext;
        };
        errdefer c.fz_drop_context(ctx);
        c.fz_register_document_handlers(ctx);
        // XXX figure out errors instead of ignoring them lol
        c.fz_set_error_callback(ctx, null, null);
        c.fz_set_warning_callback(ctx, null, null);

        const path = args[1];
        const doc = c.fz_open_document(ctx, path.ptr) orelse {
            const err_msg = c.fz_caught_message(ctx);
            std.debug.print("Failed to open document: {s}\n", .{err_msg});
            return error.FailedToOpenDocument;
        };
        errdefer c.fz_drop_document(ctx, doc);

        const total_pages = @as(u16, @intCast(c.fz_count_pages(ctx, doc)));
        const current_page_number = blk: {
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

        var watcher: ?fzwatch.Watcher = null;
        if (config.FileMonitor.enabled) {
            watcher = try fzwatch.Watcher.init(allocator);
            if (watcher) |*w| try w.addFile(path);
        }

        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .current_page_number = current_page_number,
            .path = path,
            .ctx = ctx,
            .doc = doc,
            .total_pages = total_pages,
            .watcher = watcher,
            .current_page = null,
            .temp_doc = null,
            .mouse = null,
            .thread = null,
            .zoom = 1.0,
            .y_offset = 0,
            .x_offset = 0,
        };
    }

    pub fn deinit(self: *FileView) void {
        if (self.watcher) |*w| w.deinit();
        if (self.current_page) |img| self.vx.freeImage(self.tty.anyWriter(), img.id);
        if (self.temp_doc) |doc| c.fz_drop_document(self.ctx, doc);
        c.fz_drop_document(self.ctx, self.doc);
        c.fz_drop_context(self.ctx);
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    fn callback(context: ?*anyopaque, event: fzwatch.Event) void {
        switch (event) {
            .modified => {
                const loop = @as(*vaxis.Loop(Event), @ptrCast(@alignCast(context.?)));
                loop.postEvent(Event.file_changed);
            },
        }
    }

    fn watcherThread(watcher: *fzwatch.Watcher) !void {
        try watcher.start(.{ .latency = config.FileMonitor.latency });
    }

    pub fn run(self: *FileView) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        if (config.FileMonitor.enabled) {
            if (self.watcher) |*w| {
                w.setCallback(callback, &loop);
                self.thread = try std.Thread.spawn(.{}, watcherThread, .{w});
            }
        }

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

    fn reset_zoom_and_scroll(self: *FileView) void {
        self.zoom = 1.0;
        self.y_offset = 0;
        self.x_offset = 0;
    }

    fn reset_current_page(self: *FileView) void {
        if (self.current_page) |img| {
            self.vx.freeImage(self.tty.anyWriter(), img.id);
            self.current_page = null;
        }
    }

    const ScrollDirection = enum {
        Up,
        Down,
        Left,
        Right,
    };

    fn handle_scroll(self: *FileView, direction: ScrollDirection) void {
        const step = config.Appearance.scroll_step;
        switch (direction) {
            .Up => self.y_offset += step,
            .Down => self.y_offset -= step,
            .Left => self.x_offset += step,
            .Right => self.x_offset -= step,
        }
        self.current_page = null;
    }

    fn change_page(self: *FileView, delta: i32) void {
        const new_page = @as(i32, @intCast(self.current_page_number)) + delta;
        const valid_page = new_page >= 0 and new_page < self.total_pages;

        if (valid_page) {
            self.current_page_number = @as(u16, @intCast(new_page));
            self.reset_current_page();
            self.reset_zoom_and_scroll();
        }
    }

    fn handleKeyStroke(self: *FileView, key: vaxis.Key) !void {
        const km = config.KeyMap;

        if (key.matches(km.quit.key, km.quit.modifiers)) {
            self.should_quit = true;
        } else if (key.matches(km.next.key, km.next.modifiers)) {
            self.change_page(1);
        } else if (key.matches(km.prev.key, km.prev.modifiers)) {
            self.change_page(-1);
        } else if (key.matches(km.zoom_in.key, km.zoom_in.modifiers)) {
            self.zoom *= (config.Appearance.zoom_step + 1);
            self.current_page = null;
        } else if (key.matches(km.zoom_out.key, km.zoom_out.modifiers)) {
            self.zoom /= (config.Appearance.zoom_step + 1);
            self.current_page = null;
        } else if (key.matches(km.scroll_up.key, km.scroll_up.modifiers)) {
            self.handle_scroll(.Up);
        } else if (key.matches(km.scroll_down.key, km.scroll_down.modifiers)) {
            self.handle_scroll(.Down);
        } else if (key.matches(km.scroll_left.key, km.scroll_left.modifiers)) {
            self.handle_scroll(.Left);
        } else if (key.matches(km.scroll_right.key, km.scroll_right.modifiers)) {
            self.handle_scroll(.Right);
        } else if (key.matches(km.undo.key, km.undo.modifiers)) {
            self.reset_zoom_and_scroll();
            self.current_page = null;
        }
    }

    pub fn update(self: *FileView, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                try self.handleKeyStroke(key);
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
                self.reset_current_page();
                // XXX prob change this once propper zoom handling
                self.reset_zoom_and_scroll();
            },
            .file_changed => {
                self.temp_doc = c.fz_open_document(self.ctx, self.path.ptr) orelse {
                    std.debug.print("Failed to reload document\n", .{});
                    return;
                };
                // XXX check if this can be done more efficient rather than check on every file change
                // probably check if file attribute has changed
                self.total_pages = @as(u16, @intCast(c.fz_count_pages(self.ctx, self.temp_doc.?)));
            },
        }
    }

    pub fn draw(self: *FileView) !void {
        const win = self.vx.window();
        win.clear();

        if (self.temp_doc) |doc| {
            self.doc = doc;
            self.temp_doc = null;
            self.current_page = null;
        }

        if (self.current_page == null) {
            const page = c.fz_load_page(self.ctx, self.doc, self.current_page_number);
            const bound = c.fz_bound_page(self.ctx, page);

            const winsize = try vaxis.Tty.getWinsize(self.tty.fd);

            const scale: f32 = @min(
                @as(f32, @floatFromInt(winsize.x_pixel)) / bound.x1,
                @as(f32, @floatFromInt(winsize.y_pixel)) / bound.y1,
            );
            if (self.zoom == 1.0) self.zoom = scale * config.Appearance.size;

            const bbox = c.fz_make_irect(
                0,
                0,
                @intFromFloat(bound.x1 * self.zoom),
                @intFromFloat(bound.y1 * self.zoom),
            );
            const pix = c.fz_new_pixmap_with_bbox(self.ctx, c.fz_device_rgb(self.ctx), bbox, null, 0);
            c.fz_clear_pixmap_with_value(self.ctx, pix, 0xFF);

            // TODO clamp offset

            var ctm = c.fz_scale(self.zoom, self.zoom);
            ctm = c.fz_pre_translate(ctm, self.x_offset, self.y_offset);

            const dev = c.fz_new_draw_device(self.ctx, ctm, pix);
            c.fz_run_page(self.ctx, page, dev, c.fz_identity, null);
            c.fz_close_device(self.ctx, dev);

            if (config.Appearance.darkmode) c.fz_invert_pixmap(self.ctx, pix);

            const width = bbox.x1;
            const height = bbox.y1;
            const samples = c.fz_pixmap_samples(self.ctx, pix);

            var img = try vaxis.zigimg.Image.fromRawPixels(
                self.allocator,
                @intCast(width),
                @intCast(height),
                samples[0..@intCast(width * height * 3)],
                .rgb24,
            );
            defer img.deinit();

            if (self.current_page) |prev_img| {
                self.vx.freeImage(self.tty.anyWriter(), prev_img.id);
            }

            self.current_page = try self.vx.transmitImage(
                self.allocator,
                self.tty.anyWriter(),
                &img,
                .rgb,
            );
        }

        if (self.current_page) |img| {
            const dims = try img.cellSize(win);
            const center = vaxis.widgets.alignment.center(win, dims.cols, dims.rows);
            try img.draw(center, .{ .scale = .contain });
        }
    }
};
