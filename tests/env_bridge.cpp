// Host ASan checks for several ArkTS environments in one process (0.7): the UI
// thread, a Worker and TaskPool threads each load the module into their own
// env. Every env gets its own EnvState through Init, handles and tasks stay
// with the env that created them, envs run concurrently on their own threads,
// and tearing one env down leaves the others working.
#include "napi_init.cpp"
#include <cassert>
#include <iostream>
#include <thread>
extern "C" size_t moonohos_live_allocations(void);
extern "C" const char *moonohos_host_adapter_text(void *) { return nullptr; }

static Value Number(double x) { return {napi_number, x, false}; }

struct Module {
  Env env;
  Value exports;
  Module() { env.stable_results = true; exports.type = napi_object; assert(Init(&env, &exports) == &exports); }
  napi_value Call(const char *name, std::vector<napi_value> args) {
    env.exception.clear(); env.message.clear();
    return CallMethod(&env, exports, name, std::move(args));
  }
  napi_value On(napi_value object, const char *name, std::vector<napi_value> args = {}) {
    env.exception.clear(); env.message.clear();
    return CallMethod(&env, *object, name, std::move(args));
  }
  double Diag(const char *field) {
    auto *diag = Call("moonohos_diagnostics", {});
    assert(diag); return diag->properties.at(field)->number;
  }
};
static Value &Resolved(napi_value promise) { assert(promise && promise->promise_state == 2); return *promise->settled; }

// Each env binds its own state: exports of two envs never share callback data.
static void SeparateState() {
  Module ui, worker;
  assert(ui.Diag("liveEnvs") == 2 && worker.Diag("liveEnvs") == 2);
  assert(ui.exports.properties.at("open_counter")->method_data != worker.exports.properties.at("open_counter")->method_data);
  Value five = Number(5), two = Number(2);
  napi_value a = ui.Call("open_counter", {&five});
  napi_value b = worker.Call("open_counter", {&two});
  assert(ui.On(a, "add", {&two})->number == 7 && worker.On(b, "add", {&five})->number == 7);
  // Async work completes in the env that queued it.
  napi_value later_a = ui.Call("add_later", {a, &two});
  napi_value later_b = worker.Call("add_later", {b, &two});
  worker.env.RunWorks();
  assert(later_a->promise_state == 1 && Resolved(later_b).number == 9);
  ui.env.RunWorks();
  assert(Resolved(later_a).number == 9);
  ui.On(a, "close"); worker.On(b, "close");
  assert(ui.Diag("liveHandles") == 0);
}

// A Worker terminating mid-task: its handles close and its tasks never touch
// JS again, while the UI env keeps its handle and finishes its own work.
static void WorkerTeardown() {
  Module ui;
  Value five = Number(5), huge = Number(2000000000);
  napi_value kept = ui.Call("open_counter", {&five});
  double cleanups = ui.Diag("envCleanups");
  {
    Module worker;
    assert(ui.Diag("liveEnvs") == 2);
    napi_value counter = worker.Call("open_counter", {&five});
    napi_value queued = worker.Call("add_later", {counter, &five});
    napi_value spinning = worker.Call("spin", {&huge});
    assert(queued && spinning && ui.Diag("pendingTasks") == 2 && ui.Diag("liveHandles") == 2);
    worker.env.Teardown();
    worker.env.RunWorks();
    assert(queued->promise_state == 1 && spinning->promise_state == 1);
    assert(ui.Diag("liveEnvs") == 1 && ui.Diag("envCleanups") == cleanups + 1);
    assert(ui.Diag("liveHandles") == 1 && ui.Diag("pendingTasks") == 0);
  }
  napi_value later = ui.Call("add_later", {kept, &five});
  ui.env.RunWorks();
  assert(Resolved(later).number == 10);
  ui.On(kept, "close");
  assert(ui.Diag("liveHandles") == 0);
}

// UI thread and three TaskPool threads call sync functions and run async work
// at the same time, each through its own env; the gate serializes MoonBit.
static void ConcurrentEnvs() {
  const int threads = 4, rounds = 500;
  std::vector<std::thread> workers;
  std::atomic<int> failures{0};
  for (int t = 0; t < threads; ++t) {
    workers.emplace_back([t, rounds, &failures] {
      Module m;
      Value start = Number(t), one = Number(1);
      napi_value counter = m.Call("open_counter", {&start});
      for (int i = 0; i < rounds; ++i) {
        napi_value sum = m.On(counter, "add", {&one});
        if (!sum || sum->number != t + i + 1) failures.fetch_add(1);
      }
      napi_value later = m.Call("add_later", {counter, &one});
      m.env.RunWorks(true);
      if (later->promise_state != 2 || later->settled->number != t + rounds + 1) failures.fetch_add(1);
      m.On(counter, "close");
    });
  }
  for (auto &worker : workers) worker.join();
  assert(failures.load() == 0);
  Module check;
  assert(check.Diag("liveEnvs") == 1 && check.Diag("liveHandles") == 0 && check.Diag("pendingTasks") == 0);
}

int main() {
  // Warm up: runtime initialization allocates once per process.
  { Module m; Value one = Number(1); m.On(m.Call("open_counter", {&one}), "close"); }
  auto before = moonohos_live_allocations();
  SeparateState();
  WorkerTeardown();
  for (int i = 0; i < 20; ++i) ConcurrentEnvs();
  auto after = moonohos_live_allocations();
  if (after != before) std::cerr << "allocation delta " << (long long)(after - before) << std::endl;
  assert(live_envs.load() == 0 && live_handles.load() == 0 && pending_tasks.load() == 0);
  assert(moonohos_live_allocations() == before);
  std::cout << "HOST_ENV_PASS separate_state/worker_teardown/concurrent_envs=4x20 live_envs=0 live_handles=0 pending=0\n";
}
