///|
/// Options for `moonohos init`.
pub(all) struct InitOptions {
  /// Native module and HAR module name, e.g. `textkit`.
  name : String
  /// MoonBit package, e.g. `alice/textkit`.
  package_name : String
  /// Workspace path from the project to the `ohos` platform module, if local.
  ohos : String?
}

///|
pub fn valid_module_name(name : String) -> Bool {
  if name.is_empty() || name.length() > 32 {
    return false
  }
  for index, ch in name {
    if !(ch >= 'a' && ch <= 'z') &&
      !(index > 0 && (ch == '_' || (ch >= '0' && ch <= '9'))) {
      return false
    }
  }
  true
}

///|
/// Relative path from directory `from` to `to`; both absolute with `/`.
/// Components compare case-insensitively unless `case_sensitive` is set.
pub fn relative_path(
  from : String,
  to : String,
  case_sensitive~ : Bool = false,
) -> String {
  let a = from.split("/").filter(s => s != "").map(s => s.to_owned()).to_array()
  let b = to.split("/").filter(s => s != "").map(s => s.to_owned()).to_array()
  let mut common = 0
  while common < a.length() &&
        common < b.length() &&
        (if case_sensitive {
          a[common] == b[common]
        } else {
          a[common].to_lower() == b[common].to_lower()
        }) {
    common += 1
  }
  let parts : Array[String] = []
  for _ in common..<a.length() {
    parts.push("..")
  }
  for index in common..<b.length() {
    parts.push(b[index])
  }
  if parts.is_empty() {
    "."
  } else {
    parts.join("/")
  }
}

///|
fn har_name(options : InitOptions) -> String {
  let owner = options.package_name
    .split("/")
    .head()
    .unwrap_or("moonohos")
    .to_owned()
  "@" + owner.to_lower() + "/" + options.name.replace_all(old="_", new="-")
}

