// Host ASan checks for ArkTS callbacks: sync calls invoke them on this thread
// during the call; async calls queue them through a threadsafe function and
// settle the Promise after the last one. Executes run on real worker threads.
#include "napi_init.cpp"
#include <cassert>
#include <iostream>
extern "C" size_t moonohos_live_allocations(void);
// Linked by the rawfile stub; this fixture has no adapters.
extern "C" const char *moonohos_host_adapter_text(void *) { return nullptr; }

static Value Number(double x) { return {napi_number, x, false}; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) {
  Value v; v.type = napi_object; v.kind = OrdinaryArray;
  for (auto &child : children) v.elements.push_back(Clone(child)); return v;
}
static void Throw(Env *env, const char *message) { env->exception = "Error"; env->message = message; }

struct Module {
  Env env;
  Value exports;
  Module() { env.stable_results = true; exports.type = napi_object; assert(Init(&env, &exports) == &exports); }
  napi_value Call(const char *name, std::vector<napi_value> args) {
    env.exception.clear(); env.message.clear();
    return CallMethod(&env, exports, name, std::move(args));
  }
  // Every reference, scope and threadsafe function is released after a call.
  void Settled() { assert(env.live_refs == 0 && env.open_scopes == 0 && env.LiveThreadsafeFunctions() == 0); }
};

static Value &Resolved(napi_value promise) { assert(promise && promise->promise_state == 2); return *promise->settled; }
static Value &Rejected(napi_value promise) { assert(promise && promise->promise_state == 3); return *promise->settled; }

static void SyncCallbacks() {
  Module m;
  // Warm up: runtime initialization allocates once per process.
  { Value one = Number(1); Value text = Text(u"w"); Value ignore = Function([](Env *, const std::vector<std::shared_ptr<Value>> &) {});
    m.Call("plain", {&one}); m.Call("each_word", {&text, &ignore}); m.Call("report", {&one, &ignore}); }
  auto before = moonohos_live_allocations();
  std::vector<std::pair<std::u16string, double>> seen;
  Value visit = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &args) {
    assert(args.size() == 2 && args[0]->type == napi_string && args[1]->type == napi_number);
    seen.emplace_back(args[0]->text, args[1]->number);
  });
  Value text = Text(u"moon bit  ohos");
  assert(m.Call("each_word", {&text, &visit})->number == 3);
  assert(seen.size() == 3 && seen[0].first == u"moon" && seen[1].first == u"bit" && seen[2] == std::make_pair(std::u16string(u"ohos"), 2.0));
  // Records, Option, Bytes, Int64 and enums arrive as ArkTS values.
  int steps = 0;
  Value on_step = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &args) {
    assert(args.size() == 5);
    assert(args[0]->properties.at("done")->number == steps + 1 && args[0]->properties.at("total")->number == 3);
    if (steps % 2 == 0) assert(args[1]->type == napi_number && args[1]->number == steps);
    else assert(args[1]->type == napi_undefined);
    assert(args[2]->kind == TypedArray && args[2]->length == 1 && args[2]->buffer->storage[0] == 'a' + steps);
    assert(args[3]->type == napi_bigint && args[3]->big == steps * 1000000000000LL);
    assert(args[4]->text == (steps == 2 ? u"High" : u"Low"));
    ++steps;
  });
  Value three = Number(3);
  assert(m.Call("report", {&three, &on_step}) && m.env.exception.empty() && steps == 3);
  // The callback may call the module again (the gate is re-entrant).
  std::vector<double> nested;
  Value reentrant = Function([&](Env *env, const std::vector<std::shared_ptr<Value>> &args) {
    Value index = *args[1];
    Call call{{&index}, nullptr, m.exports.properties.at("plain")->method_data};
    napi_value result = m.exports.properties.at("plain")->method(env, &call);
    assert(result); nested.push_back(result->number);
  });
  assert(m.Call("each_word", {&text, &reentrant})->number == 3);
  assert(nested == std::vector<double>({1, 2, 3}));
  m.Settled();
  assert(moonohos_live_allocations() == before);
}

