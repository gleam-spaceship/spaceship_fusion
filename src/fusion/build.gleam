import filepath
import fusion/codegen
import fusion/config
import fusion/shim
import fusion/types.{type ClassDef}
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

          // Step 5: Bundle with esbuild
          io.println("\n5. Bundling with esbuild...")
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
