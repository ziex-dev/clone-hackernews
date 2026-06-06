const std = @import("std");
const zx = @import("zx");
const query = @import("query.zig");

pub const Story = query.StoryRow;

pub const Comment = struct {
    id: usize,
    story_id: usize,
    parent_id: ?usize = null,
    author: []const u8,
    text: []const u8,
    time: i64,
    score: i32 = 1,
    replies: []usize = &.{},

    fn fromRow(row: query.CommentRow) Comment {
        return .{
            .id = row.id,
            .story_id = row.story_id,
            .parent_id = row.parent_id,
            .author = row.author,
            .text = row.text,
            .time = row.time,
            .score = row.score,
        };
    }
};

pub const User = query.UserRow;

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
        return query.storyByIdQuery(self.allocator, id) catch return null;
    }

    pub fn getCommentById(self: *Store, id: usize) ?Comment {
        const row = query.commentByIdQuery(self.allocator, id) catch return null;
        if (row) |r| return Comment.fromRow(r);
        return null;
    }

    pub fn getUser(self: *Store, username: []const u8) ?User {
        return query.getUser(self.allocator, username) catch return null;
    }

    pub fn hasVoted(self: *Store, username: []const u8, item_id: usize) bool {
        return query.hasVoted(self.allocator, username, item_id) catch false;
    }

    // Load all comments for a story into self.comments hashmap (for item page tree)
    pub fn loadCommentsForStory(self: *Store, story_id: usize) !void {
        const rows = try query.commentsForStoryQuery(self.allocator, story_id);
        for (rows) |row| {
            try self.comments.put(self.allocator, row.id, Comment.fromRow(row));
        }
        for (rows) |row| {
            if (row.parent_id) |parent_id| {
                if (self.comments.getPtr(parent_id)) |p| {
                    const new_replies = try self.allocator.realloc(p.replies, p.replies.len + 1);
                    new_replies[new_replies.len - 1] = row.id;
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
            comments[i] = Comment.fromRow(row);
        }
        return .{ .comments = comments, .has_more = has_more };
    }

    // Mutations
    pub fn addStory(_: *Store, title: []const u8, url: ?[]const u8, text: ?[]const u8, author: []const u8) !usize {
        const time = std.Io.Timestamp.now(zx.io(), .awake);
        const rowid = try query.insertStory(title, url, text, author, time.toMilliseconds());
        return @intCast(rowid);
    }

    pub fn addComment(_: *Store, story_id: usize, parent_id: ?usize, author: []const u8, text: []const u8) !usize {
        const time = std.Io.Timestamp.now(zx.io(), .awake);
        const rowid = try query.insertComment(story_id, parent_id, author, text, time.toMilliseconds());
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

pub fn get(allocator: std.mem.Allocator) !*Store {
    const s = try allocator.create(Store);
    s.* = .{ .allocator = allocator };

    return s;
}

fn rowsToPagedStories(allocator: std.mem.Allocator, rows: []const Story, page_size: usize) !PagedStories {
    const has_more = rows.len > page_size;
    const display_rows = if (has_more) rows[0..page_size] else rows;
    const stories = try allocator.dupe(Story, display_rows);
    return .{ .stories = stories, .has_more = has_more };
}
