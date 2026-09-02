import filepath
import fusion/codegen
import fusion/config
import fusion/shim
import fusion/types.{type ClassDef, type FusionConfig}
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

@external(erlang, "dev_ffi", "run_command_in")
fn run_command_in(
  cmd: String,
  args: List(String),
  cwd: String,
) -> Result(String, String)

pub fn do_build(root: String) {
  io.println("═══ fusion build ═══\n")

  // Step 1: Scan and cache metadata
  io.println("1. Scanning src/classes/ for class .gleam files...")
  case config.scan_class_files(root) {
    Error(e) -> {
      io.println_error("   Error: " <> e)
      Nil
    }
    Ok(classes) -> {
      io.println(
        "   Found " <> int.to_string(list.length(classes)) <> " class(es)",
      )

      // Cache metadata
      case config.generate_metadata(root) {
        Error(e) -> io.println_error("   Error: " <> e)
        Ok(_) -> io.println("   Saved to .spaceship/fusion/classes.json")
      }

      // Read fusion config from gleam.toml
      let fusion_config = config.read_fusion_config(root)
      let fusion_config = types.FusionConfig(..fusion_config, classes:)

      // Step 2: Run gleam build
      io.println("\n2. Running gleam build...")
      case run_command_in("gleam", ["build", "--target", "javascript"], root) {
        Error(e) -> io.println_error("   Failed: " <> e)
        Ok(_) -> io.println("   Done")
      }

      // Step 3: Transform compiled JS → class files
      io.println("\n3. Generating class files...")
      case config.read_package_name(root) {
        Error(e) -> io.println_error("   Error: " <> e)
        Ok(package_name) -> {
          let build_dir = filepath.join(root, "build/dev/javascript")
          let fusion_dir = filepath.join(root, "build/fusion/classes")
          let _ = simplifile.create_directory_all(fusion_dir)
          generate_class_files(classes, build_dir, package_name, fusion_dir)

          // Step 4: Generate shim.js
          io.println("\n4. Generating shim.js...")
          case shim.generate_shim(root, fusion_config, package_name) {
            Error(e) -> io.println_error("   Error: " <> e)
            Ok(_) -> io.println("   Done")
          }

          // Step 5: Copy assets and embed includes
          io.println("\n5. Processing assets...")
          process_assets(root, fusion_config)

          // Step 6: Bundle with esbuild
          io.println("\n6. Bundling with esbuild...")
          let shim_path = filepath.join(root, "build/fusion/shim.js")
          let outdir = filepath.join(root, "build/dist")
          let _ = simplifile.create_directory_all(outdir)

          let minify_flag = case fusion_config.minify {
            True -> "--minify"
            False -> ""
          }
          let sourcemap_flag = case fusion_config.source_map {
            True -> "--sourcemap=linked"
            False -> ""
          }

          // External imports that shouldn't be bundled
          let externals = [
            "--external:cloudflare:*",
            "--external:node:*",
          ]
          let esbuild_args =
            [
              "esbuild",
              shim_path,
              "--bundle",
              "--format=esm",
              "--outfile=" <> filepath.join(outdir, "index.js"),
              minify_flag,
              sourcemap_flag,
            ]
            |> list.append(externals)
          case run_command_in("npx", esbuild_args, root) {
            Error(e) -> io.println_error("   Failed: " <> e)
            Ok(_) -> io.println("   → build/dist/index.js")
          }
        }
      }
    }
  }

  io.println("\n═══ Done ═══")
}

fn generate_class_files(
  classes: List(ClassDef),
  build_dir: String,
  package_name: String,
  fusion_dir: String,
) {
  case classes {
    [] -> io.println("   No classes to generate")
    _ -> do_generate_classes(classes, build_dir, package_name, fusion_dir)
  }
}

fn do_generate_classes(
  classes: List(ClassDef),
  build_dir: String,
  package_name: String,
  fusion_dir: String,
) {
  case classes {
    [] -> Nil
    [class, ..rest] -> {
      case codegen.transform_class(class, build_dir, package_name) {
        Error(e) ->
          io.println_error("   Error generating " <> class.name <> ": " <> e)
        Ok(js_content) -> {
          // source_file is like "classes/worker", fusion_dir ends with "classes"
          // So we need just the filename part
          let filename = case string.split(class.source_file, "/") {
            [] -> class.source_file
            parts -> {
              let last = list.last(parts) |> result.unwrap(class.source_file)
              last
            }
          }
          let out_path = filepath.join(fusion_dir, filename <> ".mjs")
          let _ = simplifile.write(out_path, js_content)
          io.println("   " <> class.name <> ".mjs")
        }
      }
      do_generate_classes(rest, build_dir, package_name, fusion_dir)
    }
  }
}

// ── Asset Processing ──────────────────────────────────────────

/// Process assets based on fusion config.
/// For non-Cloudflare runtimes: copy assets directory and includes to dist.
/// For Cloudflare: copy assets directory to dist (for Wrangler [site]),
/// and embed includes into assets.mjs.
fn process_assets(root: String, config: FusionConfig) {
  let outdir = filepath.join(root, "build/dist")
  let is_cloudflare = config.runtime == "cloudflare"

  // Copy public assets directory
  let assets_dir = config.assets.directory
  let assets_src = filepath.join(root, assets_dir)
  let assets_dst = filepath.join(outdir, assets_dir)
  case simplifile.is_directory(assets_src) {
    Ok(True) -> {
      copy_directory(assets_src, assets_dst)
      io.println("   Copied " <> assets_dir <> "/ to dist/")
    }
    _ -> io.println("   No " <> assets_dir <> "/ directory found, skipping")
  }

  // Handle includes
  case config.assets.includes {
    [] -> io.println("   No includes to embed")
    includes -> {
      case is_cloudflare {
        True -> {
          // Cloudflare: embed as base64 in assets.mjs
          embed_includes_for_cloudflare(root, outdir, includes)
        }
        False -> {
          // Other runtimes: copy files to dist
          copy_includes_to_dist(root, outdir, includes)
        }
      }
    }
  }
}

