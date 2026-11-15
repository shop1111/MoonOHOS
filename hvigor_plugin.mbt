///|
/// Hvigor plugin written into `harmony/hvigor/` (0.10). It runs
/// `moonohos build --cache` and `moonohos har` before the HAR module's
/// `<target>@PreBuild`, so building the module or any app depending on it in
/// DevEco Studio compiles the MoonBit sources first.
pub fn hvigor_plugin_source() -> String {
  (
    #|// MoonOHOS __VERSION__ Hvigor plugin, written by `moonohos init` / `moonohos hvigor`.
    #|// Builds the MoonBit native module before the HAR module's PreBuild, so
    #|// DevEco Studio's Build and Run compile MoonBit sources too. Do not edit;
    #|// rerun `moonohos hvigor` after upgrading MoonOHOS.
    #|import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
    #|import { OhosHarContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
    #|import { spawnSync, SpawnSyncReturns } from 'child_process';
    #|import * as fs from 'fs';
    #|import * as os from 'os';
    #|import * as path from 'path';
    #|
    #|export interface MoonOHOSOptions {
    #|  /** moonohos.json, relative to the HAR module directory. */
    #|  config: string;
    #|  /** moonohos CLI; default: $MOONOHOS_CLI, ~/.moon/bin, then PATH. */
    #|  cli?: string;
    #|  /** HarmonyOS SDK; default: $MOONOHOS_SDK, then $DEVECO_SDK_HOME. */
    #|  sdk?: string;
    #|  /** ABIs to build; default: $MOONOHOS_ABIS (comma separated), then both. */
    #|  abis?: string[];
    #|  /** Build output, relative to the moonohos.json directory. */
    #|  out?: string;
    #|}
    #|
    #|interface Diagnostic {
    #|  stage: string;
    #|  code: string;
    #|  message: string;
    #|  context: string[];
    #|}
    #|
    #|interface Report {
    #|  ok: boolean;
    #|  result?: Record<string, object>;
    #|  diagnostics?: Diagnostic[];
    #|}
    #|
    #|const exe: string = process.platform === 'win32' ? '.exe' : '';
    #|
    #|function moonBin(): string {
    #|  const home: string = process.env.MOON_HOME ?? path.join(os.homedir(), '.moon');
    #|  return path.join(home, 'bin');
    #|}
    #|
    #|function findCli(options: MoonOHOSOptions, base: string): string {
    #|  if (options.cli) {
    #|    return path.resolve(base, options.cli);
    #|  }
    #|  if (process.env.MOONOHOS_CLI) {
    #|    return process.env.MOONOHOS_CLI;
    #|  }
    #|  const installed: string = path.join(moonBin(), 'moonohos' + exe);
    #|  return fs.existsSync(installed) ? installed : 'moonohos';
    #|}
    #|
    #|function findSdk(options: MoonOHOSOptions, base: string): string {
    #|  // Hvigor itself requires DEVECO_SDK_HOME (DevEco Studio sets it).
    #|  const sdk: string | undefined = options.sdk ? path.resolve(base, options.sdk)
    #|    : process.env.MOONOHOS_SDK ?? process.env.DEVECO_SDK_HOME;
    #|  if (!sdk) {
    #|    throw new Error('moonohos: HarmonyOS SDK not found; set `sdk` in moonohosPlugin(...), MOONOHOS_SDK '
    #|      + 'or DEVECO_SDK_HOME');
    #|  }
    #|  return sdk;
    #|}
    #|
    #|function run(cli: string, args: string[], cwd: string): Record<string, object> {
    #|  const env: NodeJS.ProcessEnv = { ...process.env };
    #|  const key: string = Object.keys(env).find((k) => k.toUpperCase() === 'PATH') ?? 'PATH';
    #|  env[key] = moonBin() + path.delimiter + (env[key] ?? '');
    #|  const child: SpawnSyncReturns<string> = spawnSync(cli, [...args, '--json'], {
    #|    cwd, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, windowsHide: true,
    #|  });
    #|  if (child.error) {
    #|    throw new Error(`moonohos: cannot run ${cli} (${child.error.message}); install it with `
    #|      + '`moon install shop1111/moonohos/cmd/moonohos` or set `cli` / MOONOHOS_CLI');
    #|  }
    #|  let report: Report;
    #|  try {
    #|    report = JSON.parse(child.stdout) as Report;
    #|  } catch (e) {
    #|    throw new Error(`moonohos ${args[0]} failed (exit ${child.status}):\n${child.stdout}${child.stderr}`);
    #|  }
    #|  if (!report.ok) {
    #|    const lines: string[] = (report.diagnostics ?? []).map((d: Diagnostic) =>
    #|      [`${d.stage} [${d.code}]: ${d.message}`, ...d.context.map((c: string) => '  ' + c)].join('\n'));
    #|    throw new Error(`moonohos ${args[0]} failed:\n${lines.join('\n')}`);
    #|  }
    #|  return report.result ?? {};
    #|}
    #|
    #|export function moonohosPlugin(options: MoonOHOSOptions): HvigorPlugin {
    #|  return {
    #|    pluginId: 'moonohos',
    #|    apply(node: HvigorNode): void {
    #|      const context: OhosHarContext = node.getContext(OhosPluginId.OHOS_HAR_PLUGIN) as OhosHarContext;
    #|      if (!context) {
    #|        throw new Error('moonohos: moonohosPlugin applies to HAR modules (system: harTasks)');
    #|      }
    #|      const preBuilds: string[] = [];
    #|      context.targets((target: Target) => {
    #|        preBuilds.push(target.getTargetName() + '@PreBuild');
    #|      });
    #|      node.registerTask({
    #|        name: 'moonohosBuild',
    #|        run: (): void => {
    #|          if (process.env.MOONOHOS_PLUGIN === 'off') {
    #|            // `moonohos har --assemble` already placed the package it was given.
    #|            console.log('moonohos: skipped (MOONOHOS_PLUGIN=off)');
    #|            return;
    #|          }
    #|          const module: string = context.getModulePath();
    #|          const config: string = path.resolve(module, options.config);
    #|          if (!fs.existsSync(config)) {
    #|            throw new Error(`moonohos: ${config} not found; check moonohosPlugin({ config })`);
    #|          }
    #|          const project: string = path.dirname(config);
    #|          const cli: string = findCli(options, module);
    #|          const out: string = path.resolve(project, options.out ?? '_build/moonohos/hvigor');
    #|          if (fs.existsSync(out)) {
    #|            // `moonohos build` publishes into a fresh directory; only replace a previous package.
    #|            if (!fs.existsSync(path.join(out, 'manifest.json'))) {
    #|              throw new Error(`moonohos: ${out} exists and is not a MoonOHOS package; choose another \`out\``);
    #|            }
    #|            fs.rmSync(out, { recursive: true, force: true });
    #|          }
    #|          const abis: string[] = options.abis
    #|            ?? (process.env.MOONOHOS_ABIS ? process.env.MOONOHOS_ABIS.split(',') : ['arm64-v8a', 'x86_64']);
    #|          const built = run(cli, ['build', '--config', config, '--sdk', findSdk(options, module),
    #|            '--abi', abis.join(','), '--out', out, '--cache'], project);
    #|          run(cli, ['har', '--dist', out, '--module', module], project);
    #|          console.log(`moonohos: ${context.getModuleName()} <- ${path.relative(module, config)} `
    #|            + `(${abis.join(', ')}, cache ${String(built['cache'])})`);
    #|        },
    #|        postDependencies: preBuilds,
    #|      });
    #|    },
    #|  };
    #|}
    #|
  ).replace_all(old="__VERSION__", new=moonohos_version())
}

