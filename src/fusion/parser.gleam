import fusion/types.{
  type ClassDef, type Extends, type Method, ClassDef, Extends, Method,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Parse a .class.gleam file into a ClassDef.
/// Extracts metadata: class name, extends, export flag, method signatures.
pub fn parse(input: String, source_file: String) -> Result(ClassDef, String) {
  let lines = string.split(input, "\n") |> list.filter(fn(l) { l != "" })
  do_parse(lines, [], None, [], None, False, source_file)
}

fn do_parse(
  lines: List(String),
  pending: List(String),
  extends: Option(Extends),
  methods: List(Method),
  class_name: Option(String),
  should_export: Bool,
  source_file: String,
) -> Result(ClassDef, String) {
  case lines {
    [] -> {
      // Process remaining pending annotations
      let #(class_name, should_export, extends) =
        finish_pending(pending, class_name, should_export, extends)
      case class_name {
        Some(name) ->
          Ok(ClassDef(
            name:,
            extends:,
            methods: list.reverse(methods),
            should_export:,
            source_file:,
          ))
        None -> Error("No @name annotation found")
      }
    }

    [line, ..rest] -> {
      let trimmed = string.trim(line)

      // Collect doc-comment annotations
      case string.starts_with(trimmed, "///") {
        True -> {
          let ann = string.trim(string.drop_start(trimmed, 3))
          do_parse(
            rest,
            [ann, ..pending],
            extends,
            methods,
            class_name,
            should_export,
            source_file,
          )
        }

        False ->
          // Try parsing as pub const name = "..."
          case parse_name_const(trimmed) {
            Ok(name) -> {
              // Process pending: extract @export, apply @extends
              let #(cn, ex, ext) =
                finish_pending(pending, Some(name), should_export, extends)
              let method_pending = clean_pending_for_methods(pending)
              do_parse(rest, method_pending, ext, methods, cn, ex, source_file)
            }

            Error(Nil) ->
              // Try parsing as pub const export = True/False
              case parse_export_const(trimmed) {
                Ok(export) -> {
                  // Extract @name from pending
                  let #(cn, _, ext) =
                    finish_pending(pending, class_name, export, extends)
                  do_parse(rest, [], ext, methods, cn, export, source_file)
                }

                Error(Nil) ->
                  // Try parsing as a method
                  case parse_method(trimmed) {
                    Ok(method) -> {
                      let method = apply_async(method, pending)
                      // Extract @name/@export/@extends from pending before clearing
                      let #(cn, ex, ext) =
                        finish_pending(
                          pending,
                          class_name,
                          should_export,
                          extends,
                        )
                      do_parse(
                        rest,
                        [],
                        ext,
                        [method, ..methods],
                        cn,
                        ex,
                        source_file,
                      )
                    }

                    Error(Nil) -> {
                      do_parse(
                        rest,
                        [],
                        extends,
                        methods,
                        class_name,
                        should_export,
                        source_file,
                      )
                    }
                  }
              }
          }
      }
    }
  }
}

/// Process remaining annotations at end of file to extract @name, @export
fn finish_pending(
  pending: List(String),
  class_name: Option(String),
  should_export: Bool,
  extends: Option(Extends),
) -> #(Option(String), Bool, Option(Extends)) {
  case pending {
    [] -> #(class_name, should_export, extends)
    [ann, ..rest] -> {
      let ann_text = string.trim(ann)
      let #(cn, ex, ext) =
        classify_annotation(ann_text, class_name, should_export, extends)
      finish_pending(rest, cn, ex, ext)
    }
  }
}

fn classify_annotation(
  ann: String,
  class_name: Option(String),
  should_export: Bool,
  extends: Option(Extends),
) -> #(Option(String), Bool, Option(Extends)) {
  case string.starts_with(ann, "@name ") {
    True -> {
      let name = string.trim(string.drop_start(ann, 6))
      #(Some(name), should_export, extends)
    }
    False ->
      case string.starts_with(ann, "@export ") {
        True -> {
          let value = string.trim(string.drop_start(ann, 8))
          let export = value == "true" || value == "True"
          #(class_name, export, extends)
        }
        False ->
          case string.starts_with(ann, "@extends") {
            True -> {
              let rest_text = string.trim(string.drop_start(ann, 8))
              let ext = case parse_extends(rest_text) {
                Ok(e) -> Some(e)
                Error(_) -> extends
              }
              #(class_name, should_export, ext)
            }
            False -> #(class_name, should_export, extends)
          }
      }
  }
}

/// Remove @extends from pending (already consumed)
fn clean_pending_for_methods(pending: List(String)) -> List(String) {
  list.filter(pending, fn(ann) {
    !string.starts_with(string.trim(ann), "@extends")
  })
}

/// Apply @async to a method from pending annotations
fn apply_async(method: Method, annotations: List(String)) -> Method {
  case annotations {
    [] -> method
    [ann, ..rest] -> {
      case string.trim(ann) {
        "@async" -> Method(..method, is_async: True)
        _ -> apply_async(method, rest)
      }
    }
  }
}

/// Parse: pub const name = "ChatInboxDO"
fn parse_name_const(line: String) -> Result(String, Nil) {
  case string.starts_with(line, "pub const name") {
    True ->
      case string.split(line, "\"") {
        [_, name, _] -> Ok(name)
        _ -> Error(Nil)
      }
    False -> Error(Nil)
  }
}

/// Parse: pub const export = True
fn parse_export_const(line: String) -> Result(Bool, Nil) {
  case string.starts_with(line, "pub const export") {
    True -> {
      case string.contains(line, "True") {
        True -> Ok(True)
        False -> Ok(False)
      }
    }
    False -> Error(Nil)
  }
}

/// Parse: @extends DurableObject from "cloudflare:workers"
fn parse_extends(input: String) -> Result(Extends, String) {
  case string.split(input, " from ") {
    [name, rest] -> {
      let path = string.trim(rest) |> trim_quotes
      Ok(Extends(name: string.trim(name), from: path))
    }
    _ -> Error("Invalid @extends format")
  }
}

/// Parse public methods: pub fn method_name(param1, param2) { ... }
///
/// Private Gleam functions are not exported by the compiled JavaScript module,
/// so they cannot be used as class methods.
fn parse_method(line: String) -> Result(Method, Nil) {
  case string.starts_with(line, "pub fn ") {
    False -> Error(Nil)
    True -> {
      let rest = string.drop_start(line, 7)
      case string.split(rest, "(") {
        [name, rest2] -> {
          case string.split(rest2, ")") {
            [params_str, _] -> {
              let params = string.trim(params_str) |> split_params
              Ok(Method(name: string.trim(name), params:, is_async: False))
            }
            _ -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    }
  }
}

fn split_params(params: String) -> List(String) {
  case params {
    "" -> []
    _ ->
      string.split(params, ",")
      |> list.map(string.trim)
      |> list.filter(fn(p) { p != "" })
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
