import filepath
import fusion/parser
import fusion/types.{type ClassDef, type FusionConfig, type Method, FusionConfig}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

/// Scan src/classes/ for class .gleam files, parse them, and cache metadata.
pub fn generate_metadata(project_root: String) -> Result(Nil, String) {
  use classes <- result.try(scan_class_files(project_root))
  let config =
    FusionConfig(
      classes:,
      runtime: "cloudflare",
      entry_point: "main",
      port: 3000,
      minify: True,
      source_map: True,
    )
  let config_dir = filepath.join(project_root, ".spaceship/fusion")
  let _ = simplifile.create_directory_all(config_dir)
  let config_path = filepath.join(config_dir, "classes.json")
  let json_str = config_to_json(config)
  simplifile.write(config_path, json_str)
  |> result.map_error(fn(_) { "Failed to write classes.json" })
}

/// Scan src/classes/ for class .gleam files and parse them.
pub fn scan_class_files(
  project_root: String,
) -> Result(List(ClassDef), String) {
  let classes_dir = filepath.join(project_root, "src/classes")
  use files <- result.try(find_class_files(classes_dir))
  parse_all_class_files(files)
}

/// Read fusion config from gleam.toml [fusion] section.
pub fn read_fusion_config(project_root: String) -> FusionConfig {
  let toml_path = filepath.join(project_root, "gleam.toml")
  case simplifile.read(toml_path) {
    Ok(content) -> parse_fusion_section(content)
    Error(_) ->
      FusionConfig(
        classes: [],
        runtime: "cloudflare",
        entry_point: "main",
        port: 3000,
        minify: True,
        source_map: True,
      )
  }
}

/// Read package name from gleam.toml.
pub fn read_package_name(project_root: String) -> Result(String, String) {
  let toml_path = filepath.join(project_root, "gleam.toml")
  use content <- result.try(
    simplifile.read(toml_path)
    |> result.map_error(fn(_) { "Cannot read gleam.toml" }),
  )
  let lines = string.split(content, "\n")
  find_name_line(lines)
}

fn find_name_line(lines: List(String)) -> Result(String, String) {
  case lines {
    [] -> Error("No name found in gleam.toml")
    [line, ..rest] -> {
      case string.starts_with(line, "name = ") {
        True -> {
          let name =
            string.drop_start(line, 7) |> string.trim() |> trim_quotes()
          Ok(name)
        }
        False -> find_name_line(rest)
      }
    }
  }
}

/// Recursively find .gleam files in a directory.
fn find_class_files(dir: String) -> Result(List(String), String) {
  case simplifile.read_directory(dir) {
    Error(_) -> Ok([])
    Ok(entries) -> {
      list.try_fold(entries, [], fn(acc, entry) {
        let path = filepath.join(dir, entry)
        case string.ends_with(entry, ".gleam") {
          True -> Ok([path, ..acc])
          False ->
            case simplifile.is_directory(path) {
              Ok(True) -> {
                use sub_files <- result.try(find_class_files(path))
                Ok(list.append(acc, sub_files))
              }
              _ -> Ok(acc)
            }
        }
      })
    }
  }
}

/// Parse all found .gleam files, keeping only valid class definitions.
fn parse_all_class_files(
  files: List(String),
) -> Result(List(ClassDef), String) {
  list.try_fold(files, [], fn(acc, file) {
    use content <- result.try(
      simplifile.read(file)
      |> result.map_error(fn(_) { "Failed to read: " <> file }),
    )
    let source_file = drop_src_prefix(file) |> drop_extension()
    case parser.parse(content, source_file) {
      Ok(class) -> Ok([class, ..acc])
      Error(_) -> Ok(acc)
    }
  })
  |> result.map(list.reverse)
}

/// Parse [fusion] section from TOML content.
fn parse_fusion_section(content: String) -> FusionConfig {
  let lines = string.split(content, "\n")
  do_parse_fusion(lines, False, "cloudflare", "main", 3000, True, True)
}

