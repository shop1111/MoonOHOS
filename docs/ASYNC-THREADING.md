# 异步任务与线程模型

本文记录 MoonOHOS 0.4 异步任务的线程规则、生命周期和验证依据。适用于 moonc ≥ 0.10.16（0.4.0 在 moonc `v0.10.14+7d59c7ec9` 上建立，0.4.1 在 `v0.10.18+6c83a7f62` 上复验）、HarmonyOS SDK API 26。

## 结论

- MoonBit 代码可以在 Node-API 工作线程执行，但**同一进程内任一时刻只有一个线程运行 MoonBit**。
- ArkTS 线程只负责参数复制、创建 Promise 和生成结果；耗时计算期间 UI 线程不被占用。
- 异步任务可通过 `CancelToken` 协作取消，句柄（handle）可被显式关闭、垃圾回收或环境销毁释放，三条路径只释放一次。

## 依据

### 运行时事实

MoonBit 运行时（`$MOON_HOME/lib/runtime/runtime.c`）的引用计数是非原子读写，循环回收的候选根列表是文件级全局变量；运行时源码中没有 `thread_local`、`_Thread_local`、`__thread`、`pthread` 或原子操作。因此：

1. 不能让两个线程同时接触 MoonBit 对象。
2. 只要所有 MoonBit 对象的创建、调用、读取和释放都在同一把进程锁内完成，就可以在不同线程上执行——互斥锁提供 happens-before 关系。
3. 必须使用系统分配器（`MOONBIT_ALLOCATOR_SYSTEM`）；mimalloc 的线程本地堆不适用于这种跨线程交接。

### 探针

| 探针 | 结果 | 证据 |
|---|---|---|
| 宿主：8 个线程 × 20000 轮并发调用生成的桥接函数（ASan） | 无失败，结束时活跃分配为 0 | [thread-probe](evidence/v0.4/host-thread_probe.log) |
| 模拟器：手写探针库在 `napi_create_async_work` 中运行 MoonBit | 工作线程 tid 与 JS 线程不同；4 亿轮计算 748 ms 期间 JS 定时器触发 106 次，同步调用期间为 0 | [probe-runtime](evidence/v0.4/probe-runtime.log) |
| 模拟器：协作取消 | 取消后约 100 ms 返回 | 同上 |
| 模拟器：execute 内读取 RawFile | 校验和正确 | 同上 |
| 模拟器：工作线程递归 50000 层 | 正常返回 | 同上 |
| 模拟器：ArkTS Worker `terminate()` 时仍有运行中和排队任务 | Worker 环境先等待任务完成并调用 complete，再执行 env cleanup hook | 同上 |

探针源码见 [fixtures/async_probe](../fixtures/async_probe)。

## 生成代码的执行阶段

```text
ArkTS 线程                         Node-API 工作线程                 ArkTS 线程
Call_f                              Execute_f                        Complete_f
 ├ 读取参数为 C++ 数据（复制）      ├ 已取消则直接结束               ├ 删除 async work（仅一次）
 ├ 固定（pin）句柄参数              ├ 获取进程门 GateLock            ├ 环境关闭中：只释放 C++ 状态
 ├ 获取平台适配对象（如 RawFile）   ├ 设置当前 CancelToken          ├ 成功：创建结果 / 句柄对象，resolve
 ├ 创建 Promise 与 async work       ├ 构造 MoonBit 输入、调用、复制  ├ 失败：带 code 的错误 reject
 └ 入队（失败则同步清理）           └ 释放所有 MoonBit 引用后解锁    └ 释放适配对象、解除句柄固定
```

`Execute_f` 中不调用任何 Node-API；`Call_f`/`Complete_f` 中不接触 MoonBit 对象（句柄结果在门内取得所有权后交给 `HandleState`）。宿主测试会检查生成的 `Execute_*` 函数体不包含 `napi_` 调用。

## 规则

### 进程门（Gate）

- 同步调用、异步任务和所有 ArkTS 环境共享一把门。
- 门首次获取时初始化 MoonBit 运行时（每进程一次）。
- JS 线程需要释放句柄而门正被长任务占用时，释放请求进入延迟队列，由持门线程在解锁前处理，JS 线程不阻塞。
- 同步调用在长任务执行期间会等待门；长时间计算应导出为异步函数，交互查询可保留同步变体（示例中的 `search_now`）。

### 取消

- 异步函数的最后一个参数是可选的 `CancelToken`，由 `createCancelToken()` 创建。
- 入队前或开始执行前已取消：任务不进入 MoonBit，直接以 `AbortError`（`code = ERR_MOONOHOS_CANCELLED`）拒绝。
- 执行中取消：MoonBit 代码通过 `@task.cancelled()` 或 `@task.check()` 观察；即使 MoonBit 因取消而抛出错误，结果仍报告为取消。
- 执行结束后才取消：若结果是句柄，在门内丢弃并释放，Promise 以取消拒绝。
- 取消是协作式的：不轮询的 MoonBit 循环会运行到结束。

### 句柄

- 句柄是带 `close()`、`isClosed()` 的 ArkTS 对象，内部持有一个 MoonBit 引用。
- 调用时句柄被固定（pin）；关闭正在被任务使用的句柄会推迟到最后一次解除固定时释放。
- 关闭后再使用得到 `ERR_MOONOHOS_CLOSED`；重复关闭无副作用。
- 释放路径：显式 `close()`、对象终结器、环境清理钩子。ArkRuntime 不保证终结器及时运行，应用应显式关闭（示例中的 `SearchSession.close()` 在页面 `aboutToDisappear` 中调用）。

