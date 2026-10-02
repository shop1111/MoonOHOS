cmake_minimum_required(VERSION 3.16)
project(moonohos_manual LANGUAGES C CXX)
add_library(moonohos SHARED embed.c napi_init.cpp
  "${MOON_HOME}/lib/runtime/runtime.c" "${MOON_HOME}/lib/runtime/env.c"
  "${MOON_HOME}/lib/runtime/backtrace.c" "${MOON_HOME}/lib/runtime/sync_io.c"
  "${MOON_HOME}/lib/runtime/utf.c")
target_include_directories(moonohos PRIVATE "${MOON_HOME}/include" "${CMAKE_CURRENT_SOURCE_DIR}/_build/native/release/build")
target_compile_features(moonohos PRIVATE c_std_11 cxx_std_17)
target_compile_definitions(moonohos PRIVATE _GNU_SOURCE MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM MOONBIT_NATIVE_EXIT_ON_PANIC)
target_compile_options(moonohos PRIVATE -fwrapv -fno-strict-aliasing -fvisibility=hidden)
target_link_options(moonohos PRIVATE -Wl,--no-undefined)
target_link_libraries(moonohos PRIVATE libace_napi.z.so m)
