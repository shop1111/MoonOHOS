///|
test "string results are empty on the host" {
  assert_eq(@deviceinfo.get_os_full_name(), "")
  assert_eq(@deviceinfo.get_sdk_api_version(), 0)
}
