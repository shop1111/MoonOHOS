///|
test "host cancellation flag" {
  @task.host_set_cancelled(false)
  assert_true(!@task.cancelled())
  @task.check()
  @task.host_set_cancelled(true)
  let message = try {
    @task.check()
    "running"
  } catch {
    e => e.to_string()
  }
  @task.host_set_cancelled(false)
  assert_eq(message, "task cancelled")
}
