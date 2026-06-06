const zx = @import("zx");
const std = @import("std");

pub const StoryRow = struct {
    id: usize,
    title: []const u8,
    url: ?[]const u8,
    text: ?[]const u8,
    author: []const u8,
    score: i32,
    comment_count: usize,
    time: i64,
};

pub const CommentRow = struct {
    id: usize,
    story_id: usize,
    parent_id: ?usize,
    author: []const u8,
    text: []const u8,
    time: i64,
    score: i32,
};

pub const UserRow = struct {
    username: []const u8,
    password: []const u8,
};

const story_columns = "id, title, url, text, author, score, comment_count, time";
const comment_columns = "id, story_id, parent_id, author, text, time, score";

pub fn storyCount(allocator: std.mem.Allocator) !i64 {
    const row = try zx.db.row(allocator, struct { cnt: i64 }, "SELECT COUNT(*) AS cnt FROM stories", .{});
    return if (row) |r| r.cnt else 0;
}

pub fn insertStory(title: []const u8, url: ?[]const u8, text: ?[]const u8, author: []const u8, time: i64) !i64 {
    const result = try zx.db.run(
        "INSERT INTO stories (title, url, text, author, time) VALUES (?, ?, ?, ?, ?)",
        .{ title, url, text, author, time },
    );
    return result.last_insert_id;
}

pub fn insertComment(story_id: usize, parent_id: ?usize, author: []const u8, text: []const u8, time: i64) !i64 {
    const result = try zx.db.run(
        "INSERT INTO comments (story_id, parent_id, author, text, time) VALUES (?, ?, ?, ?, ?)",
        .{ story_id, parent_id, author, text, time },
    );

    // Increment comment_count on the story
    _ = try zx.db.run(
        "UPDATE stories SET comment_count = comment_count + 1 WHERE id = ?",
        .{story_id},
    );

    return result.last_insert_id;
}

pub fn insertUser(username: []const u8, password: []const u8) !void {
    _ = try zx.db.run(
        "INSERT OR IGNORE INTO users (username, password) VALUES (?, ?)",
        .{ username, password },
    );
}

pub fn getUser(allocator: std.mem.Allocator, username: []const u8) !?UserRow {
    return zx.db.row(allocator, UserRow, "SELECT username, password FROM users WHERE username = ?", .{username});
}

pub fn insertVote(username: []const u8, item_id: usize) !void {
    _ = try zx.db.run(
        "INSERT OR IGNORE INTO votes (username, item_id) VALUES (?, ?)",
        .{ username, item_id },
    );
}

pub fn hasVoted(allocator: std.mem.Allocator, username: []const u8, item_id: usize) !bool {
    const row = try zx.db.row(allocator, struct { found: i64 }, "SELECT 1 AS found FROM votes WHERE username = ? AND item_id = ?", .{ username, item_id });
    return row != null;
}

pub fn upvoteStory(item_id: usize) !void {
    _ = try zx.db.run(
        "UPDATE stories SET score = score + 1 WHERE id = ?",
        .{item_id},
    );
}

pub fn upvoteComment(item_id: usize) !void {
    _ = try zx.db.run(
        "UPDATE comments SET score = score + 1 WHERE id = ?",
        .{item_id},
    );
}

pub fn isComment(allocator: std.mem.Allocator, item_id: usize) !bool {
    const row = try zx.db.row(allocator, struct { found: i64 }, "SELECT 1 AS found FROM comments WHERE id = ?", .{item_id});
    return row != null;
}

pub fn searchStories(allocator: std.mem.Allocator, search_query: []const u8) ![]const StoryRow {
    return zx.db.rows(
        allocator,
        StoryRow,
        "SELECT " ++ story_columns ++ " FROM stories WHERE title LIKE '%' || ? || '%' OR text LIKE '%' || ? || '%'",
        .{ search_query, search_query },
    );
}

pub fn storiesByScore(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const StoryRow {
    return zx.db.rows(
        allocator,
        StoryRow,
        "SELECT " ++ story_columns ++ " FROM stories ORDER BY score DESC LIMIT ? OFFSET ?",
        .{ limit, offset },
    );
}

pub fn storiesByNewest(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const StoryRow {
    return zx.db.rows(
        allocator,
        StoryRow,
        "SELECT " ++ story_columns ++ " FROM stories ORDER BY id DESC LIMIT ? OFFSET ?",
        .{ limit, offset },
    );
}

pub fn storiesByOldest(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const StoryRow {
    return zx.db.rows(
        allocator,
        StoryRow,
        "SELECT " ++ story_columns ++ " FROM stories ORDER BY time ASC LIMIT ? OFFSET ?",
        .{ limit, offset },
    );
}

pub fn storiesByTitlePrefix(allocator: std.mem.Allocator, prefix: []const u8, limit: usize, offset: usize) ![]const StoryRow {
    return zx.db.rows(
        allocator,
        StoryRow,
        "SELECT " ++ story_columns ++ " FROM stories WHERE title LIKE ? || '%' ORDER BY id DESC LIMIT ? OFFSET ?",
        .{ prefix, limit, offset },
    );
}

pub fn storiesByTitleKeywords(allocator: std.mem.Allocator, kw1: []const u8, kw2: []const u8, limit: usize, offset: usize) ![]const StoryRow {
    return zx.db.rows(
        allocator,
        StoryRow,
        "SELECT " ++ story_columns ++ " FROM stories WHERE title LIKE '%' || ? || '%' OR title LIKE '%' || ? || '%' ORDER BY id DESC LIMIT ? OFFSET ?",
        .{ kw1, kw2, limit, offset },
    );
}

pub fn paginatedSearchStories(allocator: std.mem.Allocator, search_query: []const u8, limit: usize, offset: usize) ![]const StoryRow {
    return zx.db.rows(
        allocator,
        StoryRow,
        "SELECT " ++ story_columns ++ " FROM stories WHERE title LIKE '%' || ? || '%' OR text LIKE '%' || ? || '%' ORDER BY id DESC LIMIT ? OFFSET ?",
        .{ search_query, search_query, limit, offset },
    );
}

pub fn storyByIdQuery(allocator: std.mem.Allocator, id: usize) !?StoryRow {
    return zx.db.row(allocator, StoryRow, "SELECT " ++ story_columns ++ " FROM stories WHERE id = ?", .{id});
}

pub fn commentsForStoryQuery(allocator: std.mem.Allocator, story_id: usize) ![]const CommentRow {
    return zx.db.rows(
        allocator,
        CommentRow,
        "SELECT " ++ comment_columns ++ " FROM comments WHERE story_id = ? ORDER BY id ASC",
        .{story_id},
    );
}

pub fn commentByIdQuery(allocator: std.mem.Allocator, id: usize) !?CommentRow {
    return zx.db.row(allocator, CommentRow, "SELECT " ++ comment_columns ++ " FROM comments WHERE id = ?", .{id});
}

pub fn commentsPaginated(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const CommentRow {
    return zx.db.rows(
        allocator,
        CommentRow,
        "SELECT " ++ comment_columns ++ " FROM comments ORDER BY time DESC LIMIT ? OFFSET ?",
        .{ limit, offset },
    );
}
