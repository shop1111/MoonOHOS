// P1a: generated bridge callbacks entered from many native threads at once.
// Each thread owns its Env (as each ArkTS worker/env would); MoonBit objects are
// created, called, copied and released only inside the generated process gate.
#include "napi_init.cpp"
#include <atomic>
#include <cassert>
#include <iostream>
#include <thread>
extern "C" size_t moonohos_live_allocations(void);
static Value Number(double x) { return {napi_number, x, false}; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) {
  Value v; v.type = napi_object; v.kind = OrdinaryArray;
  for (auto &child : children) v.elements.push_back(Clone(child)); return v;
}
int main() {
  constexpr int threads = 8;
#ifdef MOONOHOS_PROBE_ROUNDS
  constexpr int rounds = MOONOHOS_PROBE_ROUNDS;
#else
  constexpr int rounds = 20000;
#endif
  { Env warm; Value v = Array({Number(1)}); Call c{{&v, &v}}; assert(Call_join_ints(&warm, &c)); }
  const auto before = moonohos_live_allocations();
  std::atomic<int> failures{0};
  std::vector<std::thread> pool;
  for (int t = 0; t < threads; ++t) {
    pool.emplace_back([t, rounds, &failures] {
      Value ints = Array({Number(t), Number(-t), Number(INT32_MAX)});
      Value strings = Array({Text(u"中" + std::u16string(1, char16_t(u'a' + t))), Text(u"")});
      Value nested = Array({strings, strings});
      for (int i = 0; i < rounds; ++i) {
        Env env;
        Call join{{&ints, &ints}};
        auto joined = Call_join_ints(&env, &join);
        if (!joined || joined->elements.size() != 6 || joined->elements[3]->number != t) ++failures;
        Env env2;
        Call echo{{&nested}};
        auto copied = Call_echo_nested(&env2, &echo);
        if (!copied || copied->elements[1]->elements[0]->text != strings.elements[0]->text) ++failures;
      }
    });
  }
  for (auto &thread : pool) thread.join();
  const auto after = moonohos_live_allocations();
  std::cout << "THREAD_PROBE threads=" << threads << " rounds=" << rounds
            << " failures=" << failures.load() << " live_before=" << before
            << " live_after=" << after << "\n";
  assert(failures.load() == 0);
  assert(after == before);
  std::cout << "THREAD_PROBE_PASS\n";
}
