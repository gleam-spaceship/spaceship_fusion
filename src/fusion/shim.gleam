import filepath
import fusion/types.{type ClassDef, type FusionConfig}
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// Generate shim.js based on runtime config.
pub fn generate_shim(
  project_root: String,
  config: FusionConfig,
  package_name: String,
) -> Result(Nil, String) {
  let shim_dir = filepath.join(project_root, "build/fusion")
  let _ = simplifile.create_directory_all(shim_dir)
  let shim_path = filepath.join(shim_dir, "shim.js")

  // Copy adapter to build output with corrected paths
  let _ = copy_adapter(project_root, config.runtime)

  let content = case config.runtime {
    "cloudflare" -> {
      let _ = generate_wrangler_toml(project_root, package_name)
      cloudflare_shim(package_name, config.entry_point, config.classes)
    }
    "node" -> node_shim(package_name, config.entry_point)
    "bun" -> bun_shim(package_name, config.entry_point)
    "deno" -> deno_shim(package_name, config.entry_point)
    _ -> cloudflare_shim(package_name, config.entry_point, config.classes)
  }

  simplifile.write(shim_path, content)
  |> result.map_error(fn(_) { "Failed to write shim.js" })
}

/// Copy adapter.mjs from spaceship_helm to build output with corrected paths
fn copy_adapter(project_root: String, runtime: String) -> Result(Nil, String) {
  // Find spaceship_helm in workspace (look for sibling directory)
  let workspace_root = filepath.join(project_root, "../..")
  let adapter_src = filepath.join(workspace_root, "spaceship_helm/ffi/runtimes/" <> runtime <> ".mjs")
  let adapter_dst = filepath.join(project_root, "build/fusion/adapter.mjs")
  
  case simplifile.read(adapter_src) {
    Ok(content) -> {
      // Fix import paths to be relative to build/fusion/
      let fixed_content = content
        |> string.replace(
          "../../dev/javascript/gleam_stdlib/gleam/option.mjs",
          "../dev/javascript/gleam_stdlib/gleam/option.mjs",
        )
        |> string.replace(
          "../../dev/javascript/gleam_http/gleam/http.mjs",
          "../dev/javascript/gleam_http/gleam/http.mjs",
        )
      let _ = simplifile.create_directory_all(filepath.join(project_root, "build/fusion"))
      simplifile.write(adapter_dst, fixed_content)
      |> result.map_error(fn(_) { "Failed to copy adapter" })
    }
    Error(_) -> {
      // Adapter not found, skip
      Ok(Nil)
    }
  }
}

/// Generate wrangler.toml for Cloudflare Workers.
fn generate_wrangler_toml(
  project_root: String,
  package_name: String,
) -> Result(Nil, String) {
  let toml_path = filepath.join(project_root, "wrangler.toml")
  let content =
    [
      "name = \"" <> package_name <> "\"",
      "main = \"build/dist/index.js\"",
      "compatibility_date = \"" <> get_compatibility_date() <> "\"",
      "[assets]",
      "directory = \"build/static\"",
      "binding = \"ASSETS\"",
    ]
    |> string.join("\n")

  simplifile.write(toml_path, content)
  |> result.map_error(fn(_) { "Failed to write wrangler.toml" })
}

/// Get current date for compatibility_date.
fn get_compatibility_date() -> String {
  // Use a fixed date for now, can be updated later
  "2024-01-01"
}

fn cloudflare_shim(
  package_name: String,
  entry_point: String,
  classes: List(ClassDef),
) -> String {
  let app_import =
    [
      "import { ",
      entry_point,
      " } from \"../dev/javascript/",
      package_name,
      "/",
      package_name,
      ".mjs\";",
    ]
    |> string.join("")

  let adapter_import = "import { toGleamRequest, toPlatformResponse } from \"./adapter.mjs\";"

  let class_imports =
    list.filter_map(classes, fn(class) {
      case class.should_export {
        True -> {
          let filename = case string.split(class.source_file, "/") {
            [] -> class.source_file
            parts -> list.last(parts) |> result.unwrap(class.source_file)
          }
          Ok(
            [
              "import { ",
              class.name,
              " } from \"./classes/",
              filename,
              ".mjs\";",
            ]
            |> string.join(""),
          )
        }
        False -> Error(Nil)
      }
    })

  let default_export =
    [
      "export default {",
      "  async fetch(req, env, ctx) {",
      "    globalThis.__env = env;",
      "    globalThis.__ctx = ctx;",
      "    const gleamReq = toGleamRequest(req);",
      "    const resp = " <> entry_point <> "(gleamReq, env, ctx);",
      "    return toPlatformResponse(resp);",
      "  }",
      "};",
    ]
    |> string.join("\n")

  let named_exports = case
    list.filter_map(classes, fn(class) {
      case class.should_export {
        True -> Ok(class.name)
        False -> Error(Nil)
      }
    })
  {
    [] -> ""
    names -> "export { " <> string.join(names, ", ") <> " };"
  }

  let sections = [
    app_import,
    adapter_import,
    string.join(class_imports, "\n"),
    default_export,
    named_exports,
  ]
  sections
  |> list.filter(fn(s) { s != "" })
  |> string.join("\n\n")
}

fn node_shim(package_name: String, entry_point: String) -> String {
  [
    "import http from \"node:http\";",
    "import { ",
    entry_point,
    " } from \"../dev/javascript/",
    package_name,
    "/",
    package_name,
    ".mjs\";",
    "import { toGleamRequest, toPlatformResponse } from \"./adapter.mjs\";",
    "",
    "const server = http.createServer((req, res) => {",
    "  const gleamReq = toGleamRequest(req);",
    "  const resp = " <> entry_point <> "(gleamReq, null, null);",
    "  toPlatformResponse(resp, res);",
    "});",
    "",
    "const port = process.env.PORT || 3000;",
    "server.listen(port, () => {",
    "  console.log(\"Server listening on http://localhost:\" + port);",
    "});",
  ]
  |> string.join("\n")
}

fn bun_shim(package_name: String, entry_point: String) -> String {
  [
    "import { ",
    entry_point,
    " } from \"../dev/javascript/",
    package_name,
    "/",
    package_name,
    ".mjs\";",
    "import { toGleamRequest, toPlatformResponse } from \"./adapter.mjs\";",
    "",
    "Bun.serve({",
    "  port: 3000,",
    "  async fetch(req) {",
    "    const gleamReq = toGleamRequest(req);",
    "    const resp = " <> entry_point <> "(gleamReq, null, null);",
    "    return toPlatformResponse(resp);",
    "  }",
    "});",
  ]
  |> string.join("\n")
}

fn deno_shim(package_name: String, entry_point: String) -> String {
  [
    "import { ",
    entry_point,
    " } from \"../dev/javascript/",
    package_name,
    "/",
    package_name,
    ".mjs\";",
    "import { toGleamRequest, toPlatformResponse } from \"./adapter.mjs\";",
    "",
    "Deno.serve({ port: 3000 }, async (req) => {",
    "  const gleamReq = toGleamRequest(req);",
    "  const resp = " <> entry_point <> "(gleamReq, null, null);",
    "  return toPlatformResponse(resp);",
    "});",
  ]
  |> string.join("\n")
}
