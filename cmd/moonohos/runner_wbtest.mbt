///|
async test "runner preserves argument boundaries and handles nonzero exit" {
  let text = command("test", "moonc", ["-v"], @env.current_dir().unwrap_or("."))
  assert_true(@lib.moonc_supported(text))
  let failed = try
    command("test", "moonc", ["--nonexistent-option"], ".")
  catch {
    Failure(message) => Some(message)
    _ => None
  } noraise {
    _ => None
  }
  assert_true(failed is Some(message) && message.contains("exit"))
}

///|
async test "runner cancels its child on timeout" {
  let start = @async.now()
  let failed = try {
    if host_os() == Windows {
      command(
        "timeout",
        "powershell.exe",
        ["-NoProfile", "-NonInteractive", "-Command", "Start-Sleep -Seconds 20"],
        ".",
        timeout_ms=1000,
      )
    } else {
      command("timeout", "sleep", ["20"], ".", timeout_ms=1000)
    }
  } catch {
    Failure(message) => Some(message)
    _ => None
  } noraise {
    _ => None
  }
  assert_true(failed is Some(message) && message.contains("timed out"))
  assert_true(@async.now() - start < 10000L)
}