///|
/// Files of a new MoonOHOS project: a MoonBit library, its bridge manifest and
/// a Hvigor project whose HAR module will carry the built libraries.
pub fn init_files(
  options : InitOptions,
) -> Array[(String, String)] raise ConfigError {
  if !valid_module_name(options.name) {
    raise Invalid("init: name must match [a-z][a-z0-9_]{0,31}: " + options.name)
  }
  let parts = options.package_name.split("/").to_array()
  if parts.length() != 2 ||
    !identifier(parts[0].to_owned()) ||
    !identifier(parts[1].to_owned()) {
    raise Invalid("init: package must be owner/name: " + options.package_name)
  }
  let name = options.name
  let module_dir = "core"
  let members = ["  \"./" + module_dir + "\",\n"]
  if options.ohos is Some(path) {
    members.push("  \"" + path + "\",\n")
  }
  let template = (text : String) => {
    text
    .replace_all(old="__NAME__", new=name)
    .replace_all(old="__PACKAGE__", new=options.package_name)
    .replace_all(old="__HAR__", new=har_name(options))
    .replace_all(old="__VERSION__", new=moonohos_version())
  }
  let files : Array[(String, String)] = [
    ("moon.work", "members = [\n" + members.join("") + "]\n"),
    (
      "moonohos.json",
      template(
        (
          #|{
          #|  "version": 2,
          #|  "module": "core",
          #|  "package": "__PACKAGE__",
          #|  "nativeModule": "__NAME__",
          #|  "workspace": "moon.work",
          #|  "functions": [
          #|    {"name": "greet", "params": [{"name": "name", "type": "String"}], "return": "String"},
          #|    {"name": "count_words", "params": [{"name": "text", "type": "String"}], "return": "Int", "async": true, "raises": true}
          #|  ]
          #|}
          #|
        ),
      ),
    ),
    (
      "core/moon.mod",
      template(
        (
          #|name = "__PACKAGE__"
          #|
          #|version = "0.1.0"
          #|
          #|preferred_target = "native"
          #|
          #|import {
          #|  "shop1111/moonohos_ohos@__VERSION__",
          #|}
          #|
        ),
      ),
    ),
    (
      "core/moon.pkg",
      (
        #|import {
        #|  "shop1111/moonohos_ohos/hilog",
        #|  "shop1111/moonohos_ohos/task",
        #|}
        #|
      ),
    ),
    (
      "core/lib.mbt",
      template(
        (
          #|///|
          #|/// Synchronous export: runs on the calling ArkTS thread.
          #|pub fn greet(name : String) -> String {
          #|  "Hello, " + name + " from MoonBit"
          #|}
          #|
          #|///|
          #|/// Async export: runs on a Node-API worker thread and polls cancellation.
          #|pub fn count_words(text : String) -> Int raise @task.Cancelled {
          #|  let mut count = 0
          #|  let mut inside = false
          #|  for index, ch in text {
          #|    if index % 4096 == 0 {
          #|      @task.check()
          #|    }
          #|    let space = ch == ' ' || ch == '\n' || ch == '\t'
          #|    if !space && !inside {
          #|      count += 1
          #|    }
          #|    inside = !space
          #|  }
          #|  // Logging is best-effort: an invalid domain or tag must not fail the call.
          #|  let logger = try Some(@hilog.Logger::new(0x4d4f, "__NAME__")) catch {
          #|    _ => None
          #|  }
          #|  if logger is Some(logger) {
          #|    logger.info("count_words " + count.to_string())
          #|  }
          #|  count
          #|}
          #|
        ),
      ),
    ),
    (
      "core/lib_wbtest.mbt",
      (
        #|///|
        #|test "exports" {
        #|  assert_eq(greet("ArkTS"), "Hello, ArkTS from MoonBit")
        #|  assert_eq(count_words("one two\nthree"), 3)
        #|}
        #|
      ),
    ),
    (
      ".gitignore",
      (
        #|_build/
        #|.mooncakes/
        #|**/build/
        #|**/oh_modules/
        #|**/.hvigor/
        #|**/oh-package-lock.json5
        #|**/BuildProfile.ets
        #|harmony/*/libs/
        #|harmony/*/src/main/cpp/types/
        #|harmony/*/src/main/ets/generated/
        #|*.har
        #|
      ),
    ),
    (
      "README.md",
      template(
        (
          #|# __NAME__
          #|
          #|MoonBit native module for HarmonyOS, generated by MoonOHOS __VERSION__.
          #|
          #|```bash
          #|moonohos build --sdk "<DevEco>/sdk" --out _build/dist
          #|moonohos har --dist _build/dist --module harmony/__NAME__ --assemble --app --deveco "<DevEco>"
          #|```
          #|
          #|The HAR is written to `harmony/__NAME__/build/default/outputs/default/__NAME__.har`.
          #|`--app` also builds the demo app in `harmony/entry` (an unsigned debug HAP);
          #|open `harmony/` in DevEco Studio to sign and run it.
          #|An application adds `"__HAR__": "file:<path>/__NAME__.har"` to its
          #|`oh-package.json5` and imports it:
          #|
          #|```typescript
          #|import native, { CancelToken } from '__HAR__';
          #|const token: CancelToken = native.createCancelToken();
          #|const words: number = await native.count_words('a b c', token);
          #|```
          #|
        ),
      ),
    ),
    (
      "harmony/build-profile.json5",
      template(
        (
          #|{
          #|  "app": {
          #|    "products": [{"name": "default", "compatibleSdkVersion": "26.0.0", "targetSdkVersion": "26.0.0", "runtimeOS": "HarmonyOS"}],
          #|    "buildModeSet": [{"name": "debug"}, {"name": "release"}]
          #|  },
          #|  "modules": [
          #|    {"name": "__NAME__", "srcPath": "./__NAME__"},
          #|    {"name": "entry", "srcPath": "./entry", "targets": [{"name": "default", "applyToProducts": ["default"]}]}
          #|  ]
          #|}
          #|
        ),
      ),
    ),
    (
      "harmony/oh-package.json5",
      template(
        "{\"modelVersion\": \"5.0.0\", \"name\": \"__NAME__-har-project\", \"version\": \"0.1.0\", \"dependencies\": {}, \"devDependencies\": {}}\n",
      ),
    ),
    (
      "harmony/hvigorfile.ts", "import { appTasks } from '@ohos/hvigor-ohos-plugin';\nexport default { system: appTasks, plugins: [] };\n",
    ),
    (
      "harmony/hvigor/hvigor-config.json5", "{\"modelVersion\": \"5.0.0\", \"dependencies\": {}, \"execution\": {}, \"logging\": {\"level\": \"info\"}, \"nodeOptions\": {}}\n",
    ),
    (
      "harmony/AppScope/app.json5",
      template(
        "{\"app\": {\"bundleName\": \"com.moonohos.__NAME__\", \"vendor\": \"MoonOHOS\", \"versionCode\": 1000000, \"versionName\": \"0.1.0\", \"icon\": \"$media:app_icon\", \"label\": \"$string:app_name\"}}\n",
      ),
    ),
    (
      "harmony/AppScope/resources/base/element/string.json",
      template(
        "{\"string\": [{\"name\": \"app_name\", \"value\": \"__NAME__\"}]}\n",
      ),
    ),
    (
      "harmony/AppScope/resources/base/media/app_icon.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" rx=\"14\" fill=\"#2f6fdd\"/><circle cx=\"32\" cy=\"32\" r=\"14\" fill=\"#f5f8fb\"/></svg>\n",
    ),
    (
      "harmony/entry/oh-package.json5",
      template(
        "{\"name\": \"entry\", \"version\": \"0.1.0\", \"description\": \"Demo app consuming the __HAR__ HAR\", \"main\": \"\", \"license\": \"Apache-2.0\", \"dependencies\": {\"__HAR__\": \"file:../__NAME__\"}}\n",
      ),
    ),
    (
      "harmony/entry/build-profile.json5", "{\"apiType\": \"stageMode\", \"buildOption\": {}, \"targets\": [{\"name\": \"default\"}]}\n",
    ),
    (
      "harmony/entry/hvigorfile.ts", "import { hapTasks } from '@ohos/hvigor-ohos-plugin';\nexport default { system: hapTasks, plugins: [] };\n",
    ),
    (
      "harmony/entry/src/main/module.json5",
      (
        #|{
        #|  "module": {
        #|    "name": "entry", "type": "entry", "mainElement": "EntryAbility", "deviceTypes": ["phone", "tablet", "2in1"],
        #|    "deliveryWithInstall": true, "installationFree": false, "pages": "$profile:main_pages",
        #|    "abilities": [{"name": "EntryAbility", "srcEntry": "./ets/entryability/EntryAbility.ets", "icon": "$media:app_icon",
        #|      "label": "$string:app_name", "startWindowIcon": "$media:app_icon", "startWindowBackground": "$color:start_window_background",
        #|      "exported": true, "skills": [{"entities": ["entity.system.home"], "actions": ["action.system.home"]}]}]
        #|  }
        #|}
        #|
      ),
    ),
    (
      "harmony/entry/src/main/resources/base/element/color.json", "{\"color\": [{\"name\": \"start_window_background\", \"value\": \"#F5F8FB\"}]}\n",
    ),
    (
      "harmony/entry/src/main/resources/base/profile/main_pages.json", "{\"src\": [\"pages/Index\"]}\n",
    ),
    (
      "harmony/entry/src/main/ets/entryability/EntryAbility.ets",
      (
        #|import { UIAbility } from '@kit.AbilityKit';
        #|import { window } from '@kit.ArkUI';
        #|
        #|export default class EntryAbility extends UIAbility {
        #|  onWindowStageCreate(windowStage: window.WindowStage): void {
        #|    windowStage.loadContent('pages/Index');
        #|  }
        #|}
        #|
      ),
    ),
    (
      "harmony/entry/src/main/ets/pages/Index.ets",
      template(
        (
          #|// Demo page: a synchronous call and a cancellable async call into MoonBit.
          #|import native, { CancelToken } from '__HAR__';
          #|
          #|@Entry
          #|@Component
          #|struct Index {
          #|  @State greeting: string = '';
          #|  @State words: string = 'Tap to count words on a worker thread';
          #|  private token: CancelToken | undefined = undefined;
          #|
          #|  aboutToAppear(): void {
          #|    this.greeting = native.greet('ArkTS');
          #|  }
          #|
          #|  aboutToDisappear(): void {
          #|    this.token?.cancel();
          #|  }
          #|
          #|  build() {
          #|    Column({ space: 16 }) {
          #|      Text(this.greeting).fontSize(22)
          #|      Button('Count words in MoonBit')
          #|        .onClick(async () => {
          #|          const token: CancelToken = native.createCancelToken();
          #|          this.token = token;
          #|          try {
          #|            const count: number = await native.count_words('MoonBit runs on a Node-API worker thread', token);
          #|            this.words = `${count} words`;
          #|          } catch (error) {
          #|            this.words = `Failed: ${JSON.stringify(error)}`;
          #|          }
          #|        })
          #|      Text(this.words).fontSize(18)
          #|    }
          #|    .width('100%')
          #|    .height('100%')
          #|    .justifyContent(FlexAlign.Center)
          #|  }
          #|}
          #|
        ),
      ),
    ),
    (
      "harmony/__NAME__/oh-package.json5".replace_all(old="__NAME__", new=name),
      template(
        "{\n  \"name\": \"__HAR__\",\n  \"version\": \"0.1.0\",\n  \"description\": \"MoonBit native module __NAME__\",\n  \"main\": \"Index.ets\",\n  \"license\": \"Apache-2.0\",\n  \"dependencies\": {\n    \"lib__NAME__.so\": \"file:./src/main/cpp/types/lib__NAME__\"\n  }\n}\n",
      ),
    ),
    (
      "harmony/__NAME__/Index.ets".replace_all(old="__NAME__", new=name),
      (
        #|// Public entry of the HAR; `moonohos har` regenerates src/main/ets/generated/Native.ets.
        #|import native from './src/main/ets/generated/Native';
        #|
        #|export * from './src/main/ets/generated/Native';
        #|export default native;
        #|
      ),
    ),
    (
      "harmony/__NAME__/build-profile.json5".replace_all(
        old="__NAME__",
        new=name,
      ),
      "{\"apiType\": \"stageMode\", \"buildOption\": {}, \"targets\": [{\"name\": \"default\"}]}\n",
    ),
    (
      "harmony/__NAME__/hvigorfile.ts".replace_all(old="__NAME__", new=name),
      "import { harTasks } from '@ohos/hvigor-ohos-plugin';\nexport default { system: harTasks, plugins: [] };\n",
    ),
    (
      "harmony/__NAME__/src/main/module.json5".replace_all(
        old="__NAME__",
        new=name,
      ),
      template(
        "{\"module\": {\"name\": \"__NAME__\", \"type\": \"har\", \"deviceTypes\": [\"phone\", \"tablet\", \"2in1\"]}}\n",
      ),
    ),
  ]
  files
}

///|
/// Drive of a Windows path (`D:`), or `/` for other absolute paths. Paths with
/// different roots have no relative path between them.
pub fn path_root(path : String) -> String {
  let chars = path.to_array()
  if chars.length() >= 2 && chars[1] == ':' && chars[0].is_ascii_alphabetic() {
    path[:1].to_owned().to_upper() + ":"
  } else {
    "/"
  }
}
