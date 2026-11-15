# Hvigor 插件：在 DevEco Studio 中直接构建 MoonBit 模块

本文说明 MoonOHOS Hvigor 插件的用法、工作方式和验证范围（0.10 起）。

## 用途

没有插件时，修改 MoonBit 代码后要先在命令行运行 `moonohos build` 和 `moonohos har`，再回到 DevEco Studio 构建应用。插件把这两步挂进 Hvigor 的构建流程：在 DevEco Studio 中点 Build 或 Run，或在命令行运行 `hvigorw assembleHap`，都会先编译 MoonBit 代码，再把 `.so`、类型声明和 ArkTS 门面放进 HAR 模块。

插件本身不重新实现构建逻辑，只调用 `moonohos` CLI。产物和命令行构建完全相同：同样的校验、同样的 `manifest.json`、同样的错误分类。

## 新工程

`moonohos init` 生成的工程已经接好插件：

```text
harmony/
  hvigor/moonohos-plugin.ts              # 插件（由 CLI 写入，不要手改）
  <name>/hvigorfile.ts                   # plugins: [moonohosPlugin({ config: '../../moonohos.json' })]
  <name>/src/main/cpp/types/lib<name>/oh-package.json5   # 类型包描述，提交到仓库
```

在 DevEco Studio 中打开 `harmony/`，同步后直接运行 `entry` 即可。第一次构建会编译两个 ABI（几十秒）；之后源码不变时命中 `--cache`，约 7 秒。

类型包的 `oh-package.json5` 要提交：DevEco 同步时 ohpm 先解析 HAR 的 `lib<name>.so` 依赖，目录不存在会直接报错，这时插件还没有机会运行。`index.d.ts`、`libs/` 和 `src/main/ets/generated/` 由构建生成，已在 `.gitignore` 中。

## 已有工程

对已有的 HAR 模块运行：

```bash
moonohos hvigor --module harmony/<name> --config moonohos.json
```

命令会：

1. 写入（或更新）`<Hvigor 工程>/hvigor/moonohos-plugin.ts`；
2. 如果模块的 `hvigorfile.ts` 仍是 DevEco 或 `init` 生成的默认内容，改为应用插件；已应用时不变；内容被改过时不修改，在结果的 `manual` 字段给出需要手动添加的两行；
3. 补齐类型包 `oh-package.json5`，并在模块 `oh-package.json5` 中加入 `lib<name>.so` 依赖。

升级 MoonOHOS 后重新运行这条命令即可更新插件文件。

## 配置

```typescript
moonohosPlugin({
  config: '../../moonohos.json',   // 必填，相对 HAR 模块目录
  cli: '...',                      // 可选，moonohos 可执行文件
  sdk: '...',                      // 可选，HarmonyOS SDK 目录
  abis: ['x86_64'],                // 可选，默认两个 ABI
  out: '_build/moonohos/hvigor',   // 可选，相对 moonohos.json 所在目录
})
```

| 项 | 查找顺序 |
|---|---|
| CLI | `cli` → 环境变量 `MOONOHOS_CLI` → `~/.moon/bin/moonohos`（`moon install` 的位置，`MOON_HOME` 可改）→ PATH |
| SDK | `sdk` → `MOONOHOS_SDK` → `DEVECO_SDK_HOME`。Hvigor 本身要求 `DEVECO_SDK_HOME`，DevEco Studio 运行 Hvigor 时会设置 |
| ABI | `abis` → `MOONOHOS_ABIS`（逗号分隔）→ `arm64-v8a,x86_64`。只在模拟器上调试时设 `MOONOHOS_ABIS=x86_64`，构建时间约减半 |

插件运行 CLI 时把 `~/.moon/bin` 加到 PATH 前面，因为 `moonohos build` 要调用 `moon` 和 `moonc`；从桌面启动的 DevEco Studio 不一定继承终端里的 PATH。

## 工作方式

```text
DevEco Build / hvigorw assembleHap
  └─ <HAR 模块>:moonohosBuild                       ← 插件注册的任务
       ├─ moonohos build --config … --sdk … --abi … --out _build/moonohos/hvigor --cache --json
       └─ moonohos har --dist _build/moonohos/hvigor --module <HAR 模块> --json
  └─ <HAR 模块>:<target>@PreBuild                    ← moonohosBuild 是它的前置任务
  └─ … CompileArkTS、ProcessLibs、打包 HAR/HAP
```

- 任务通过 `postDependencies` 排在模块每个 target 的 `PreBuild` 之前（target 名称从 `OhosHarContext.targets()` 读取）。构建依赖这个 HAR 的应用模块时，Hvigor 同样会先执行它。
- `moonohos build` 只发布到新目录，插件每次先删除自己的输出目录；目录存在但不是 MoonOHOS 包（没有 `manifest.json`）时报错，不删除。
- 增量判断交给 CLI 的 `--cache`：键包含暂存后的源码和依赖、编译器、运行时、SDK 头文件和构建配置。命中时直接恢复已校验的产物，不重新编译。耗时主要在对 SDK 头文件计算指纹。
- `moonohos har` 写入当前构建的 ABI，并删除 HAR 模块中上次留下的其他 ABI 的库，避免切换 `MOONOHOS_ABIS` 后打进旧代码。
- 失败时 CLI 的诊断原样成为 Hvigor 错误。编译器输出中暂存副本的路径（`_build/moonohos/work-N/ws/m0/...`）会改写回原始源文件，DevEco 的 Build 窗口显示的是 `core/lib.mbt:4:17` 这样的真实位置。

## 范围

- 只支持 HAR 模块（`system: harTasks`）。HAP 或 HSP 模块通过依赖 HAR 模块使用 MoonBit 代码。
- 插件是 Hvigor 工程内的一个 TypeScript 文件，由 `hvigorfile.ts` 相对导入，不需要在 `hvigor-config.json5` 中声明依赖，也不需要联网安装。暂未发布到 npm。
- 不修改 DevEco、SDK、Node、ohpm 或全局环境。

## 验证

| 场景 | 结果（Hvigor 6.26.4，DevEco Studio 自带工具，Windows x64） |
|---|---|
| 新 `init` 工程，只运行 `ohpm install` 和 `hvigorw assembleHap`（entry） | 通过：HAP 含 `libs/arm64-v8a` 和 `libs/x86_64` 两个库；首次 moonohosBuild 约 17–68 秒，缓存命中约 7 秒 |
| HAR 模块单独 `assembleHar`，`MOONOHOS_ABIS=x86_64` | 通过：HAR 只含 x86_64 库，上次构建的 arm64 库被删除 |
| MoonBit 编译错误 | Hvigor 构建失败，错误位置指向 `core/lib.mbt` |
| 检索示例副本运行 `moonohos hvigor` 后 `assembleHar` | 通过：默认 `hvigorfile.ts` 被改写，第二次运行报告 `present` |
| `scripts/verify_init_flow.ps1` | 在原有 CLI 流程之外，增加一个只用 Hvigor 构建的新工程 |
| `scripts/verify_cli.py` | `hvigor` 命令：已应用、改写默认文件、缺少 `--module`、非 HAR 模块 |

尚未验证：DevEco Studio 图形界面中的 Build/Run（Hvigor daemon 模式），macOS 和 Linux 上的 command-line-tools。
