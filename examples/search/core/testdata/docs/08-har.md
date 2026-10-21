# Distributing a HAR

moonohos har places both ABI libraries, the generated declarations and an ArkTS
facade into a HAR module, then hvigor assembleHar builds the archive. Another
application only adds a file dependency on the HAR to use the search module.
