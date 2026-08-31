# spaceship_fusion

[![Package Version](https://img.shields.io/hexpm/v/spaceship_fusion)](https://hex.pm/packages/spaceship_fusion)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://spaceship-fusion.hexdocs.pm/)

A build tool for Gleam projects that generates platform-specific shims, compiles class files, and bundles with esbuild.

## Features

- Scan `.gleam` class files with annotations
- Generate platform-specific runtime shims (Node, Cloudflare, Bun, Deno)
- Bundle with esbuild with source map support
- Configurable entry point function
- Generate `wrangler.toml` for Cloudflare Workers

## Usage

```sh
gleam add spaceship_fusion
```

### Build a project

```sh
gleam run -m fusion -- build
```

### Scan class files

```sh
gleam run -m fusion -- scan
```

## Configuration

Add a `[fusion]` section to your `gleam.toml`:

```toml
[fusion]
runtime = "cloudflare"  # or "node", "bun", "deno"
entry_point = "main"    # function to call as entry point
port = 3000
minify = true
source_map = true
```

### Entry Point

The entry point function is called by the generated shim. The function signature depends on the runtime:

**Web server (all runtimes):**
```gleam
pub fn main(req: Request(BitArray)) -> Response(BitArray) {
  // handle HTTP request
}
```

**Cloudflare Workers (with env/ctx):**
```gleam
pub fn main(req: Request(BitArray), env: Dynamic, ctx: Dynamic) -> Response(BitArray) {
  // access env vars and context
}
```

### Class Files

Place `.gleam` files in `src/classes/` with annotations:

```gleam
/// @extends Service
/// @name MyService
/// @export
pub fn handle_message(msg: String) -> String {
  // ...
}
```

## Build Output

```
build/
  fusion/
    classes/           # Generated class adapters
    shim.js            # Platform-specific entry point
  dist/
    index.js           # esbundle output
    index.js.map       # Source map
  static/              # Static assets (CSS, etc.)
```

## Runtime Shims

| Runtime | Entry Point Signature | Notes |
|---|---|---|
| `cloudflare` | `main(req, env, ctx)` | Generates wrangler.toml |
| `node` | `main(req)` | HTTP server with static files |
| `bun` | `main(req)` | Bun.serve wrapper |
| `deno` | `main(req)` | Deno.serve wrapper |

## Development

```sh
gleam build   # Build the project
gleam test    # Run the tests
```
