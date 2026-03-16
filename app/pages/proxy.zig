const std = @import("std");
const zx = @import("zx");
const data = @import("../data.zig");

/// Runs before every page and route
pub fn Proxy(ctx: *zx.ProxyContext) !void {
    const session = ctx.request.cookies.get("session");

    var state = AuthState{
        .username = null,
        .is_authenticated = false,
    };

    if (session) |s| {
        if (std.mem.indexOfScalar(u8, s, ':')) |idx| {
            const username = s[0..idx];
            const password = s[idx + 1 ..];

            const s_store = data.get(ctx.allocator) catch null;
            if (s_store) |store| {
                if (store.getUser(username)) |user| {
                    if (std.mem.eql(u8, user.password, password)) {
                        state.username = username;
                        state.is_authenticated = true;
                    }
                }
            }
        }
    }

    ctx.state(state);

    // Handle protected routes if any
    if (isProtectedRoute(ctx.request.pathname) and !state.is_authenticated) {
        return ctx.response.redirect("/login?msg=You must be logged in to access this page", 302);
    }

    ctx.next();
}

const protected_routes: []const []const u8 = &.{"/submit"};

fn isProtectedRoute(path: []const u8) bool {
    for (protected_routes) |route| {
        if (std.mem.eql(u8, path, route))
            return true;
    }
    return false;
}

pub const AuthState = struct {
    username: ?[]const u8 = null,
    is_authenticated: bool = false,
};
