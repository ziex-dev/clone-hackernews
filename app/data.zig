const std = @import("std");
const zx = @import("zx");
const query = @import("query.zig");

pub const Story = struct {
    id: usize,
    title: []const u8,
    url: ?[]const u8 = null,
    text: ?[]const u8 = null,
    author: []const u8,
    score: i32,
    comment_count: usize,
    time: i64,
};

pub const Comment = struct {
    id: usize,
    story_id: usize,
    parent_id: ?usize = null,
    author: []const u8,
    text: []const u8,
    time: i64,
    score: i32 = 1,
    replies: []usize = &.{},
};

pub const User = struct {
    username: []const u8,
    password: []const u8,
};

pub const PagedStories = struct {
    stories: []Story,
    has_more: bool,
};

pub const PagedComments = struct {
    comments: []Comment,
    has_more: bool,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    comments: std.AutoHashMapUnmanaged(usize, Comment) = .empty,

    // Paginated story queries
    pub fn getStoriesByScore(_: *Store, allocator: std.mem.Allocator, page: usize, page_size: usize) !PagedStories {
        const offset = (page - 1) * page_size;
        const rows = try query.storiesByScore(allocator, page_size + 1, offset);
        return rowsToPagedStories(allocator, rows, page_size);
    }

    pub fn getStoriesByNewest(_: *Store, allocator: std.mem.Allocator, page: usize, page_size: usize) !PagedStories {
        const offset = (page - 1) * page_size;
        const rows = try query.storiesByNewest(allocator, page_size + 1, offset);
        return rowsToPagedStories(allocator, rows, page_size);
    }

    pub fn getStoriesByOldest(_: *Store, allocator: std.mem.Allocator, page: usize, page_size: usize) !PagedStories {
        const offset = (page - 1) * page_size;
        const rows = try query.storiesByOldest(allocator, page_size + 1, offset);
        return rowsToPagedStories(allocator, rows, page_size);
    }

    pub fn getStoriesByTitlePrefix(_: *Store, allocator: std.mem.Allocator, prefix: []const u8, page: usize, page_size: usize) !PagedStories {
        const offset = (page - 1) * page_size;
        const rows = try query.storiesByTitlePrefix(allocator, prefix, page_size + 1, offset);
        return rowsToPagedStories(allocator, rows, page_size);
    }

    pub fn getStoriesByTitleKeywords(_: *Store, allocator: std.mem.Allocator, kw1: []const u8, kw2: []const u8, page: usize, page_size: usize) !PagedStories {
        const offset = (page - 1) * page_size;
        const rows = try query.storiesByTitleKeywords(allocator, kw1, kw2, page_size + 1, offset);
        return rowsToPagedStories(allocator, rows, page_size);
    }

    pub fn searchStories(_: *Store, allocator: std.mem.Allocator, search_query: []const u8, page: usize, page_size: usize) !PagedStories {
        const offset = (page - 1) * page_size;
        const rows = try query.paginatedSearchStories(allocator, search_query, page_size + 1, offset);
        return rowsToPagedStories(allocator, rows, page_size);
    }

    // Single item lookups
    pub fn getStoryById(self: *Store, id: usize) ?Story {
        const row = query.storyByIdQuery(self.allocator, id) catch return null;
        if (row) |r| return rowToStory(r);
        return null;
    }

    pub fn getCommentById(self: *Store, id: usize) ?Comment {
        const row = query.commentByIdQuery(self.allocator, id) catch return null;
        if (row) |r| return rowToComment(r);
        return null;
    }

    pub fn getUser(self: *Store, username: []const u8) ?User {
        const result = query.getUser(self.allocator, username) catch return null;
        if (result) |r| return User{ .username = r.username, .password = r.password };
        return null;
    }

    pub fn hasVoted(self: *Store, username: []const u8, item_id: usize) bool {
        return query.hasVoted(self.allocator, username, item_id) catch false;
    }

    // Load all comments for a story into self.comments hashmap (for item page tree)
    pub fn loadCommentsForStory(self: *Store, story_id: usize) !void {
        const rows = try query.commentsForStoryQuery(self.allocator, story_id);
        for (rows) |row| {
            const id: usize = @intCast(asInt(row, "id"));
            const parent_id_val = asInt(row, "parent_id");
            const parent_id: ?usize = if (parent_id_val > 0) @intCast(parent_id_val) else null;
            try self.comments.put(self.allocator, id, .{
                .id = id,
                .story_id = @intCast(asInt(row, "story_id")),
                .parent_id = parent_id,
                .author = asText(row, "author"),
                .text = asText(row, "text"),
                .time = asInt(row, "time"),
                .score = @intCast(asInt(row, "score")),
            });
        }
        for (rows) |row| {
            const parent_id_val = asInt(row, "parent_id");
            if (parent_id_val > 0) {
                const parent_id: usize = @intCast(parent_id_val);
                const child_id: usize = @intCast(asInt(row, "id"));
                if (self.comments.getPtr(parent_id)) |p| {
                    const new_replies = try self.allocator.realloc(p.replies, p.replies.len + 1);
                    new_replies[new_replies.len - 1] = child_id;
                    p.replies = new_replies;
                }
            }
        }
    }

    // Paginated comments query
    pub fn getCommentsPaginated(_: *Store, allocator: std.mem.Allocator, page: usize, page_size: usize) !PagedComments {
        const offset = (page - 1) * page_size;
        const rows = try query.commentsPaginated(allocator, page_size + 1, offset);
        const has_more = rows.len > page_size;
        const display_rows = if (has_more) rows[0..page_size] else rows;
        var comments = try allocator.alloc(Comment, display_rows.len);
        for (display_rows, 0..) |row, i| {
            comments[i] = rowToComment(row);
        }
        return .{ .comments = comments, .has_more = has_more };
    }

    // Mutations
    pub fn addStory(_: *Store, title: []const u8, url: ?[]const u8, text: ?[]const u8, author: []const u8) !usize {
        const time = std.time.timestamp();
        const rowid = try query.insertStory(title, url, text, author, time);
        return @intCast(rowid);
    }

    pub fn addComment(_: *Store, story_id: usize, parent_id: ?usize, author: []const u8, text: []const u8) !usize {
        const time = std.time.timestamp();
        const rowid = try query.insertComment(story_id, parent_id, author, text, time);
        return @intCast(rowid);
    }

    pub fn vote(self: *Store, username: []const u8, item_id: usize) !void {
        if (try query.hasVoted(self.allocator, username, item_id)) return;
        try query.insertVote(username, item_id);
        if (try query.isComment(self.allocator, item_id)) {
            try query.upvoteComment(item_id);
        } else {
            try query.upvoteStory(item_id);
        }
    }

    pub fn addUser(_: *Store, username: []const u8, password: []const u8) !void {
        try query.insertUser(username, password);
    }
};

