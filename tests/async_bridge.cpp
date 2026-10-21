// Host ASan checks for async tasks, handles, adapters and business errors.
// Executes run on real worker threads; Node-API calls stay on this thread.
#include "napi_init.cpp"
#include <atomic>
#include <cassert>
#include <chrono>
#include <iostream>
#include <thread>
extern "C" size_t moonohos_live_allocations(void);

// ArkTS stand-in for resourceManager: a string naming the rawfile directory.
extern "C" const char *moonohos_host_adapter_text(void *value) {
  thread_local std::string text;
  auto *v = static_cast<Value *>(value);
  if (v->type != napi_string) return nullptr;
  text = Utf8(v->text);
  return text.c_str();
}

static Value Number(double x) { return {napi_number, x, false}; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) {
  Value v; v.type = napi_object; v.kind = OrdinaryArray;
  for (auto &child : children) v.elements.push_back(Clone(child)); return v;
}
static std::u16string U16(const std::string &text) { return std::u16string(text.begin(), text.end()); }
static std::string FixtureRoot() {
  std::string file = __FILE__;
  auto cut = file.find_last_of("/\\");
  return file.substr(0, cut) + "/../fixtures/async_core/testdata";
}

struct Module {
  Env env;
  Value exports;
  Module() { exports.type = napi_object; assert(Init(&env, &exports) == &exports); }
  napi_value Call(const char *name, std::vector<napi_value> args) {
    env.exception.clear(); env.message.clear();
    return CallMethod(&env, exports, name, std::move(args));
  }
  int32_t Diag(const char *field) {
    auto *diag = Call("moonohos_diagnostics", {});
    assert(diag); return static_cast<int32_t>(diag->properties.at(field)->number);
  }
};

static Value &Resolved(napi_value promise) { assert(promise && promise->promise_state == 2); return *promise->settled; }
static Value &Rejected(napi_value promise) { assert(promise && promise->promise_state == 3); return *promise->settled; }
static std::string Code(const Value &error) { return ErrorCode(error); }

static void HandleLifecycle() {
  Module m;
  Value five = Number(5), two = Number(2), one = Number(1);
  napi_value counter = m.Call("open_counter", {&five});
  assert(counter && counter->native);
  assert(m.Diag("liveHandles") == 1);
  assert(m.Call("add", {counter, &two})->number == 7);
  assert(!CallMethod(&m.env, *counter, "isClosed")->boolean);
  CallMethod(&m.env, *counter, "close");
  assert(CallMethod(&m.env, *counter, "isClosed")->boolean);
  assert(!m.Call("add", {counter, &one}) && m.env.exception == "Error");
  assert(m.env.message.find("ERR_MOONOHOS_CLOSED") == 0);
  CallMethod(&m.env, *counter, "close"); // idempotent
  assert(m.Diag("liveHandles") == 0);
  // A token is not a counter handle.
  napi_value token = m.Call("createCancelToken", {});
  assert(!m.Call("add", {token, &one}) && m.env.exception == "TypeError");
  // Finalization without close releases the MoonBit object.
  napi_value dropped = m.Call("open_counter", {&five});
  assert(dropped && m.Diag("liveHandles") == 1);
  m.env.Collect();
  assert(m.Diag("liveHandles") == 0);
}

static void AsyncResults() {
  Module m;
  Value five = Number(5), three = Number(3);
  napi_value counter = m.Call("open_counter", {&five});
  napi_value later = m.Call("add_later", {counter, &three});
  assert(later && later->promise_state == 1 && m.Diag("pendingTasks") == 1);
  m.env.RunWorks();
  assert(Resolved(later).number == 8 && m.Diag("pendingTasks") == 0);
  napi_value opened = m.Call("open_counter_later", {&three});
  m.env.RunWorks();
  Value &handle = Resolved(opened);
  assert(handle.native && m.Call("add", {&handle, &three})->number == 6);
  Value words = Array({Text(u"a"), Text(u"中")});
  napi_value echoed = m.Call("echo_words", {&words});
  m.env.RunWorks();
  assert(Resolved(echoed).elements[1]->text == u"中!");
  // Closing while a task holds a pin defers the release to task completion.
  napi_value pinned = m.Call("add_later", {counter, &three});
  CallMethod(&m.env, *counter, "close");
  assert(m.Diag("liveHandles") == 2);
  m.env.RunWorks();
  assert(Resolved(pinned).number == 11 && m.Diag("liveHandles") == 1);
  napi_value closed = m.Call("add_later", {counter, &three});
  assert(!closed && m.env.message.find("ERR_MOONOHOS_CLOSED") == 0);
}

