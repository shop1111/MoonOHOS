# 取消与生命周期

每个异步调用可以携带 CancelToken。页面退出时取消令牌，MoonBit 循环通过 task 包检查取消状态，
任务以 AbortError 结束。索引句柄调用 close 后释放，任务仍在使用时延迟到任务完成再释放。
