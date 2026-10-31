///|
test "host fallback reports placeholders for every field" {
  assert_false(@deviceinfo.is_device())
  let info = @deviceinfo.snapshot()
  assert_eq(info.device_type, "host")
  assert_eq(info.os_full_name, "Host-0.0.0")
  assert_eq(info.sdk_api_version, 0)
  assert_eq(@deviceinfo.first_api_version(), 0)
  for
    field in [
      @deviceinfo.DeviceType,
      Manufacturer,
      Brand,
      MarketName,
      ProductSeries,
      ProductModel,
      SoftwareModel,
      HardwareModel,
      OsFullName,
      DisplayVersion,
      DistributionOsName,
      DistributionOsVersion,
      AbiList,
      BuildType,
    ] {
    assert_true(@deviceinfo.get(field) != "")
  }
}
