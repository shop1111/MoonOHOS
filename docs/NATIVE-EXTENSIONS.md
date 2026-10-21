# Native 依赖扩展机制

MoonOHOS 0.4 允许 MoonBit 包携带 C stub 进入 HarmonyOS 动态库，但只接受**带描述文件、可复现交叉编译**的包。0.3 会拒绝任何 `native-stub`，因此依赖 C 的 MoonBit 库无法复用。

## 描述文件

带 stub 的包在 `moon.pkg` 旁放置 `moonohos.native.json`：

```json
{
  "schema": "moonohos-native-v1",
  "package": "shop1111/moonohos_ohos/rawfile",
  "sources": ["rawfile_stub.c"],
  "includeDirs": [],
  "defines": [],
  "systemLibraries": ["librawfile.z.so"],
  "abis": ["arm64-v8a", "x86_64"],
  "adapters": [{
    "type": "Manager",
    "arkType": "resourceManager.ResourceManager",
    "arkImport": "import { resourceManager } from '@kit.LocalizationKit';",
    "acquire": "moonohos_rawfile_acquire",
    "release": "moonohos_rawfile_release"
  }]
}
```

| 字段 | 规则 |
|---|---|
| `package` | 必须等于编译器链接该目录时使用的包名 |
| `sources` | 必须与 `moon.pkg` 的 `native-stub` 列表完全一致；只接受包内相对路径的 `.c` 文件 |
| `includeDirs` | 包内相对目录；包目录本身总是加入头文件路径 |
| `defines` | `NAME` 或 `NAME=value`；不得覆盖 `MOONOHOS_BRIDGE`、`MOONOHOS_TARGET_OHOS` |
| `systemLibraries` | 必须在白名单内（当前为 `libhilog_ndk.z.so`、`librawfile.z.so`、`libdeviceinfo_ndk.z.so`），并且所选 SDK 对每个 ABI 都提供该库 |
| `abis` | 必须覆盖本次构建的所有 ABI |
| `adapters` | 可选；声明 ArkTS 对象到 C 指针的参数适配，`acquire`/`release` 必须以 `moonohos_` 开头，`arkImport` 只能是 `import { 名称 } from '@kit.套件';` |

## 构建流程

1. 暂存模块（或其 `moon.work` 工作区全部成员），运行 `moon info` 解析依赖。
2. 扫描暂存树和 `.mooncakes`：
   - 发现 `pre-build`、自定义 `rule`、`cc-flags`、`cc-link-flags`、`stub-cc` 等无法在 OHOS 上复现的配置时直接失败；
   - 记录所有带 `native-stub` 的包及其描述文件，描述文件不合法时失败。
3. 绑定清单中的 `@包.类型` 参数：用目标包 `.mbti` 的 `import` 段确定完整包名，再查找对应描述文件中的适配器。
4. 生成桥接包并读取 `moon build --dry-run` 的 `link-core` 步骤：只有实际链接进动态库的包才参与本地编译；链接到的包带 stub 却没有描述文件时失败，并说明原因（例如 `moonbitlang/async` 的事件循环不能在 HarmonyOS 模块中运行）。
5. 把 stub 源码和同目录头文件复制到 `work/native/deps/<序号>/`，生成的 CMake 增加源码、头文件路径、`MOONOHOS_BRIDGE=1 MOONOHOS_TARGET_OHOS=1` 和声明的 NDK 库。
6. 产物清单（`moonohos-build-v2`）记录每个依赖的包名、描述文件 SHA256、源码 SHA256、系统库和适配器；`verify` 只允许 ELF 依赖基础库与清单声明的白名单库。

## 编写 stub

- `MOONOHOS_TARGET_OHOS` 定义时调用真实 SDK；否则提供宿主回退，使 `moon test` 和宿主 ASan 测试可以在 Windows 上运行。
- `MOONOHOS_BRIDGE` 定义时可以使用生成桥接提供的符号（例如 `moonohos_bridge_cancelled`），以及编写适配器函数。
- 适配器函数签名为 `void *acquire(void *env, void *value)` 与 `void release(void *ptr)`，在 ArkTS 线程调用；返回 `NULL` 时调用方得到 `TypeError`。适配对象只在一次同步调用或一个异步任务期间有效，结束后释放，MoonBit 代码不得保存。

## 首批平台包（`ohos/`，模块 `shop1111/moonohos_ohos`）

| 包 | 能力 | 系统库 |
|---|---|---|
| `hilog` | `Logger::new(domain, tag)`，`debug/info/warn/error/fatal`，`is_loggable`；消息总是以 `%{public}s` 参数传入，不会被当作格式串 | `libhilog_ndk.z.so` |
| `rawfile` | `read`、`read_text`、`list`；`Manager` 由 ArkTS `resourceManager` 适配获得；路径必须在 rawfile 目录内，单文件上限 64 MiB | `librawfile.z.so` |
| `task` | `cancelled()`、`check()`，读取当前异步任务的 `CancelToken`；同步调用中始终为未取消 | 无 |

`ohos` 模块已发布为 Mooncakes 包 `shop1111/moonohos_ohos@0.4.0`，`moonohos init` 生成的工程默认从注册表依赖它；仓库内示例和 `moonohos init --ohos <路径>` 通过 `moon.work` 工作区引用本地目录。构建时工作区全部成员被复制到 `work/ws/m<序号>`，原始目录不被修改。
