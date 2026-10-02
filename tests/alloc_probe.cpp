#include <cstdlib>
#include <unordered_set>
#include <mutex>
static std::unordered_set<void *> allocations;
static std::mutex allocation_gate;
extern "C" void *moonohos_count_malloc(size_t size) {
  void *pointer = std::malloc(size);
  if (pointer) {
    std::lock_guard<std::mutex> lock(allocation_gate);
    allocations.insert(pointer);
  }
  return pointer;
}
extern "C" void moonohos_count_free(void *pointer) {
  {
    std::lock_guard<std::mutex> lock(allocation_gate);
    allocations.erase(pointer);
  }
  std::free(pointer);
}
extern "C" size_t moonohos_live_allocations(void) {
  std::lock_guard<std::mutex> lock(allocation_gate);
  return allocations.size();
}
