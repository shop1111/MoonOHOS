///|
test "handle-returning functions give None on the host" {
  assert_true(@sensor.create_subscriber() is None)
  assert_true(@sensor.create_subscription_id() is None)
}
