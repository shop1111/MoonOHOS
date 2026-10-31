# Security Policy

## Supported versions

Only the latest minor release receives fixes (currently 0.4.x).

## Reporting a vulnerability

Please do **not** open a public issue for memory-safety problems in generated
bridge code, path handling in the CLI, or anything that could let untrusted
input from ArkTS corrupt native memory.

Use GitHub's private reporting instead:
**Security → Report a vulnerability** on
<https://github.com/shop1111/MoonOHOS/security/advisories/new>.

Include the MoonOHOS version, `moonohos doctor --json` output, and a minimal
`moonohos.json` plus ArkTS call that triggers the problem. You should get a
reply within 7 days.

## Scope notes

- Generated bridges validate argument types, nesting depth (32), element count
  (1,048,576) and copied size (64 MiB) before touching MoonBit values. Bypasses
  of these limits are in scope.
- MoonBit `panic` terminating the process is documented behaviour, not a
  vulnerability.
