# Fusion CLI Improvements

## Dependencies

```toml
gleam add glint
gleam add argv
```

## CLI Structure

```gleam
import glint
import argv

pub fn main() {
  glint.new()
  |> glint.with_name("fusion")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: build_cmd())  // default command
  |> glint.add(at: ["init"], do: init_cmd())
  |> glint.add(at: ["class", "create"], do: class_create_cmd())
  |> glint.add(at: ["class", "list"], do: class_list_cmd())
  |> glint.add(at: ["dev"], do: dev_cmd())
  |> glint.run(argv.load().arguments)
}
```

## Commands

### `fusion init`

Initialize a new project for fusion.

```bash
# Basic (Node runtime)
gleam run -m fusion init

# Cloudflare
gleam run -m fusion init --cloudflare

# Cloudflare with specific wrangler version
gleam run -m fusion init --cloudflare --wrangler=2
```

**What it does:**
1. Edits `gleam.toml`:
   - `target = "javascript"`
   - `[javascript] source_maps = true`
   - `[fusion]` section with runtime config
2. For `--cloudflare`:
   - Creates `wrangler.toml` with basic config
   - Adds `[fusion] wrangler_ver = "2"` (or specified version)

**Flags:**
| Flag | Description | Default |
|---|---|---|
| `--cloudflare` | Target Cloudflare Workers | `false` |
| `--bun` | Target Bun runtime | `false` |
| `--deno` | Target Deno runtime | `false` |
| `--wrangler=<ver>` | Wrangler version (cloudflare only) | `"latest"` |

---

### `fusion class create <name>`

Create a new class file.

```bash
gleam run -m fusion class create "greeter"
gleam run -m fusion class create "user_service"
```

**What it does:**
1. Creates `src/classes/` if it doesn't exist
2. Creates `src/classes/<name>.gleam`
3. Adds template with metadata comments:

```gleam
/// @name Greeter
/// @export
pub fn greet(name: String) -> String {
  "Hello, " <> name
}
```

---

### `fusion class list`

List all class files.

```bash
gleam run -m fusion class list
```

**Output:**
```
Classes:
  - greeter (src/classes/greeter.gleam)
    Methods: greet, farewell
  - user_service (src/classes/user_service.gleam)
    Methods: create_user, get_user
```

---

### `fusion dev`

Development mode with file watching and auto-rebuild.

```bash
gleam run -m fusion dev
```

**What it does:**
1. Reads `gleam.toml` for fusion config
2. Builds once
3. Starts file watcher on `src/`
4. Launches runtime in dev mode:
   - `runtime=node` → `node --watch build/dist/index.js`
   - `runtime=bun` → `bun --watch build/dist/index.js`
   - `runtime=deno` → `deno run --watch build/dist/index.js`
   - `runtime=cloudflare` → `npx wrangler@<version> dev`

**On file change:**
1. Stop current runtime
2. Rebuild
3. Restart runtime

---

## Implementation Plan

### Phase 1: `fusion init`

- [ ] Add `init` subcommand to fusion.gleam
- [ ] Parse gleam.toml
- [ ] Modify gleam.toml with required settings
- [ ] Generate wrangler.toml for cloudflare
- [ ] Add wrangler_ver to gleam.toml for cloudflare

### Phase 2: `fusion class`

- [ ] Add `class` subcommand with create/list
- [ ] Create class template
- [ ] Parse existing classes for listing
- [ ] Handle snake_case to PascalCase conversion

### Phase 3: `fusion dev`

- [ ] Add `dev` subcommand
- [ ] Implement file watcher (Erlang filesystem events)
- [ ] Add runtime-specific dev commands
- [ ] Handle process lifecycle (start/stop/restart)
- [ ] Add rebuild on change with debounce

---

## File Changes

| File | Change |
|---|---|
| `src/fusion.gleam` | Add subcommand routing for init, class, dev |
| `src/fusion/init.gleam` | New: init command logic |
| `src/fusion/class.gleam` | New: class create/list logic |
| `src/fusion/dev.gleam` | New: dev mode with file watcher |
| `src/fusion/watcher.gleam` | New: file system watcher |
| `src/fusion/toml.gleam` | New: gleam.toml parser/editor |