fn do_parse_fusion(
  lines: List(String),
  in_fusion: Bool,
  runtime: String,
  entry_point: String,
  port: Int,
  minify: Bool,
  source_map: Bool,
) -> FusionConfig {
  case lines {
    [] ->
      FusionConfig(
        classes: [],
        runtime:,
        entry_point:,
        port:,
        minify:,
        source_map:,
      )
    [line, ..rest] -> {
      let trimmed = string.trim(line)

      // Detect section headers
      case is_section_header(trimmed) {
        True -> {
          case trimmed {
            "[fusion]" ->
              do_parse_fusion(
                rest,
                True,
                runtime,
                entry_point,
                port,
                minify,
                source_map,
              )
            _ ->
              do_parse_fusion(
                rest,
                False,
                runtime,
                entry_point,
                port,
                minify,
                source_map,
              )
          }
        }
        False ->
          case in_fusion {
            True -> {
              let #(
                new_runtime,
                new_entry_point,
                new_port,
                new_minify,
                new_source_map,
              ) =
                parse_toml_key_value(
                  trimmed,
                  runtime,
                  entry_point,
                  port,
                  minify,
                  source_map,
                )
              do_parse_fusion(
                rest,
                True,
                new_runtime,
                new_entry_point,
                new_port,
                new_minify,
                new_source_map,
              )
            }
            False ->
              do_parse_fusion(
                rest,
                False,
                runtime,
                entry_point,
                port,
                minify,
                source_map,
              )
          }
      }
    }
  }
}

fn is_section_header(line: String) -> Bool {
  string.starts_with(line, "[") && string.ends_with(line, "]")
}

fn parse_toml_key_value(
  line: String,
  runtime: String,
  entry_point: String,
  port: Int,
  minify: Bool,
  source_map: Bool,
) -> #(String, String, Int, Bool, Bool) {
  case string.split(line, "=") {
    [key, value] -> {
      let key = string.trim(key)
      let value = string.trim(value) |> trim_quotes()
      case key {
        "runtime" -> #(value, entry_point, port, minify, source_map)
        "entry_point" -> #(runtime, value, port, minify, source_map)
        "port" -> {
          case int.parse(value) {
            Ok(p) -> #(runtime, entry_point, p, minify, source_map)
            Error(_) -> #(runtime, entry_point, port, minify, source_map)
          }
        }
        "minify" -> #(runtime, entry_point, port, value == "true", source_map)
        "source_map" -> #(runtime, entry_point, port, minify, value == "true")
        _ -> #(runtime, entry_point, port, minify, source_map)
      }
    }
    _ -> #(runtime, entry_point, port, minify, source_map)
  }
}

fn trim_quotes(s: String) -> String {
  case s {
    "" -> ""
    _ -> {
      let s = case string.starts_with(s, "\"") {
        True -> string.drop_start(s, 1)
        False -> s
      }
      case string.ends_with(s, "\"") {
        True -> string.drop_end(s, 1)
        False -> s
      }
    }
  }
}

/// Extract path after src/ from a file path.
/// e.g. /foo/bar/src/classes/worker.class.gleam -> classes/worker.class.gleam
fn drop_src_prefix(path: String) -> String {
  case string.split(path, "src/") {
    [_, rest] -> rest
    _ -> path
  }
}

/// Drop the last file extension.
/// e.g. worker.class.gleam -> worker.class
fn drop_extension(path: String) -> String {
  case string.split(path, ".") {
    [] -> path
    [base] -> base
    parts -> {
      let without_last = list.take(parts, list.length(parts) - 1)
      string.join(without_last, ".")
    }
  }
}

// ── JSON Serialization ────────────────────────────────────────

fn config_to_json(config: FusionConfig) -> String {
  let classes_json = list.map(config.classes, class_to_json)
  "{ \"classes\": [" <> string.join(classes_json, ", ") <> "] }"
}

fn class_to_json(class: ClassDef) -> String {
  let extends_json = case class.extends {
    None -> "null"
    Some(ext) ->
      "{ \"name\": "
      <> escape_json_string(ext.name)
      <> ", \"from\": "
      <> escape_json_string(ext.from)
      <> " }"
  }

  let methods_json = list.map(class.methods, method_to_json)

  "{ \"name\": "
  <> escape_json_string(class.name)
  <> ", \"extends\": "
  <> extends_json
  <> ", \"methods\": ["
  <> string.join(methods_json, ", ")
  <> "], \"export\": "
  <> bool_to_string(class.should_export)
  <> ", \"source_file\": "
  <> escape_json_string(class.source_file)
  <> " }"
}

fn method_to_json(method: Method) -> String {
  "{ \"name\": "
  <> escape_json_string(method.name)
  <> ", \"params\": ["
  <> string.join(list.map(method.params, escape_json_string), ", ")
  <> "], \"is_async\": "
  <> bool_to_string(method.is_async)
  <> " }"
}

fn escape_json_string(s: String) -> String {
  let s = string.replace(s, "\\", "\\\\")
  let s = string.replace(s, "\"", "\\\"")
  "\"" <> s <> "\""
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