static void BusinessErrors() {
  Module m;
  Value six = Number(6), zero = Number(0), three = Number(3), negative = Number(-4);
  assert(m.Call("checked_div", {&six, &three})->number == 2);
  assert(!m.Call("checked_div", {&six, &zero}) && m.env.exception == "Error");
  assert(m.env.message == "ERR_MOONOHOS_BUSINESS: division by zero");
  napi_value counter = m.Call("open_counter", {&negative});
  assert(!m.Call("reset", {counter}) && m.env.message == "ERR_MOONOHOS_BUSINESS: negative total -4");
  napi_value positive = m.Call("open_counter", {&six});
  assert(m.Call("reset", {positive}) && m.env.exception.empty());
  napi_value spin = m.Call("spin", {&six});
  m.env.RunWorks();
  assert(Resolved(spin).number == 15);
}

static void Cancellation() {
  Module m;
  Value huge = Number(2000000000);
  napi_value token = m.Call("createCancelToken", {});
  CallMethod(&m.env, *token, "cancel");
  assert(CallMethod(&m.env, *token, "isCancelled")->boolean);
  auto started = std::chrono::steady_clock::now();
  napi_value before = m.Call("spin", {&huge, token});
  m.env.RunWorks();
  Value &error = Rejected(before);
  assert(Code(error) == "ERR_MOONOHOS_CANCELLED" && Utf8(error.properties.at("name")->text) == "AbortError");
  // Cancel while MoonBit is running: @task.check() observes the token.
  napi_value running_token = m.Call("createCancelToken", {});
  auto *state = static_cast<Wrapped *>(running_token->native);
  napi_value running = m.Call("spin", {&huge, running_token});
  std::thread canceller([state] { std::this_thread::sleep_for(std::chrono::milliseconds(30)); state->cancel->cancelled.store(true); });
  m.env.RunWorks();
  canceller.join();
  assert(Code(Rejected(running)) == "ERR_MOONOHOS_CANCELLED");
  assert(std::chrono::steady_clock::now() - started < std::chrono::seconds(10));
  assert(m.Diag("cancelledTasks") == 2);
  Value wrong = Number(1);
  assert(!m.Call("spin", {&huge, &wrong}) && m.env.exception == "TypeError");
}

static void Adapters() {
  Module m;
  Value root = Text(U16(FixtureRoot())), one = Text(u"docs/one.txt"), missing = Text(u"docs/none.txt"), docs = Text(u"docs");
  auto before = moonohos_live_allocations();
  assert(m.Call("count_docs", {&root, &docs})->number == 2);
  napi_value text = m.Call("read_doc", {&root, &one});
  m.env.RunWorks();
  assert(Resolved(text).text == u"alpha\n");
  napi_value absent = m.Call("read_doc", {&root, &missing});
  m.env.RunWorks();
  assert(Code(Rejected(absent)) == "ERR_MOONOHOS_BUSINESS" && Utf8(Rejected(absent).text) == "rawfile not found: docs/none.txt");
  Value number = Number(3);
  assert(!m.Call("count_docs", {&number, &docs}) && m.env.exception == "TypeError");
  assert(moonohos_live_allocations() == before);
}

