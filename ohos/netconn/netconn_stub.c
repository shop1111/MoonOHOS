// Default network state (network/netmanager/net_connection.h). Needs the
// ohos.permission.GET_NETWORK_INFO permission in the consuming app.
#include <stdint.h>
#ifdef MOONOHOS_TARGET_OHOS
#include <network/netmanager/net_connection.h>
#else
static int32_t moonohos_netconn_host[3] = {1, 0, 0}; // has default net, metered, forced error
#endif

// Returns 0 and writes 0/1 to `out`, or the NDK error code.
int32_t moonohos_netconn_query(int32_t which, int32_t *out) {
#ifdef MOONOHOS_TARGET_OHOS
  switch (which) {
    case 0: return OH_NetConn_HasDefaultNet(out);
    case 1: return OH_NetConn_IsDefaultNetMetered(out);
    default: return -1;
  }
#else
  if (moonohos_netconn_host[2] != 0) return moonohos_netconn_host[2];
  if (which < 0 || which > 1) return -1;
  *out = moonohos_netconn_host[which];
  return 0;
#endif
}

// Host-only test hook; a no-op on HarmonyOS.
void moonohos_netconn_host_set(int32_t has_default, int32_t metered, int32_t error) {
#ifdef MOONOHOS_TARGET_OHOS
  (void)has_default; (void)metered; (void)error;
#else
  moonohos_netconn_host[0] = has_default;
  moonohos_netconn_host[1] = metered;
  moonohos_netconn_host[2] = error;
#endif
}
