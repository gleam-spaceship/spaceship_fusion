import fusion/parser
import gleam/list
import gleam/option.{Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── Parser Tests ──────────────────────────────────────────────

pub fn parse_simple_class_test() {
  let input =
    "
/// @extends Animal from \"./animal.js\"
/// @name Dog
/// @export true

pub fn bark() {
  // woof
}
"

  let assert Ok(class) = parser.parse(input, "test")
  class.name |> should.equal("Dog")
  class.should_export |> should.equal(True)
  class.extends |> should.be_some

  let assert Some(ext) = class.extends
  ext.name |> should.equal("Animal")
  ext.from |> should.equal("./animal.js")
}

pub fn export_flag_true_test() {
  let input =
    "
/// @name MyClass
/// @export true
"

  let assert Ok(class) = parser.parse(input, "test")
  class.should_export |> should.equal(True)
}

pub fn export_flag_false_test() {
  let input =
    "
/// @name MyClass
/// @export false
"

  let assert Ok(class) = parser.parse(input, "test")
  class.should_export |> should.equal(False)
}

// ── Codegen Tests ─────────────────────────────────────────────

pub fn generate_header_with_extends_test() {
  let input =
    "
/// @extends DurableObject from \"cloudflare:workers\"
/// @name ChatInbox
/// @export true

pub fn fetch(request) {
  // ...
}
"

  let assert Ok(class) = parser.parse(input, "test")
  class.name |> should.equal("ChatInbox")
  class.extends |> should.be_some
}

pub fn generate_header_without_extends_test() {
  let input =
    "
/// @name Helper
/// @export true

pub fn do_something() {
  // ...
}
"

  let assert Ok(class) = parser.parse(input, "test")
  class.name |> should.equal("Helper")
  class.extends |> should.equal(option.None)
}

pub fn generate_header_no_export_test() {
  let input =
    "
/// @name Internal
/// @export false

pub fn helper() {
  // ...
}
"

  let assert Ok(class) = parser.parse(input, "test")
  class.should_export |> should.equal(False)
}

// ── Async Annotation ──────────────────────────────────────────

pub fn async_methods_test() {
  let input =
    "
/// @name Worker
/// @export true

/// @async
pub fn fetch(request) {
  // ...
}

pub fn alarm() {
  // ...
}
"

  let assert Ok(class) = parser.parse(input, "test")
  let async_methods = list.filter(class.methods, fn(m) { m.is_async })
  list.length(async_methods) |> should.equal(1)
}

// ── Error Cases ───────────────────────────────────────────────

pub fn missing_class_name_test() {
  let input =
    "
pub fn bark() {
  // woof
}
"

  let result = parser.parse(input, "test")
  case result {
    Error(_) -> Nil
    Ok(_) -> panic as "Expected error"
  }
}
