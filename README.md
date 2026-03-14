# Ziex App - Hacker News Clone

>This is minimal hackernews clone built with [Ziex](https://ziex.dev). 


Here are the features implemented in this clone:
- [x] Home page with stories
- [x] Story details page with comments
- [x] User profile page
- [x] Login/logout functionality

## Usage

### Development
```bash
zig build dev
```
App will be available at [`http://localhost:3000`](http://localhost:3000). with hot reload enabled.

### Serve Production Build
```bash
zig build serve --release=fast
```

### Exporting as Static Site
```bash
zig build zx -- export
```
This will create a `dist/` directory with the static export of your app. You can deploy the contents of `dist/` to any static hosting provider (Netlify, Vercel, GitHub Pages, etc) or serve it with any static file server.

### Deployment

```bash
zig build zx -- bundle
```

This will create a `bundle/` directory with the binary and static assets needed to run your app. You can deploy the contents of `bundle/` to any VPS.


### [ZX CLI](https://ziex.dev/reference#cli) Commands
```bash
zig build zx -- [command] [options]
```

All ZX CLI commands are available under `zig build zx -- [command]`. For example, to run auto formatter:
```bash
zig build zx -- fmt .
```

## Contributing

Contributions are welcome! Feel free to open issues or pull requests. For feature requests, bug reports, or questions, see the [Ziex Repo](https://github.com/ziex-dev/ziex).

## Links

- [Documentation](https://ziex.dev)
- [Discord](https://ziex.dev/r/discord)
- [Topic on Ziggit](https://ziex.dev/r/ziggit)
- [Project on Zig Discord Community](https://ziex.dev/r/zig-discord) (Join Zig Discord first: https://discord.gg/zig)
- [GitHub](https://github.com/nurulhudaapon/ziex)
- [Zig Language](https://ziglang.org/)