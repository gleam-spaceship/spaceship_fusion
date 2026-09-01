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

  let class_imports =
    list.filter_map(classes, fn(class) {
      case class.should_export {
        True -> {
          // source_file is like "classes/worker", we need just "worker"
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
      "    return " <> entry_point <> "(req, env, ctx);",
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
    string.join(class_imports, "\n"),
    default_export,
    named_exports,
  ]
  sections
  |> list.filter(fn(s) { s != "" })
  |> string.join("\n\n")
}

fn node_shim(package_name: String, entry_point: String) -> String {
  "import http from \"node:http\";
import fs from \"node:fs/promises\";
import { Get, Post, Put, Delete, Patch, Head, Options } from \"../dev/javascript/gleam_http/gleam/http.mjs\";
import { BitArray } from \"../dev/javascript/prelude.mjs\";
import { " <> entry_point <> " } from \"../dev/javascript/" <> package_name <> "/" <> package_name <> ".mjs\";

const METHOD_MAP = { GET: Get, POST: Post, PUT: Put, DELETE: Delete, PATCH: Patch, HEAD: Head, OPTIONS: Options };

function toGleamMethod(method) {
  const C = METHOD_MAP[method];
  if (C) return new C();
  return { tag: \"Other\", 0: method };
}

function gleamList(arr) {
  let list = { head: undefined, tail: undefined };
  for (let i = arr.length - 1; i >= 0; i--) {
    list = { head: arr[i], tail: list };
  }
  return list;
}

function gleamHeaders(req) {
  const headers = [];
  for (const [key, value] of Object.entries(req.headers)) {
    headers.push([key, value]);
  }
  return gleamList(headers);
}

async function serveStatic(pathname, res) {
  if (!pathname.startsWith(\"/assets/\")) return false;

  const relative = pathname.slice(\"/assets/\".length);
  if (relative === \"\" || relative.includes(\"..\")) {
    res.writeHead(404);
    res.end(\"Not Found\");
    return true;
  }

  try {
    const file = await fs.readFile(new URL(\"../static/\" + relative, import.meta.url));
    const contentType = relative.endsWith(\".js\")
      ? \"application/javascript; charset=utf-8\"
      : relative.endsWith(\".css\")
        ? \"text/css; charset=utf-8\"
        : relative.endsWith(\".map\")
          ? \"application/json; charset=utf-8\"
          : \"application/octet-stream\";
    res.writeHead(200, { \"content-type\": contentType });
    res.end(file);
    return true;
  } catch (_) {
    return false;
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, \"http://localhost\");
  if (await serveStatic(url.pathname, res)) return;

  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = new Uint8Array(Buffer.concat(chunks));

  const path = url.pathname;
  const query = url.search ? url.search.substring(1) : \"\";

  const gleamReq = {
    method: toGleamMethod(req.method),
    headers: gleamHeaders(req),
    path: path,
    query: query,
    body: new BitArray(body),
  };

  try {
    const response = " <> entry_point <> "(gleamReq);
    const respHeaders = {};
    let h = response.headers;
    while (h && h.head) {
      const [k, v] = h.head;
      respHeaders[k] = v;
      h = h.tail;
    }
    res.writeHead(response.status, respHeaders);
    res.end(Buffer.from(response.body.buffer || response.body));
  } catch (e) {
    console.error(e);
    res.writeHead(500);
    res.end(\"Internal Server Error\");
  }
});

server.listen(3000, () => console.log(\"Server running on http://localhost:3000\"));"
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
    "",
    "Bun.serve({ port: 3000, fetch: " <> entry_point <> " });",
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
    "",
    "Deno.serve({ port: 3000 }, " <> entry_point <> ");",
  ]
  |> string.join("\n")
}