### 回调（开发中，未发布）

清单参数类型写作 `(T1, T2) -> Unit`，ArkTS 侧是 `(arg0: T1, arg1: T2) => void`。业务函数收到的是生成的 MoonBit 闭包，不是 ArkTS 函数：包装层把 ArkTS 函数换成本次调用的编号（`Int64`），闭包把参数降为边界形式（Option 为数组、枚举为整数标签）后调用桥接层的 `moonohos_event_<函数>_<参数序号>`。桥接层在门内把参数复制为 C++ 数据，此后不再接触 MoonBit 对象。

| | 同步函数 | 异步函数 |
|---|---|---|
| 执行线程 | 调用期间在 ArkTS 线程直接调用（每次一个 handle scope） | 工作线程入队 `napi_call_threadsafe_function`（非阻塞、队列不限长），在 ArkTS 线程按入队顺序调用 |
| 与结果的顺序 | 函数返回前全部执行完 | `Complete` 时若仍有排队的回调，任务暂存，最后一个回调执行后才 resolve/reject |
| 回调中调用本模块 | 允许：进程门对持有线程可重入，取消与回调作用域会在嵌套调用后恢复 | 回调运行时工作线程可能仍持有门，回调中的同步调用会等待任务结束 |
| 回调抛错 | 后续回调跳过；`@task.check()`/`@task.cancelled()` 看到取消；MoonBit 返回后抛出该错误（优先于业务错误） | 同左，Promise 以该错误拒绝 |
| 参数无法转换（如非有限 Double、超出转换上限） | 不调用 ArkTS，按 RangeError/TypeError 失败 | 同左，拒绝 |

规则：

- 只有本次调用正在运行时，闭包调用才会送达。业务代码把闭包保存起来，调用返回后再调用，会因编号不匹配被忽略。
- 用户的 `CancelToken` 不会因回调失败而被置为取消；失败只影响本次调用。
- 线程安全函数在 ArkTS 线程创建，任务结算时释放；每个异步任务最多一个。环境销毁时，排队中的回调不再执行，暂存的任务直接释放（计入 `cancelledTasks`）。
- 工作线程上唯一的 Node-API 调用是事件函数中的 `napi_call_threadsafe_function`，它按规范可在任意线程调用；`Execute_*` 函数体本身仍不含 Node-API 调用。
- 回调的每次调用单独计算转换上限（深度 32、元素数和字节数同上）。

### 环境销毁

- 每个 ArkTS 环境注册 env cleanup hook：标记关闭、取消该环境登记的令牌、关闭其句柄。
- 探针显示 Worker 终止会先等待运行中的 async work 完成，cleanup hook 之后才运行。因此**销毁 Worker 前应先取消令牌**，否则终止会等到任务自然结束。
- 关闭后到达的 complete 不再创建 JS 值，只释放本地状态。

### 错误

| 情况 | 同步调用 | 异步调用 |
|---|---|---|
| 参数类型错误 | 抛出 `TypeError` | 同步抛出 `TypeError` |
| 数值/容量越界 | 抛出 `RangeError` | 同步抛出或拒绝 `RangeError` |
| 句柄已关闭 | `Error`，`code = ERR_MOONOHOS_CLOSED` | 同左 |
| MoonBit `raise`（清单 `"raises": true`） | `Error`，`code = ERR_MOONOHOS_BUSINESS`，消息为错误的 `Show` 文本 | 拒绝，同左 |
| 取消 | — | `AbortError`，`code = ERR_MOONOHOS_CANCELLED` |
| 本地分配失败 | `Error`，`code = ERR_MOONOHOS_NATIVE` | 拒绝，同左 |

MoonBit `panic` 仍会终止进程，不能当作业务错误。设备验证发现 ArkRuntime 以空 `code` 调用 `napi_create_type_error`/`napi_create_range_error` 时不会得到对应类型，因此同步转换错误使用 `napi_throw_type_error`/`napi_throw_range_error`，创建错误对象时总是带 `ERR_MOONOHOS_*` code。

### 诊断

每个模块导出 `moonohos_diagnostics()`，返回进程级计数：`liveHandles`、`releasedHandles`、`pendingTasks`、`completedTasks`、`cancelledTasks`、`envCleanups`。设备脚本用它确认离开页面后句柄和任务归零。

## 验证范围

| 层级 | 覆盖 | 不覆盖 |
|---|---|---|
| 宿主 ASan（Node-API 替身，execute 在真实线程上运行） | 句柄关闭/终结/固定中关闭，异步结果，业务错误，执行前/中取消，RawFile 适配，环境销毁时的排队与运行任务，Call/Complete 中每个 Node-API 失败点，800 个并发任务，10000 轮无分配增长 | ArkRuntime 的真实调度、终结器时机 |
| x86_64 模拟器（API 26） | 工作线程执行、UI 定时器不中断、取消、离开页面取消并释放、重新进入、诊断归零 | ARM64 真机、旧 SDK、ArkTS Worker 中使用生成模块的完整场景 |

宿主替身不验证 HarmonyOS 加载器；模拟器结果不代表 ARM64 真机性能。