/// Copy a directory recursively
fn copy_directory(src: String, dst: String) {
  let _ = simplifile.create_directory_all(dst)
  case simplifile.read_directory(src) {
    Ok(entries) -> {
      list.each(entries, fn(entry) {
        let src_path = filepath.join(src, entry)
        let dst_path = filepath.join(dst, entry)
        case simplifile.is_directory(src_path) {
          Ok(True) -> copy_directory(src_path, dst_path)
          _ -> {
            case simplifile.read_bits(src_path) {
              Ok(content) -> {
                let _ = simplifile.write_bits(dst_path, content)
                Nil
              }
              Error(_) -> Nil
            }
          }
        }
      })
    }
    Error(_) -> Nil
  }
}

/// Copy includes files to dist directory (for non-Cloudflare runtimes)
fn copy_includes_to_dist(root: String, outdir: String, includes: List(String)) {
  list.each(includes, fn(path) {
    let src = filepath.join(root, path)
    let dst = filepath.join(outdir, path)
    // Get directory part by splitting on path separator
    let dst_dir = case string.split(dst, "/") {
      [] -> dst
      parts -> {
        let without_last = list.take(parts, list.length(parts) - 1)
        string.join(without_last, "/")
      }
    }
    let _ = simplifile.create_directory_all(dst_dir)
    case simplifile.read_bits(src) {
      Ok(content) -> {
        let _ = simplifile.write_bits(dst, content)
        io.println("   Copied " <> path)
      }
      Error(_) -> io.println_error("   Warning: Could not read " <> path)
    }
  })
}

/// Embed includes as base64 in assets.mjs (for Cloudflare Workers)
fn embed_includes_for_cloudflare(
  root: String,
  outdir: String,
  includes: List(String),
) {
  let entries =
    list.map(includes, fn(path) {
      let src = filepath.join(root, path)
      case simplifile.read_bits(src) {
        Ok(content) -> {
          let base64 = encode_base64(content)
          io.println(
            "   Embedded "
            <> path
            <> " ("
            <> int.to_string(bit_array.byte_size(content))
            <> " bytes)",
          )
          Ok(#(path, base64))
        }
        Error(_) -> {
          io.println_error("   Warning: Could not read " <> path)
          Error(Nil)
        }
      }
    })

  let valid_entries = list.filter_map(entries, fn(e) { e })

  case valid_entries {
    [] -> io.println("   No valid includes to embed")
    _ -> {
      let js = generate_assets_js(valid_entries)
      let out_path = filepath.join(outdir, "assets.mjs")
      case simplifile.write(out_path, js) {
        Ok(_) -> io.println("   Generated assets.mjs with embedded files")
        Error(_) -> io.println_error("   Failed to write assets.mjs")
      }
    }
  }
}

/// Generate JavaScript module with embedded base64 assets
fn generate_assets_js(entries: List(#(String, String))) -> String {
  let exports =
    list.map(entries, fn(entry) {
      let #(path, base64) = entry
      "  \"" <> path <> "\": \"" <> base64 <> "\""
    })
    |> string.join(",\n")

  "// Auto-generated by fusion build - do not edit\n"
  <> "const assets = {\n"
  <> exports
  <> "\n};\n\n"
  <> "export function getAsset(path) {\n"
  <> "  const b64 = assets[path];\n"
  <> "  if (b64 === undefined) return null;\n"
  <> "  const binary = atob(b64);\n"
  <> "  const bytes = new Uint8Array(binary.length);\n"
  <> "  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);\n"
  <> "  return bytes;\n"
  <> "}\n\n"
  <> "export function getAssetString(path) {\n"
  <> "  const bytes = getAsset(path);\n"
  <> "  return bytes ? new TextDecoder().decode(bytes) : null;\n"
  <> "}\n"
}

/// Encode bytes to base64
fn encode_base64(data: BitArray) -> String {
  do_encode_base64(data)
}

@external(erlang, "dev_ffi", "encode_base64")
@external(javascript, "./dev_ffi.mjs", "encodeBase64")
fn do_encode_base64(data: BitArray) -> String

pub fn do_scan(root: String) {
  case config.scan_class_files(root) {
    Error(e) -> io.println_error("Error: " <> e)
    Ok(classes) -> {
      io.println(
        "Found " <> int.to_string(list.length(classes)) <> " class(es)",
      )
      print_classes(classes)
    }
  }
}

fn print_classes(classes: List(ClassDef)) {
  case classes {
    [] -> Nil
    [class, ..rest] -> {
      io.println("  " <> class.name <> " (" <> class.source_file <> ")")
      print_methods(class.methods)
      print_classes(rest)
    }
  }
}

fn print_methods(methods: List(types.Method)) {
  case methods {
    [] -> Nil
    [m, ..rest] -> {
      let async_str = case m.is_async {
        True -> "async "
        False -> ""
      }
      io.println(
        "    "
        <> async_str
        <> "."
        <> m.name
        <> "("
        <> string.join(m.params, ", ")
        <> ")",
      )
      print_methods(rest)
    }
  }
}

pub fn find_project_root() -> String {
  do_find_root(".")
}

fn do_find_root(path: String) -> String {
  let toml_path = filepath.join(path, "gleam.toml")
  case simplifile.is_file(toml_path) {
    Ok(True) -> path
    _ -> do_find_root(filepath.join(path, ".."))
  }
}
