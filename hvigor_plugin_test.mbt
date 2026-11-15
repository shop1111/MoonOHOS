///|
test "hvigor plugin source carries the CLI version and both entry points" {
  let source = @moonohos.hvigor_plugin_source()
  assert_true(source.contains("MoonOHOS " + @moonohos.moonohos_version()))
  assert_false(source.contains("__VERSION__"))
  assert_true(source.contains("export function moonohosPlugin("))
  assert_true(source.contains("'@PreBuild'"))
  assert_true(source.contains("'build', '--config'"))
  assert_true(source.contains("'har', '--dist'"))
}

///|
test "hvigorfile_update replaces stock HAR hvigorfiles only" {
  let init_stock = "import { harTasks } from '@ohos/hvigor-ohos-plugin';\nexport default { system: harTasks, plugins: [] };\n"
  let deveco_stock =
    #|import { harTasks } from '@ohos/hvigor-ohos-plugin';
    #|
    #|export default {
    #|  system: harTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    #|  plugins:[]         /* Custom plugin to extend the functionality of your project. */
    #|}
    #|
  let expected = @moonohos.hvigor_har_module_file(
    "../hvigor/moonohos-plugin", "../../moonohos.json",
  )
  for stock in [init_stock, deveco_stock] {
    match
      @moonohos.hvigorfile_update(
        stock, "../hvigor/moonohos-plugin", "../../moonohos.json",
      ) {
      Replace(text) => assert_eq(text, expected)
      _ => fail("stock hvigorfile not replaced")
    }
  }
  match @moonohos.hvigorfile_update(expected, "x", "y") {
    Present => ()
    _ => fail("plugin already applied")
  }
  let custom = "import { harTasks } from '@ohos/hvigor-ohos-plugin';\nimport { other } from './other';\nexport default { system: harTasks, plugins: [other()] };\n"
  match
    @moonohos.hvigorfile_update(
      custom, "../hvigor/moonohos-plugin", "../m.json",
    ) {
    Manual(lines) =>
      inspect(
        lines,
        content=(
          #|import { moonohosPlugin } from '../hvigor/moonohos-plugin';
          #|// in plugins: moonohosPlugin({ config: '../m.json' })
        ),
      )
    _ => fail("custom hvigorfile must be left to the developer")
  }
}

///|
test "init applies the Hvigor plugin and commits the type package manifest" {
  let files = @moonohos.init_files({
    name: "demo",
    package_name: "alice/demo",
    ohos: None,
  })
  let file = (path : String) => {
    for entry in files {
      if entry.0 == path {
        return entry.1
      }
    }
    abort("missing " + path)
  }
  assert_eq(
    file("harmony/hvigor/moonohos-plugin.ts"),
    @moonohos.hvigor_plugin_source(),
  )
  assert_true(
    file("harmony/demo/hvigorfile.ts").contains(
      "moonohosPlugin({ config: '../../moonohos.json' })",
    ),
  )
  inspect(
    file("harmony/demo/src/main/cpp/types/libdemo/oh-package.json5"),
    content=(
      #|{
      #|  "name": "libdemo.so",
      #|  "version": "0.9.0",
      #|  "types": "./index.d.ts"
      #|}
    ),
  )
  let ignore = file(".gitignore")
  assert_true(ignore.contains("harmony/*/src/main/cpp/types/*/index.d.ts"))
  assert_false(ignore.contains("harmony/*/src/main/cpp/types/\n"))
}

///|
test "parse_cli accepts hvigor with --module and --config" {
  let options = @moonohos.parse_cli([
    "hvigor", "--module", "harmony/demo", "--config", "x/moonohos.json", "--json",
  ])
  assert_true(options.command is Hvigor)
  assert_eq(options.module_dir, Some("harmony/demo"))
  assert_eq(options.config, "x/moonohos.json")
  let missing = Some(@moonohos.parse_cli(["hvigor"])) catch { _ => None }
  assert_true(missing is None)
  let wrong = Some(
    @moonohos.parse_cli(["hvigor", "--module", "m", "--dist", "d"]),
  ) catch {
    _ => None
  }
  assert_true(wrong is None)
}
