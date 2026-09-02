# spaceship_fusion

[![Package Version](https://img.shields.io/hexpm/v/spaceship_fusion)](https://hex.pm/packages/spaceship_fusion)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://spaceship-fusion.hexdocs.pm/)

A build tool for Gleam projects that generates platform-specific shims, compiles class files, and bundles with esbuild.

## Features

- Scan `.gleam` class files with annotations
- Generate platform-specific runtime shims (Node, Cloudflare, Bun, Deno)
- Bundle with esbuild with source map support
- Configurable entry point function
- Static asset handling (copy to dist, embed for Cloudflare)
- Generate `wrangler.toml` for Cloudflare Workers
- Initialize projects with `fusion init`

## Installation

```sh
gleam add spaceship_fusion
```

## CLI Commands

### `fusion init`

Initialize a new project for fusion.

```bash
# Basic (Node runtime)
gleam run -m fusion -- init

# Cloudflare
gleam run -m fusion -- init --cloudflare

# Cloudflare with specific wrangler version
gleam run -m fusion -- init --cloudflare --wrangler=2
```

**What it does:**
1. Edits `gleam.toml` with `[fusion]` section
2. For `--cloudflare`: generates `wrangler.toml` with D1 binding

**Flags:**
| Flag | Description | Default |
|---|---|---|
| `--cloudflare` | Target Cloudflare Workers | `false` |
| `--wrangler=<ver>` | Wrangler version (cloudflare only) | `"latest"` |

### `fusion build`

Build the project.

```sh
gleam run -m fusion -- build
```

**What it does:**
1. Scans `src/classes/` for class `.gleam` files
2. Runs `gleam build --target javascript`
3. Generates class adapter files in `build/fusion/classes/`
4. Generates platform-specific `shim.js`
5. Processes static assets:
   - Copies `directory` to `build/dist/` (non-Cloudflare)
   - Embeds `includes` as base64 in `assets.mjs` (Cloudflare)
6. Bundles with esbuild to `build/dist/index.js`

### `fusion scan`

Scan class files and display metadata.

```sh
gleam run -m fusion -- scan
```

### `fusion dev`

Start development mode with file watching.

```sh
gleam run -m fusion -- dev
```

**What it does:**
1. Runs full build
2. Starts appropriate server based on runtime:
   - `node` → runs `node build/fusion/shim.js`
   - `cloudflare` → runs `npx wrangler dev`

### `fusion class create <name>`

Create a new class file.

```bash
gleam run -m fusion -- class create "greeter"
```

**What it does:**
1. Creates `src/classes/` if it doesn't exist
2. Creates `src/classes/<name>.gleam` with template

### `fusion class list`

List all class files.

```sh
gleam run -m fusion -- class list
```

**Output:**
```
Found 1 class(es)
  Greeter (classes/greeter)
    .greet(message: String)
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

[fusion.assets]
directory = "public"                    # Public assets to serve
includes = ["priv/secret.cert"]         # Files to embed in bundle
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

### Assets

Configure static assets in `gleam.toml`:

```toml
[fusion.assets]
# Public directory - served as static files
directory = "public"

# Private files - embedded in bundle for Cloudflare
includes = ["priv/cert.pem", "priv/config.json"]
```

**Build behavior:**

| Runtime | `directory` | `includes` |
|---|---|---|
| Node/Bun/Deno | Copied to `dist/` | Copied to `dist/` |
| Cloudflare | Copied for `[site]` | Embedded as base64 in `assets.mjs` |

**Reading assets in code:**

```gleam
import fusion/asset

// Read asset as bytes
let assert Ok(cert) = asset.read("priv/cert.pem")

// Read asset as string
let assert Ok(config) = asset.read_string("priv/config.json")
```

On Cloudflare, embedded assets are loaded from the bundle. On other runtimes, assets are read from the filesystem.

## Build Output

```
build/
  fusion/
    classes/           # Generated class adapters
    shim.js            # Platform-specific entry point
    assets.mjs         # Embedded assets (Cloudflare only)
  dist/
    index.js           # esbuild output
    index.js.map       # Source map
    public/            # Copied public assets
    priv/              # Copied private assets (non-Cloudflare)
```

## Runtime Shims

| Runtime | Entry Point Signature | Notes |
|---|---|---|
| `cloudflare` | `main(req, env, ctx)` | Generates wrangler.toml |
| `node` | `main(req)` | HTTP server with static files |
| `bun` | `main(req)` | Bun.serve wrapper |
| `deno` | `main(req)` | Deno.serve wrapper |

## Examples

### Basic Web Server (Node)

```toml
# gleam.toml
[fusion]
runtime = "node"
entry_point = "main"
port = 3000
```

```gleam
// src/app.gleam
import gleam/http/request.{type Request}
import gleam/http/response

pub fn main(req: Request(BitArray)) -> response.Response(BitArray) {
  response.new(200)
  |> response.set_body(<<"Hello from Fusion!":utf8>>)
}
```

### Cloudflare Worker with Assets

```toml
# gleam.toml
[fusion]
runtime = "cloudflare"
entry_point = "main"

[fusion.assets]
directory = "public"
includes = ["priv/api-key.txt"]
```

```gleam
// src/app.gleam
import fusion/asset

pub fn main(req, env, ctx) {
  // Read embedded asset
  let assert Ok(api_key) = asset.read_string("priv/api-key.txt")
  
  response.new(200)
  |> response.set_body(<<"Hello!":utf8>>)
}
```

## Development

```sh
gleam build   # Build the project
gleam test    # Run the tests
gleam format  # Format the code
```

## License

Apache-2.0