static void SyncFailures() {
  Module m;
  // `remember` keeps one closure in a MoonBit global; later calls replace it.
  { Value ignore = Function([](Env *, const std::vector<std::shared_ptr<Value>> &) {}); m.Call("remember", {&ignore}); }
  auto before = moonohos_live_allocations();
  Value text = Text(u"a b c d");
  // A throwing callback stops later invocations; the call rethrows its error.
  int calls = 0;
  Value failing = Function([&](Env *env, const std::vector<std::shared_ptr<Value>> &) { if (++calls == 2) Throw(env, "boom"); });
  assert(!m.Call("each_word", {&text, &failing}));
  assert(m.env.exception == "Error" && m.env.message == "boom" && calls == 2);
  // Not a function.
  Value number = Number(1);
  assert(!m.Call("each_word", {&text, &number}) && m.env.exception == "TypeError");
  assert(m.env.message.find("each_word.visit: function required") == 0);
  // Arguments that cannot be converted fail the call before ArkTS runs.
  bool invoked = false;
  Value ratio = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &) { invoked = true; });
  Value one = Number(1), zero = Number(0), two = Number(2);
  assert(!m.Call("emit_ratio", {&one, &zero, &ratio}) && m.env.exception == "RangeError" && !invoked);
  assert(m.Call("emit_ratio", {&one, &two, &ratio}) && invoked);
  // A closure kept beyond its call is ignored afterwards.
  std::vector<double> remembered;
  Value keep = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &args) { remembered.push_back(args[0]->number); });
  assert(m.Call("remember", {&keep}) && remembered == std::vector<double>({1}));
  Value five = Number(5);
  assert(m.Call("replay", {&five})->number == 1 && remembered.size() == 1);
  m.Settled();
  // Node-API failure at every step of a sync call with callbacks.
  int steps;
  { int start = m.env.operations; Value ok = Function([](Env *, const std::vector<std::shared_ptr<Value>> &) {});
    assert(m.Call("report", {&two, &ok})); steps = m.env.operations - start; }
  for (int i = 0; i < steps; ++i) {
    for (bool pending : {false, true}) {
      Value ok = Function([](Env *, const std::vector<std::shared_ptr<Value>> &) {});
      m.env.fail_at = m.env.operations + i; m.env.pending = pending;
      assert(!m.Call("report", {&two, &ok}) && !m.env.exception.empty());
      m.env.fail_at = -1; m.env.pending = false;
      m.Settled();
    }
  }
  assert(moonohos_live_allocations() == before);
}

static void AsyncCallbacks(bool events_first) {
  Module m;
  m.env.events_first = events_first;
  auto before = moonohos_live_allocations();
  napi_value promise = nullptr;
  std::vector<double> progress;
  Value on_progress = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &args) {
    assert(promise->promise_state == 1); // every event precedes the settlement
    progress.push_back(args[0]->number);
  });
  Value hundred = Number(100);
  promise = m.Call("count_up", {&hundred, &on_progress});
  assert(promise && promise->promise_state == 1 && progress.empty());
  m.env.RunWorks();
  assert(Resolved(promise).number == 5050 && progress.size() == 10 && progress.front() == 10 && progress.back() == 100);
  // Two callbacks keep their relative order.
  std::vector<std::u16string> order;
  Value on_word = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &args) { order.push_back(args[0]->text); });
  Value on_done = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &args) {
    assert(args[0]->kind == OrdinaryArray && args[0]->elements.size() == 3 && args[0]->elements[2]->text == u"z!");
    order.push_back(u"done");
  });
  Value words = Array({Text(u"x"), Text(u"y"), Text(u"z")});
  napi_value scanned = m.Call("scan", {&words, &on_word, &on_done});
  m.env.RunWorks();
  assert(Resolved(scanned).number == 3);
  assert(order == std::vector<std::u16string>({u"x", u"y", u"z", u"done"}));
  // A throwing callback rejects with its error and skips the rest.
  int calls = 0;
  Value failing = Function([&](Env *env, const std::vector<std::shared_ptr<Value>> &) { if (++calls == 3) Throw(env, "stop"); });
  Value thousand = Number(1000);
  napi_value failed = m.Call("count_up", {&thousand, &failing});
  m.env.RunWorks();
  assert(Rejected(failed).error_kind == "Error" && Utf8(Rejected(failed).text) == "stop" && calls == 3);
  // Cancelled before running: no events, AbortError.
  int none = 0;
  Value silent = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &) { ++none; });
  napi_value token = m.Call("createCancelToken", {});
  napi_value cancelled = m.Call("count_up", {&hundred, &silent, token});
  CallMethod(&m.env, *token, "cancel");
  m.env.RunWorks();
  assert(ErrorCode(Rejected(cancelled)) == "ERR_MOONOHOS_CANCELLED" && none == 0);
  Value number = Number(1);
  assert(!m.Call("count_up", {&hundred, &number}) && m.env.exception == "TypeError");
  m.Settled();
  assert(moonohos_live_allocations() == before);
}

