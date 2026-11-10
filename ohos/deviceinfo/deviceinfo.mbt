///|
/// Text properties of the device and OS, from `deviceinfo.h`.
pub(all) enum Field {
  DeviceType
  Manufacturer
  Brand
  MarketName
  ProductSeries
  ProductModel
  SoftwareModel
  HardwareModel
  OsFullName
  DisplayVersion
  DistributionOsName
  DistributionOsVersion
  AbiList
  BuildType
}

///|
fn Field::code(self : Field) -> Int32 {
  match self {
    DeviceType => 0
    Manufacturer => 1
    Brand => 2
    MarketName => 3
    ProductSeries => 4
    ProductModel => 5
    SoftwareModel => 6
    HardwareModel => 7
    OsFullName => 8
    DisplayVersion => 9
    DistributionOsName => 10
    DistributionOsVersion => 11
    AbiList => 12
    BuildType => 13
  }
}

///|
#borrow(out)
extern "C" fn copy_raw(
  field : Int32,
  out : FixedArray[Byte],
  capacity : Int32,
) -> Int32 = "moonohos_deviceinfo_copy"

///|
extern "C" fn api_raw(which : Int32) -> Int32 = "moonohos_deviceinfo_api"

///|
extern "C" fn is_device_raw() -> Int32 = "moonohos_deviceinfo_is_device"

///|
/// Reads one property. Returns `""` when the system does not report it.
pub fn get(field : Field) -> String {
  let code = field.code()
  let needed = copy_raw(code, FixedArray::make(0, b'\x00'), 0)
  if needed <= 0 {
    return ""
  }
  let buffer = FixedArray::make(needed, b'\x00')
  if copy_raw(code, buffer, needed) != needed {
    return ""
  }
  @utf8.decode_lossy(Bytes::from_array(buffer[:]))
}

///|
/// API level of the running system (`OH_GetSdkApiVersion`); 0 on the host.
pub fn sdk_api_version() -> Int32 {
  api_raw(0)
}

///|
/// API level the device first shipped with (`OH_GetFirstApiVersion`).
pub fn first_api_version() -> Int32 {
  api_raw(1)
}

///|
/// True inside a HarmonyOS process, false for host builds and tests, where
/// every property returns a fixed placeholder.
pub fn is_device() -> Bool {
  is_device_raw() != 0
}

///|
/// The commonly needed properties in one value.
#derive(Debug)
pub(all) struct DeviceInfo {
  device_type : String
  manufacturer : String
  brand : String
  market_name : String
  product_model : String
  os_full_name : String
  display_version : String
  sdk_api_version : Int32
}

///|
pub fn snapshot() -> DeviceInfo {
  {
    device_type: get(DeviceType),
    manufacturer: get(Manufacturer),
    brand: get(Brand),
    market_name: get(MarketName),
    product_model: get(ProductModel),
    os_full_name: get(OsFullName),
    display_version: get(DisplayVersion),
    sdk_api_version: sdk_api_version(),
  }
}

///|
#deprecated
pub extend DeviceInfo with @debug.Debug::{to_repr}
