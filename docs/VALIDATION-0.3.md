# MoonOHOS 0.3 验证记录

验证日期：2026-10-03。固定 Moon `0.1.20260920 (914d7da)`、moonc `v0.10.14+7d59c7ec9`、Core `0.10.14+7d59c7ec9`、async `0.21.0`；DevEco Native SDK API 26（26.0.0.105）。

## 实际结果

| 检查 | 结果 | 证据 |
|---|---|---|
| MoonBit | 32 项工具链测试、2 项示例核心测试通过；格式、严格 Native 检查、接口生成、Release CLI 和打包通过 | 源码测试及 `pkg.generated.mbti` |
| 生产代码 | 4002 行；仅统计跟踪的生产 `.mbt`，排除测试、示例、fixture、注释和字符串/模板正文 | [逐文件统计](evidence/v0.3/production-lines.json)、`scripts/count_production.py` |
| 开发历史 | 保留首个提交及 13 项功能交付，另有统计规则、共享依赖分析和 ELF 一致性修复；不重写历史 | `git log --oneline --reverse` |
| 类型 | 全部叶子类型数组、嵌套数组、嵌套记录、记录数组、空容器、混合字段及别名返回通过 | `fixtures/array_core`、`fixtures/record_core` |
| 所有权 | 固定版本生成代码确认借用参数，返回及引用字段读取增引用；C++ 只调用生成的访问接口 | [编译探针](evidence/v0.3/ownership-probe.txt) |
| 宿主 ASan | 原标量、String/Bytes、返回类型矩阵、Array、Struct 均通过；各复杂 fixture 10000 轮，存活分配增量为零 | [引用回归](evidence/v0.3/host-reference.log)、[数组](evidence/v0.3/host-array.log)、[记录](evidence/v0.3/host-record.log)、[矩阵](evidence/v0.3/host-matrix.log) |
| CLI | 23 项实际 CLI 场景通过：文本/JSON、退出码、中文空格路径、缓存命中/失效/恢复、损坏包及重算校验值后的 ELF 损坏 | `实际 CLI 结果 JSON（运行脚本写入 `_build/CLI 中文 空格-*/results.json`）`，复现使用 `scripts/verify_cli.py` |
| 超时 | 实际子进程超时取消及非零退出测试通过 | `cmd/moonohos/runner_wbtest.mbt` |
| 干净构建 | 中文空格路径下 11 项集成检查通过，两个 ABI 均生成 ELF；原始业务源码保持不变 | `_build/integration/run-x975qii5/results.json` |
| ELF | AArch64 / x86-64、注册符号、动态依赖及可重定位分发结构通过 | [arm64-v8a](evidence/v0.3/elf-arm64-v8a.log)、[x86_64](evidence/v0.3/elf-x86_64.log)，CLI `verify` |
| HAP | Hvigor 构建成功，包含两个 ABI 的 `.so` | `examples/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap` |
| x86_64 模拟器 | Pura 90 Pro：13 项标量、14 项引用、10 项容器检查，1000 轮重复调用和两次进程重启通过 | [运行日志](evidence/v0.3/runtime.log)、[截图](evidence/v0.3/page.jpeg)、[HAP SHA256](evidence/v0.3/hap-sha256.json) |
| Windows CI | [固定编译器发行归档及校验值](evidence/v0.3/toolchain-archive.json)和 Core，执行格式、严格 Native 检查、测试、接口一致性、CLI、打包、代码量门槛和 ASan | `.github/workflows/windows.yml`；运行状态见 [Actions](https://github.com/shop1111/MoonOHOS/actions) |
| ARM64 真机 | 未运行，仅有编译验证 | 不推断运行成功 |

## 容器及失败边界

引用参数从输入复制完成后持有到调用结束；返回值与每次引用字段/元素读取均各持有一份引用，分别释放，即使指针相同也不去重。构造记录及追加数组时，临时子对象由 RAII 持有。C++ 不读取 MoonBit Array/Struct 的布局。

宿主替身覆盖数组空洞、错误元素、缺失自有字段、null、Sendable、循环对象、重复非循环对象的独立复制、后续参数失败及字段/索引诊断。容量边界包含 32 层、1048576 节点和 64 MiB 的精确预算边界及超限，并让实际生成的读取代码拒绝过大的文本长度。对正常 Node-API 操作逐项注入失败及 pending exception；C++ 分配 failpoint 覆盖转换缓冲区及结果创建。ASan 检查越界和释放错误，宿主专用 malloc/free 计数补充泄漏验证。这些失败注入是宿主测试，不声称是设备故障注入。

生产统计排除纯字符串列表或元组，即使该行带逗号或括号；正常格式化后的代码结束行仍作为代码统计。共享记录的高度缓存避免 DAG 分支被重复递归，并在每次使用时重新核对深度边界。32 层、每层两个共享字段的测试通过。

CLI 校验器同时检查文件完整性、SHA256、类型包名称和版本、CMake 导入、ELF64 标头/节表/程序段、动态段与动态节的一致性、映射范围、架构、注册符号及依赖。损坏 ELF 的测试先重算文件校验值，再验证二进制解析确实拒绝损坏内容。分发 manifest 不含 SDK 绝对路径，CLI 构建结果保持 `runtime: not_run`。

类型分析拒绝循环依赖、超过深度的类型、签名不一致、未知类型、泛型、`#value`、不可访问或不完整字段。包装包由固定编译器再次核对，不通过整行文本匹配判断签名。生成规划检测业务导出、原始导出和访问函数之间的符号冲突。

## 设备证据

```text
10-03 19:19:15.759 21755 21755 I A00000/MoonOHOS: MOONOHOS_RUNTIME_PASS version=0.3.0 add=42 scalar_checks=13 reference_checks=14 container_checks=10 repeated_calls=1000
10-03 19:19:18.743 21872 21872 I A00000/MoonOHOS: MOONOHOS_RUNTIME_PASS version=0.3.0 add=42 scalar_checks=13 reference_checks=14 container_checks=10 repeated_calls=1000
```

页面展示 `Sample[] → Analysis: count=2, total=42`、嵌套数值数组和 `MoonBit` 来源。复制独立性、空容器、重复共享输入及数组空洞均在设备页面自检中执行。宿主复杂类型重复 10000 轮；设备重复 1000 轮，二者分别记录。

首次模拟器启动因虚拟内存不足退出；释放闲置应用后启动成功。首次验收期间模拟器退出导致连接中断，重启模拟器并重新安装同一 HAP 后，完整两次应用重启验收通过。失败记录没有作为成功证据。未修改 SDK、签名、模拟器内存配置或系统分页设置。

HAP SHA256：`3A173D2EC6F35450BF392AEF211C53310FD6B8C8E2399EAF44F43AA0C52A5767`。

## 复现

按 README 构建 Release CLI，运行 `verify_cli.py --sdk <SDK>`、`verify_integration.py <SDK>`，再运行两个 `verify_containers.py` fixture。`verify_host.py _build/moonohos/work-12` 复现当前主示例标量/引用回归；新构建应使用实际返回的工作目录。`build_example.ps1 -Package _build/moonohos/dist-v0.3` 生成 HAP，设备连接后运行 `verify_device.ps1`。

0.1 和 0.2 文档、截图、日志、标签均保留。0.3 证据独立存放。ARM64 真机、旧 SDK、异步、多线程、零复制和独立 OpenHarmony 产品尚未验证。
