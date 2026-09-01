import argv
import fusion/cli
import glint

pub fn main() {
  glint.new()
  |> glint.with_name("fusion")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: cli.build_cmd())
  |> glint.add(at: ["build"], do: cli.build_cmd())
  |> glint.add(at: ["scan"], do: cli.scan_cmd())
  |> glint.add(at: ["init"], do: cli.init_cmd())
  |> glint.add(at: ["class", "create"], do: cli.class_create_cmd())
  |> glint.add(at: ["class", "list"], do: cli.class_list_cmd())
  |> glint.add(at: ["dev"], do: cli.dev_cmd())
  |> glint.run(argv.load().arguments)
}
