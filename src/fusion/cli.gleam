import fusion/build
import gleam/io
import gleam/list
import gleam/string
import glint
import simplifile

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
  // TODO: Edit gleam.toml
  // TODO: Generate wrangler.toml for cloudflare
  io.println("\n═══ Done ═══")
}

fn cloudflare_name(cloudflare: Bool) -> String {
  case cloudflare {
    True -> "cloudflare"
    False -> "node"
  }
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
  // TODO: Parse classes from src/classes/
  io.println("No classes found.")
  io.println("\n═══ Done ═══")
}

pub fn dev_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("Start development mode with file watching")
  use _, _, _ <- glint.command()
  do_dev()
}

fn do_dev() {
  io.println("═══ fusion dev ═══\n")
  io.println("Development mode not yet implemented.")
  io.println("\n═══ Done ═══")
}
