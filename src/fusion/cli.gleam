import filepath
import fusion/build
import fusion/config
import fusion/date
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/string
import glint
import simplifile
import spaceship_toml

@external(erlang, "dev_ffi", "run_command_in")
fn run_command_in(
  cmd: String,
  args: List(String),
  cwd: String,
) -> Result(String, String)

pub fn build_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("Build the project")
  use _, _, _ <- glint.command()
  build.do_build(build.find_project_root())
}

pub fn scan_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("Scan class files and cache metadata")
  use _, _, _ <- glint.command()
  build.do_scan(build.find_project_root())
}

pub fn init_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("Initialize a new fusion project")
  use cloudflare <- glint.flag(
    glint.bool_flag("cloudflare")
    |> glint.flag_help("Target Cloudflare Workers runtime")
    |> glint.flag_default(False),
  )
  use wrangler <- glint.flag(
    glint.string_flag("wrangler")
    |> glint.flag_help("Wrangler version (cloudflare only)")
    |> glint.flag_default("latest"),
  )
  use _, _, flags <- glint.command()
  let assert Ok(cloudflare_val) = cloudflare(flags)
  let assert Ok(wrangler_val) = wrangler(flags)
  do_init(cloudflare_val, wrangler_val)
}

fn do_init(cloudflare: Bool, wrangler: String) {
  io.println("═══ fusion init ═══\n")
  io.println("Target: " <> cloudflare_name(cloudflare))
  io.println("Wrangler: " <> wrangler)

  // Read gleam.toml
  let assert Ok(content) = simplifile.read("gleam.toml")

  // Parse toml
  let assert Ok(doc) = spaceship_toml.parse(content)

  // Get runtime value
  let runtime = case cloudflare {
    True -> "cloudflare"
    False -> "node"
  }

  // Check if [fusion] section exists
  let doc = case spaceship_toml.get_table(doc, ["fusion"]) {
    Ok(_) -> {
      // Section exists, update runtime
      let assert Ok(doc) =
        spaceship_toml.set(
          doc,
          ["fusion", "runtime"],
          spaceship_toml.string(runtime),
          None,
        )
      doc
    }
    Error(_) -> {
      // Section doesn't exist, add it
      let assert Ok(doc) = spaceship_toml.add_table(doc, ["fusion"], None)
      let assert Ok(doc) =
        spaceship_toml.set(
          doc,
          ["fusion", "runtime"],
          spaceship_toml.string(runtime),
          None,
        )
      let assert Ok(doc) =
        spaceship_toml.set(
          doc,
          ["fusion", "entry_point"],
          spaceship_toml.string("main"),
          None,
        )
      let assert Ok(doc) =
        spaceship_toml.set(
          doc,
          ["fusion", "port"],
          spaceship_toml.integer(8080),
          None,
        )
      let assert Ok(doc) =
        spaceship_toml.set(
          doc,
          ["fusion", "minify"],
          spaceship_toml.boolean(False),
          None,
        )
      let assert Ok(doc) =
        spaceship_toml.set(
          doc,
          ["fusion", "source_map"],
          spaceship_toml.boolean(True),
          None,
        )
      doc
    }
  }

  // Write updated toml
  let output = spaceship_toml.to_string(doc)
  let assert Ok(Nil) = simplifile.write("gleam.toml", output)

  io.println("\nUpdated gleam.toml with [fusion] section")

  // Generate wrangler.toml for cloudflare
  case cloudflare {
    True -> {
      let assert Ok(Nil) =
        simplifile.write("wrangler.toml", generate_wrangler_toml(wrangler))
      io.println("Generated wrangler.toml")
    }
    False -> Nil
  }

  io.println("\n═══ Done ═══")
}

fn cloudflare_name(cloudflare: Bool) -> String {
  case cloudflare {
    True -> "cloudflare"
    False -> "node"
  }
}

