const std = @import("std");
const zx = @import("zx");

/// Runs before every page and route
pub fn Proxy(ctx: *zx.ProxyContext) !void {
    const session = ctx.request.cookies.get("session");

    ctx.state(AuthState{
        .username = session,
        .is_authenticated = session != null,
    });

    // Handle protected routes if any
    if (isProtectedRoute(ctx.request.pathname) and session == null) {
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
