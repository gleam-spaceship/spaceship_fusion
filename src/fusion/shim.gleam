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

  let content = case config.runtime {
    "cloudflare" ->
      cloudflare_shim(package_name, config.entry_point, config.classes)
    "node" -> node_shim(package_name, config.entry_point)
    "bun" -> bun_shim(package_name, config.entry_point)
    "deno" -> deno_shim(package_name, config.entry_point)
    _ -> cloudflare_shim(package_name, config.entry_point, config.classes)
  }

  simplifile.write(shim_path, content)
  |> result.map_error(fn(_) { "Failed to write shim.js" })
}

fn adapter_import(runtime: String) -> String {
  [
    "import { toGleamRequest, toPlatformResponse } from \"../dev/javascript/spaceship_helm/spaceship_helm/ffi/runtimes/",
    runtime,
    ".mjs\";",
  ]
  |> string.join("")
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

  let adapter_import = adapter_import("cloudflare")

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
      "    const gleamReq = await toGleamRequest(req);",
      "    const resp = await " <> entry_point <> "(gleamReq, env, ctx);",
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
    adapter_import("node"),
    "",
    "const server = http.createServer(async (req, res) => {",
    "  const gleamReq = await toGleamRequest(req);",
    "  const resp = await " <> entry_point <> "(gleamReq, null, null);",
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
    adapter_import("bun"),
    "",
    "Bun.serve({",
    "  port: 3000,",
    "  async fetch(req) {",
    "    const gleamReq = await toGleamRequest(req);",
    "    const resp = await " <> entry_point <> "(gleamReq, null, null);",
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
    adapter_import("deno"),
    "",
    "Deno.serve({ port: 3000 }, async (req) => {",
    "  const gleamReq = await toGleamRequest(req);",
    "  const resp = await " <> entry_point <> "(gleamReq, null, null);",
    "  return toPlatformResponse(resp);",
    "});",
  ]
  |> string.join("\n")
}