fn generate_wrangler_toml(wrangler: String) -> String {
  let version = case wrangler {
    "latest" -> "3"
    v -> v
  }

  let assert Ok(doc) = spaceship_toml.parse("")
  let assert Ok(doc) =
    spaceship_toml.set(doc, ["name"], spaceship_toml.string("app"), None)
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["main"],
      spaceship_toml.string("build/dist/index.js"),
      None,
    )
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["compatibility_date"],
      spaceship_toml.string(date.today()),
      None,
    )
  let assert Ok(doc) =
    spaceship_toml.set(doc, ["wrangler"], spaceship_toml.string(version), None)
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["compatibility_flags"],
      spaceship_toml.array([spaceship_toml.string("nodejs_compat")]),
      None,
    )
  // D1 database binding
  let assert Ok(doc) =
    spaceship_toml.add_array_of_tables(doc, ["d1_databases"], None)
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["d1_databases", "binding"],
      spaceship_toml.string("DB"),
      None,
    )
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["d1_databases", "database_name"],
      spaceship_toml.string("notes-db"),
      None,
    )
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["d1_databases", "database_id"],
      spaceship_toml.string("placeholder"),
      None,
    )
  // Assets binding
  let assert Ok(doc) = spaceship_toml.add_table(doc, ["assets"], None)
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["assets", "directory"],
      spaceship_toml.string("public"),
      None,
    )
  let assert Ok(doc) =
    spaceship_toml.set(
      doc,
      ["assets", "binding"],
      spaceship_toml.string("ASSETS"),
      None,
    )

  spaceship_toml.to_string(doc)
}

pub fn class_create_cmd() -> glint.Command(Nil) {
  use get_name <- glint.named_arg("name")
  use <- glint.command_help("Create a new class file")
  use named, _, _ <- glint.command()
  let name = get_name(named)
  do_class_create(name)
}

fn do_class_create(name: String) {
  io.println("═══ fusion class create ═══\n")
  let dir = "src/classes"
  let path = dir <> "/" <> name <> ".gleam"

  // Create directory if it doesn't exist
  let _ = simplifile.create_directory_all(dir)

  let content = class_template(name)
  case simplifile.write(path, content) {
    Ok(Nil) -> {
      io.println("Created: " <> path)
      io.println("\n═══ Done ═══")
    }
    Error(_) -> {
      io.println_error("Error: Could not write to " <> path)
    }
  }
}

fn class_template(name: String) -> String {
  let display_name = snake_to_pascal(name)
  "/// @name "
  <> display_name
  <> "\n/// @export\npub fn "
  <> name
  <> "_fn() -> String {\n  \"Hello from "
  <> display_name
  <> "\"\n}\n"
}

fn snake_to_pascal(name: String) -> String {
  string.split(name, "_")
  |> list.map(capitalize)
  |> string.join("")
}

fn capitalize(s: String) -> String {
  case string.starts_with(s, "_") {
    True -> {
      let rest = string.slice(s, 1, string.length(s) - 1)
      string.uppercase(rest)
    }
    False -> {
      let first = string.slice(s, 0, 1)
      let rest = string.slice(s, 1, string.length(s) - 1)
      string.uppercase(first) <> rest
    }
  }
}

pub fn class_list_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("List all class files")
  use _, _, _ <- glint.command()
  do_class_list()
}

fn do_class_list() {
  io.println("═══ fusion class list ═══\n")
  let root = build.find_project_root()
  case build.do_scan(root) {
    _ -> io.println("\n═══ Done ═══")
  }
}

pub fn dev_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("Start development mode with file watching")
  use _, _, _ <- glint.command()
  do_dev()
}

fn do_dev() {
  io.println("═══ fusion dev ═══\n")
  io.println("Starting development server...\n")

  // First, do a build
  let root = build.find_project_root()
  build.do_build(root)

  // Then start file watcher and run server
  io.println("\nWatching for changes...\n")

  // Read config to get runtime and port
  let config = config.read_fusion_config(root)
  let port = config.port

  case config.runtime {
    "node" -> {
      io.println(
        "Starting Node.js server on port " <> int.to_string(port) <> "...\n",
      )
      // Run node with the built shim
      let shim_path = filepath.join(root, "build/fusion/shim.js")
      case run_command_in("node", [shim_path], root) {
        Ok(output) -> io.println(output)
        Error(e) -> io.println_error("Server error: " <> e)
      }
    }
    "cloudflare" -> {
      io.println("Starting Wrangler dev server...\n")
      // Run wrangler dev for Cloudflare Workers
      case run_command_in("npx", ["wrangler", "dev"], root) {
        Ok(output) -> io.println(output)
        Error(e) -> io.println_error("Wrangler error: " <> e)
      }
    }
    runtime -> {
      io.println_error("Runtime '" <> runtime <> "' not supported for dev mode")
      io.println("Supported runtimes: node, cloudflare")
    }
  }

  io.println("\n═══ Done ═══")
}