var db_initialized = false;

pub fn get(allocator: std.mem.Allocator) !*Store {
    const s = try allocator.create(Store);
    s.* = .{ .allocator = allocator };

    if (!db_initialized) {
        try query.init();

        if ((try query.storyCount(allocator)) == 0) {
            const story1_id = try s.addStory("Ziex: A full-stack web framework for Zig", null, null, "nurulhudaapon");
            _ = try s.addStory("Show HN: Exact Hacker News Clone in Ziex", null, "I built this clone to show off Ziex.", "nurulhudaapon");
            _ = try s.addStory("Zig 0.15.2 Released", "https://ziglang.org/download/0.15.1/release-notes.html", null, "andrewrk");

            const c1_id = try s.addComment(story1_id, null, "user1", "This looks amazing!");
            _ = try s.addComment(story1_id, null, "user2", "Zig is the future of web dev.");
            _ = try s.addComment(story1_id, c1_id, "user3", "I agree!");
        }

        db_initialized = true;
    }

    return s;
}

fn rowsToPagedStories(allocator: std.mem.Allocator, rows: []const zx.db.Row, page_size: usize) !PagedStories {
    const has_more = rows.len > page_size;
    const display_rows = if (has_more) rows[0..page_size] else rows;
    var stories = try allocator.alloc(Story, display_rows.len);
    for (display_rows, 0..) |row, i| {
        stories[i] = rowToStory(row);
    }
    return .{ .stories = stories, .has_more = has_more };
}

fn rowToStory(row: zx.db.Row) Story {
    return .{
        .id = @intCast(asInt(row, "id")),
        .title = asText(row, "title"),
        .url = asOptionalText(row, "url"),
        .text = asOptionalText(row, "text"),
        .author = asText(row, "author"),
        .score = @intCast(asInt(row, "score")),
        .comment_count = @intCast(asInt(row, "comment_count")),
        .time = asInt(row, "time"),
    };
}

fn rowToComment(row: zx.db.Row) Comment {
    const parent_id_val = asInt(row, "parent_id");
    return .{
        .id = @intCast(asInt(row, "id")),
        .story_id = @intCast(asInt(row, "story_id")),
        .parent_id = if (parent_id_val > 0) @intCast(parent_id_val) else null,
        .author = asText(row, "author"),
        .text = asText(row, "text"),
        .time = asInt(row, "time"),
        .score = @intCast(asInt(row, "score")),
    };
}

fn asInt(row: zx.db.Row, name: []const u8) i64 {
    return switch (row.get(name) orelse .null) {
        .integer => |value| value,
        .float => |value| @intFromFloat(value),
        else => 0,
    };
}

fn asText(row: zx.db.Row, name: []const u8) []const u8 {
    return switch (row.get(name) orelse .null) {
        .text => |value| value,
        else => "",
    };
}

fn asOptionalText(row: zx.db.Row, name: []const u8) ?[]const u8 {
    return switch (row.get(name) orelse .null) {
        .text => |value| value,
        else => null,
    };
}