static void AsyncFailureSweep() {
  Value ten = Number(30);
  int steps;
  { Module m; Value ok = Function([](Env *, const std::vector<std::shared_ptr<Value>> &) {});
    int start = m.env.operations; m.Call("count_up", {&ten, &ok}); m.env.RunWorks(); steps = m.env.operations - start; }
  for (int i = 0; i < steps; ++i) {
    for (bool pending : {false, true}) {
      auto before = moonohos_live_allocations();
      {
        Module m;
        Value ok = Function([](Env *, const std::vector<std::shared_ptr<Value>> &) {});
        m.env.fail_at = m.env.operations + i; m.env.pending = pending;
        napi_value promise = m.Call("count_up", {&ten, &ok});
        m.env.RunWorks();
        m.env.fail_at = -1;
        if (promise && promise->promise_state != 0) assert(promise->promise_state != 1);
        assert(pending_tasks.load() == 0);
        m.Settled();
      }
      assert(moonohos_live_allocations() == before);
    }
  }
}

static void Teardown() {
  auto before = moonohos_live_allocations();
  {
    Module m;
    int calls = 0;
    Value counted = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &) { ++calls; });
    Value hundred = Number(100);
    napi_value queued = m.Call("count_up", {&hundred, &counted});
    m.env.Teardown(); // tokens cancelled; nothing reaches ArkTS afterwards
    m.env.RunWorks();
    assert(queued->promise_state == 1 && calls == 0 && pending_tasks.load() == 0);
  }
  {
    // Events already queued when the env goes away are dropped.
    Module m;
    int calls = 0;
    Value counted = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &) { ++calls; });
    Value hundred = Number(100);
    napi_value running = m.Call("count_up", {&hundred, &counted});
    for (auto *work : m.env.queue) work->execute(&m.env, work->data);
    auto works = m.env.queue; m.env.queue.clear();
    for (auto *work : works) work->complete(&m.env, napi_ok, work->data); // parks behind 10 events
    assert(running->promise_state == 1 && pending_tasks.load() == 1);
    m.env.Teardown();
    assert(running->promise_state == 1 && calls == 0 && pending_tasks.load() == 0);
  }
  assert(moonohos_live_allocations() == before);
}

static void Threaded() {
  Module m;
  auto before = moonohos_live_allocations();
  for (int round = 0; round < 50; ++round) {
    std::vector<napi_value> promises;
    std::vector<int> counts(16, 0);
    std::vector<Value> callbacks;
    callbacks.reserve(16);
    Value fifty = Number(50);
    for (int i = 0; i < 16; ++i) {
      callbacks.push_back(Function([&counts, i](Env *, const std::vector<std::shared_ptr<Value>> &) { ++counts[i]; }));
      promises.push_back(m.Call("count_up", {&fifty, &callbacks.back()}));
    }
    m.env.RunWorks(true); // executes contend for the gate on real threads
    for (int i = 0; i < 16; ++i) assert(Resolved(promises[i]).number == 1275 && counts[i] == 5);
  }
  m.Settled();
  assert(moonohos_live_allocations() == before);
}

static void Repeat() {
  Module m;
  Value text = Text(u"a b"), ten = Number(10);
  int calls = 0;
  Value counted = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &) { ++calls; });
  for (int i = 0; i < 100; ++i) { m.Call("each_word", {&text, &counted}); m.Call("count_up", {&ten, &counted}); m.env.RunWorks(); }
  auto before = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) {
    assert(m.Call("each_word", {&text, &counted})->number == 2);
    napi_value promise = m.Call("count_up", {&ten, &counted});
    m.env.RunWorks();
    assert(Resolved(promise).number == 55);
  }
  assert(calls == 10100 * 3);
  m.Settled();
  assert(moonohos_live_allocations() == before);
}

int main() {
  SyncCallbacks();
  SyncFailures();
  AsyncCallbacks(false);
  AsyncCallbacks(true);
  AsyncFailureSweep();
  Teardown();
  Threaded();
  Repeat();
  std::cout << "HOST_CALLBACK_PASS sync/reentrant/types/throw/range/escaped/status/async/order/cancel/teardown/threads/repeat=10000 pending="
            << pending_tasks.load() << "\n";
}