static void Teardown() {
  auto before = moonohos_live_allocations();
  {
    Module m;
    Value five = Number(5), huge = Number(2000000000);
    napi_value counter = m.Call("open_counter", {&five});
    napi_value queued = m.Call("add_later", {counter, &five});
    napi_value spinning = m.Call("spin", {&huge});
    assert(queued && spinning && m.Diag("pendingTasks") == 2);
    int32_t cleanups = m.Diag("envCleanups");
    m.env.Teardown(); // cancels tokens and closes handles before work completes
    m.env.RunWorks();
    assert(queued->promise_state == 1 && spinning->promise_state == 1); // no JS after teardown
    assert(pending_tasks.load() == 0 && env_cleanups.load() == cleanups + 1);
  }
  assert(live_handles.load() == 0);
  assert(moonohos_live_allocations() == before);
}

static void FailureSweep() {
  Value five = Number(5), three = Number(3);
  int operations;
  { Module m; napi_value counter = m.Call("open_counter", {&five}); int start = m.env.operations;
    assert(m.Call("add_later", {counter, &three})); operations = m.env.operations - start; m.env.RunWorks(); }
  for (int i = 0; i < operations; ++i) {
    for (bool pending : {false, true}) {
      auto before = moonohos_live_allocations();
      {
        Module m; napi_value counter = m.Call("open_counter", {&five});
        m.env.fail_at = m.env.operations + i; m.env.pending = pending;
        napi_value promise = m.Call("add_later", {counter, &three});
        m.env.fail_at = -1;
        m.env.RunWorks();
        if (promise && promise->promise_state != 0) assert(promise->promise_state != 1);
        assert(m.Diag("pendingTasks") == 0);
      }
      assert(moonohos_live_allocations() == before);
    }
  }
  // Failures while creating results in Complete reject instead of leaking.
  for (int i = 0; i < 6; ++i) {
    auto before = moonohos_live_allocations();
    {
      Module m;
      Value words = Array({Text(u"x"), Text(u"y")});
      napi_value promise = m.Call("echo_words", {&words});
      m.env.fail_at = m.env.operations + i;
      m.env.RunWorks();
      m.env.fail_at = -1;
      assert(promise->promise_state == 2 || promise->promise_state == 3);
    }
    assert(moonohos_live_allocations() == before);
  }
}

static void Concurrency() {
  Module m;
  Value zero = Number(0), one = Number(1), small = Number(4096);
  napi_value counter = m.Call("open_counter", {&zero});
  auto before = moonohos_live_allocations();
  for (int round = 0; round < 50; ++round) {
    std::vector<napi_value> promises;
    for (int i = 0; i < 16; ++i) {
      promises.push_back(m.Call("add_later", {counter, &one}));
      promises.push_back(m.Call("spin", {&small}));
      assert(m.Call("add", {counter, &zero}));
    }
    m.env.RunWorks(true); // all executes contend for the gate on real threads
    for (auto *promise : promises) assert(promise->promise_state == 2);
  }
  assert(m.Call("add", {counter, &zero})->number == 800);
  assert(moonohos_live_allocations() == before);
}

static void Repeat() {
  Module m;
  Value one = Number(1), words = Array({Text(u"a"), Text(u"b")});
  napi_value counter = m.Call("open_counter", {&one});
  for (int i = 0; i < 100; ++i) { m.Call("add", {counter, &one}); m.Call("echo_words", {&words}); m.env.RunWorks(); }
  auto before = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) {
    napi_value promise = m.Call("add_later", {counter, &one});
    napi_value echoed = m.Call("echo_words", {&words});
    m.env.RunWorks();
    assert(Resolved(promise).number == 102 + i && Resolved(echoed).elements.size() == 2);
  }
  assert(moonohos_live_allocations() == before);
}

int main() {
  HandleLifecycle();
  AsyncResults();
  BusinessErrors();
  Cancellation();
  Adapters();
  Teardown();
  FailureSweep();
  Concurrency();
  Repeat();
  std::cout << "HOST_ASYNC_PASS handles/async/business/cancel/adapters/teardown/failures/concurrency/repeat=10000 live_handles="
            << live_handles.load() << " pending=" << pending_tasks.load() << "\n";
}