///|
/// Published file name of the plugin inside the Hvigor project's `hvigor/`.
pub let hvigor_plugin_file : String = "moonohos-plugin.ts"

///|
/// `hvigorfile.ts` of a HAR module built by the plugin. `plugin_import` is
/// the plugin path relative to the module without extension, `config` the
/// bridge manifest relative to the module.
pub fn hvigor_har_module_file(
  plugin_import : String,
  config : String,
) -> String {
  "import { harTasks } from '@ohos/hvigor-ohos-plugin';\nimport { moonohosPlugin } from '" +
  plugin_import +
  "';\n\nexport default { system: harTasks, plugins: [moonohosPlugin({ config: '" +
  config +
  "' })] };\n"
}

///|
/// How `moonohos hvigor` treats a HAR module's existing `hvigorfile.ts`.
pub(all) enum HvigorfileUpdate {
  /// Already applies `moonohosPlugin`; left unchanged.
  Present
  /// The stock file DevEco Studio or `moonohos init` creates; replaced.
  Replace(String)
  /// Customised; the developer adds the returned lines by hand.
  Manual(String)
}

///|
/// Source text without comments and whitespace, `"` read as `'`, and without
/// `;` and trailing commas, for recognising the stock `hvigorfile.ts`.
fn hvigorfile_shape(text : String) -> String {
  let chars = text.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '/' && i + 1 < chars.length() && chars[i + 1] == '*' {
      i += 2
      while i + 1 < chars.length() && !(chars[i] == '*' && chars[i + 1] == '/') {
        i += 1
      }
      i += 2
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '/' {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
    } else {
      if c == '"' {
        out.write_char('\'')
      } else if c != ' ' && c != '\n' && c != '\r' && c != '\t' && c != ';' {
        out.write_char(c)
      }
      i += 1
    }
  }
  out.to_string().replace_all(old=",}", new="}").replace_all(old=",]", new="]")
}

///|
pub fn hvigorfile_update(
  existing : String,
  plugin_import : String,
  config : String,
) -> HvigorfileUpdate {
  if existing.contains("moonohosPlugin(") {
    return Present
  }
  let stock = "import{harTasks}from'@ohos/hvigor-ohos-plugin'exportdefault{system:harTasks,plugins:[]}"
  if hvigorfile_shape(existing) == stock {
    return Replace(hvigor_har_module_file(plugin_import, config))
  }
  Manual(
    "import { moonohosPlugin } from '" +
    plugin_import +
    "';\n// in plugins: moonohosPlugin({ config: '" +
    config +
    "' })",
  )
}

///|
/// `types/lib<name>/oh-package.json5`, as `moonohos build` writes it. `init`
/// writes it too so `ohpm install` resolves the HAR's type dependency before
/// the first build.
pub fn type_package_manifest(native_module : String) -> String {
  let json : Json = {
    "name": "lib" + native_module + ".so",
    "version": moonohos_version(),
    "types": "./index.d.ts",
  }
  json.stringify(indent=2)
}
