///|
priv struct SelectedProject {
  project : @lib.Project
  base : String
  root : String
  source_dir : String
  relative_package : String
}

///|
async fn select_project(path : String) -> SelectedProject {
  let config_path = normalized(@fs.realpath(path))
  let base = parent(config_path)
  let project = @lib.parse_project(read(config_path))
  project.validate()
  let root = normalized(@fs.realpath(resolve(base, project.module_dir)))
  let (name, source_dir) = module_metadata(root)
  let relative_package = if project.package_name == name {
    ""
  } else if project.package_name.has_prefix(name + "/") {
    project.package_name[name.length() + 1:].to_owned()
  } else {
    raise Failure("config: package must belong to selected module")
  }
  { project, base, root, source_dir, relative_package, }
}

///|
async fn create_work(base : String, purpose : String) -> String {
  ensure_dir(base + "/_build/moonohos")
  let mut index = 1
  while @fs.exists(
          base + "/_build/moonohos/" + purpose + "-" + index.to_string(),
        ) {
    index += 1
  }
  let work = base + "/_build/moonohos/" + purpose + "-" + index.to_string()
  ensure_dir(work)
  work
}

///|
async fn verify_selected(selected : SelectedProject, work : String) -> Unit {
  let staged = stage_project(
    selected.project,
    selected.base,
    selected.root,
    selected.source_dir,
    work,
  )
  command("interface", "moon", ["info", "--target", "native"], staged.root)
  |> ignore
  let found : Array[NativePackage] = []
  discover_native(staged.root, found)
  let source = staged.source
  let interface_text = read(
    source + "/" + selected.relative_package + "/pkg.generated.mbti",
  )
  selected.project.verify_interface(interface_text)
  let bridge = source + "/moonohos_bridge"
  if @fs.exists(bridge) {
    raise Failure("interface: reserved package moonohos_bridge already exists")
  }
  let project = selected.project.with_adapters(
    @lib.resolve_adapters(
      selected.project,
      known_descriptors(found),
      @lib.interface_imports(interface_text),
    ),
  )
  let generated = project.generate()
  write(bridge + "/main.mbt", generated.wrapper)
  write(bridge + "/moon.pkg", generated.package_file)
  command(
    "wrapper-check",
    "moon",
    ["check", "--target", "native", "--deny-warn"],
    staged.root,
  )
  |> ignore
  write(
    work + "/interface.json",
    selected.project.summary().stringify(indent=2),
  )
}

///|
async fn analyze(options : @lib.CliOptions) -> Json {
  let selected = select_project(options.config)
  let work = create_work(selected.base, "analysis")
  verify_selected(selected, work)
  match options.command {
    Check =>
      {
        "verified": true,
        "package": selected.project.package_name,
        "evidence": work,
      }
    Inspect => selected.project.summary()
    Plan => {
      if options.sdk is Some(_) {
        doctor(options) |> ignore
      }
      selected.project.build_plan(options.abis)
    }
    _ => raise Failure("analysis: unsupported command")
  }
}
