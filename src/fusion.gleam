import argv
import fusion/build
import fusion/cli
import glint

pub fn main() {
  glint.new()
  |> glint.with_name("fusion")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: build_cmd())
  |> glint.add(at: ["build"], do: build_cmd())
  |> glint.add(at: ["scan"], do: scan_cmd())
  |> glint.add(at: ["init"], do: cli.init_cmd())
  |> glint.add(at: ["class", "create"], do: cli.class_create_cmd())
  |> glint.add(at: ["class", "list"], do: cli.class_list_cmd())
  |> glint.add(at: ["dev"], do: cli.dev_cmd())
  |> glint.run(argv.load().arguments)
}

fn build_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("Build the project")
  use _, _, _ <- glint.command()
  build.do_build(build.find_project_root())
}

fn scan_cmd() -> glint.Command(Nil) {
  use <- glint.command_help("Scan class files and cache metadata")
  use _, _, _ <- glint.command()
  build.do_scan(build.find_project_root())
}
