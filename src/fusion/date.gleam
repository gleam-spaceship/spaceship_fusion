@external(erlang, "dev_ffi", "get_today")
fn do_get_today() -> String

pub fn today() -> String {
  do_get_today()
}
