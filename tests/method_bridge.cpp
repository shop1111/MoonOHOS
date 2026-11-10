// Host ASan checks for handle methods: `counter.add(1)` forwards `this` as the
// first argument of the module function, sync, async and raising alike.
#include "napi_init.cpp"
#include <cassert>
#include <iostream>
extern "C" size_t moonohos_live_allocations(void);

extern "C" const char *moonohos_host_adapter_text(void *value) {
  thread_local std::string text;
  auto *v = static_cast<Value *>(value);
  if (v->type != napi_string) return nullptr;
  text = Utf8(v->text);
  return text.c_str();
}

static Value Number(double x) { return {napi_number, x, false}; }

struct Module {
  Env env;
  Value exports;
  Module() { exports.type = napi_object; assert(Init(&env, &exports) == &exports); }
  napi_value Call(const char *name, std::vector<napi_value> args) {
    env.exception.clear(); env.message.clear();
    return CallMethod(&env, exports, name, std::move(args));
  }
  napi_value On(napi_value object, const char *name, std::vector<napi_value> args = {}) {
    env.exception.clear(); env.message.clear();
    return CallMethod(&env, *object, name, std::move(args));
  }
  int32_t Diag(const char *field) {
    auto *diag = Call("moonohos_diagnostics", {});
    assert(diag); return static_cast<int32_t>(diag->properties.at(field)->number);
  }
};

static Value &Resolved(napi_value promise) { assert(promise && promise->promise_state == 2); return *promise->settled; }

int main() {
  {
    Module m;
    Value five = Number(5), two = Number(2), three = Number(3), negative = Number(-1);
    napi_value counter = m.Call("open_counter", {&five});
    assert(counter && counter->properties.count("add") && counter->properties.count("add_later") && counter->properties.count("reset"));
    assert(!counter->properties.count("spin")); // only declared methods are attached
    // Method and module function observe the same MoonBit object.
    assert(m.On(counter, "add", {&two})->number == 7);
    assert(m.Call("add", {counter, &two})->number == 9);
    // Async method returns a Promise and accepts the optional token.
    napi_value token = m.Call("createCancelToken", {});
    napi_value later = m.On(counter, "add_later", {&three, token});
    assert(later && later->promise_state == 1);
    m.env.RunWorks();
    assert(Resolved(later).number == 12);
    // Raising method: business error on a negative counter, success otherwise.
    assert(m.On(counter, "reset") && m.env.exception.empty());
    assert(m.On(counter, "add", {&two})->number == 2);
    napi_value bad = m.Call("open_counter", {&negative});
    assert(!m.On(bad, "reset") && m.env.message == "ERR_MOONOHOS_BUSINESS: negative total -1");
    // Missing argument and wrong argument type keep their usual errors.
    assert(!m.On(counter, "add") && m.env.exception == "TypeError");
    Value text; text.type = napi_string; text.text = u"x";
    assert(!m.On(counter, "add", {&text}) && m.env.exception == "TypeError");
    // After close, methods fail like module calls with a closed handle.
    m.On(counter, "close");
    assert(!m.On(counter, "add", {&two}) && m.env.message.find("ERR_MOONOHOS_CLOSED") == 0);
    // Async-created handles carry methods too.
    napi_value opened = m.Call("open_counter_later", {&three});
    m.env.RunWorks();
    Value &handle = Resolved(opened);
    assert(m.On(&handle, "add", {&three})->number == 6);
    m.On(&handle, "close"); m.On(bad, "close");
    assert(m.Diag("liveHandles") == 0);
  }
  // An object wrapped by another native module (here: same methods, foreign
  // pointer, no MoonOHOS type tag) is rejected before its pointer is read.
  {
    Module m; Value one = Number(1);
    napi_value counter = m.Call("open_counter", {&one});
    assert(counter->tagged);
    napi_value token = m.Call("createCancelToken", {});
    assert(token->tagged);
    static int foreign_native = 0;
    Value foreign; foreign.type = napi_object; foreign.properties = counter->properties;
    assert(napi_wrap(&m.env, &foreign, &foreign_native, nullptr, nullptr, nullptr) == napi_ok);
    assert(!m.Call("add", {&foreign, &one}) && m.env.exception == "TypeError");
    assert(m.env.message.find("MoonOHOS object of this module required") != std::string::npos);
    assert(!m.On(&foreign, "add", {&one}) && m.env.exception == "TypeError");
    assert(!m.On(&foreign, "close") && m.env.exception == "TypeError");
    assert(!m.Call("add_later", {counter, &one, &foreign}) && m.env.exception == "TypeError");
    m.On(counter, "close");
    assert(m.Diag("liveHandles") == 0);
  }
  // Node-API failure injection on a method call leaves no leaks.
  {
    Env probe; Value exports; exports.type = napi_object; assert(Init(&probe, &exports));
    Value five = Number(5), one = Number(1);
    napi_value counter = CallMethod(&probe, exports, "open_counter", {&five});
    int before = probe.operations; assert(CallMethod(&probe, *counter, "add", {&one})); int steps = probe.operations - before;
    for (int i = 0; i < steps; ++i) {
      probe.exception.clear(); probe.fail_at = probe.operations + i;
      auto live = moonohos_live_allocations();
      auto ok = CallMethod(&probe, *counter, "add", {&one});
      // A failed napi_unwrap is reported as "not a MoonOHOS object" (TypeError).
      bool unwrap = probe.exception == "TypeError" && probe.message.find("object required") != std::string::npos;
      assert(!ok && (probe.exception == "Error" || unwrap));
      assert(moonohos_live_allocations() == live);
    }
    probe.fail_at = -1; CallMethod(&probe, *counter, "close");
  }
  {
    Module m; Value one = Number(1);
    auto baseline = moonohos_live_allocations();
    for (int i = 0; i < 10000; ++i) {
      napi_value counter = m.Call("open_counter", {&one});
      assert(m.On(counter, "add", {&one})->number == 2);
      m.On(counter, "close");
    }
    assert(m.Diag("liveHandles") == 0 && moonohos_live_allocations() == baseline);
  }
  std::cout << "HOST_METHOD_PASS sync/async/raises/closed/errors/status/repeat=10000 live_handles=0\n";
}
