import filepath
import fusion/types.{type ClassDef, type Method, Extends}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

/// Generate a class adapter for a compiled Gleam module.
///
/// The generated methods delegate to the original compiled functions. This
/// keeps the original module and its source map in the bundle, so errors in
/// Gleam code can still be mapped back to the .gleam source file.
pub fn transform_class(
  class: ClassDef,
  build_dir: String,
  package_name: String,
) -> Result(String, String) {
  let mjs_path =
    filepath.join(build_dir, package_name)
    |> filepath.join(class.source_file <> ".mjs")

  use _content <- result.try(
    simplifile.read(mjs_path)
    |> result.map_error(fn(_) { "Cannot read compiled output: " <> mjs_path }),
  )

  Ok(generate_class_file(class, package_name))
}

fn generate_class_file(class: ClassDef, package_name: String) -> String {
  let sections = [
    generate_imports(class, package_name),
    generate_class_header(class),
    generate_constructor(class),
    generate_methods(class),
    "}",
  ]

  sections
  |> list.filter(fn(s) { s != "" })
  |> string.join("\n\n")
}

/// Import the parent class and the functions from the original Gleam module.
fn generate_imports(class: ClassDef, package_name: String) -> String {
  let parent_import = case class.extends {
    None -> ""
    Some(Extends(name:, from:)) ->
      "import { " <> name <> " } from \"" <> from <> "\";"
  }

  let function_import = case class.methods {
    [] -> ""
    _ -> {
      let imports =
        class.methods
        |> list.map(fn(method) {
          method.name <> " as " <> function_alias(method)
        })
        |> string.join(", ")
      "import { "
      <> imports
      <> " } from \"../../dev/javascript/"
      <> package_name
      <> "/"
      <> class.source_file
      <> ".mjs\";"
    }
  }

  [parent_import, function_import]
  |> list.filter(fn(s) { s != "" })
  |> string.join("\n")
}

fn generate_class_header(class: ClassDef) -> String {
  let extends_str = case class.extends {
    None -> ""
    Some(Extends(name:, from: _)) -> " extends " <> name
  }

  let export_str = case class.should_export {
    True -> "export "
    False -> ""
  }

  export_str <> "class " <> class.name <> extends_str <> " {"
}

fn generate_constructor(class: ClassDef) -> String {
  case find_method(class, "constructor") {
    Some(method) -> {
      let super_call = case class.extends {
        Some(_) -> "    super(...args);\n"
        None -> ""
      }
      let call = "    " <> function_alias(method) <> "(...args);"
      "  constructor(...args) {\n" <> super_call <> call <> "\n  }"
    }
    None -> ""
  }
}

fn generate_methods(class: ClassDef) -> String {
  class.methods
  |> list.filter(fn(method) { method.name != "constructor" })
  |> list.map(generate_method)
  |> string.join("\n\n")
}

fn generate_method(method: Method) -> String {
  let async_str = case method.is_async {
    True -> "async "
    False -> ""
  }

  let params = method.params |> list.map(js_param_name)
  let params_str = string.join(params, ", ")
  let args_str = string.join(params, ", ")

  "  "
  <> async_str
  <> method.name
  <> "("
  <> params_str
  <> ") {\n    return "
  <> function_alias(method)
  <> "("
  <> args_str
  <> ");\n  }"
}

fn function_alias(method: Method) -> String {
  method.name <> "$"
}

/// Convert a Gleam parameter declaration to a JavaScript parameter name.
/// For example, `message: String` becomes `message`.
fn js_param_name(param: String) -> String {
  case string.split(param, ":") {
    [name, ..] -> string.trim(name)
    [] -> param
  }
}

fn find_method(class: ClassDef, name: String) -> Option(Method) {
  case list.find(class.methods, fn(method) { method.name == name }) {
    Ok(method) -> Some(method)
    Error(_) -> None
  }
}
