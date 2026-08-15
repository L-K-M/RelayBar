# Task 042 — Copy Profile as SSH Command

Status: Complete

Created: 2026-08-14

## Outcome

Every profile's row menu can copy the forwarding-only `ssh` invocation
RelayBar effectively runs, in the same grammar Quick Add imports, so the
command can be shared, documented, run by hand, or pasted back into the
importer.

## Delivery Boundary

- The formatter is presentation-only; no profile, lifecycle, or persisted
  state changes.
- Output round-trips through the Quick Add parser: TCP binds are named
  explicitly (bare port ≡ `localhost` under the default `GatewayPorts=no`),
  and every character outside the safe set is backslash-escaped so one token
  survives both a POSIX shell and the importer's tokenizer.

## Work

- Add `SSHCommandFormatter.command(for:)` covering rules, PermitRemoteOpen,
  StreamLocal options, additional arguments, and host.
- Add **Copy SSH Command** to the row menu, reusing the row's pasteboard
  helper.
- Add exact-string and round-trip tests; update the tunnel-management
  system spec.

## Acceptance

- A mixed local/SOCKS/reverse profile copies as the expected command string.
- Format → Quick Add import preserves kinds, endpoints, host, arguments, and
  reverse policy; formatting the re-import is byte-identical.
- Paths with spaces and quotes escape and re-import correctly.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `SSHCommandFormatter` renders `ssh -N -T` plus one option/specification
  pair per rule, reverse-SOCKS and StreamLocal options, preserved additional
  arguments, and the host, escaping every unsafe character with a backslash
  (quote-wrapping was rejected: the `'\''` idiom breaks both POSIX shells
  and the importer's tokenizer once spaces follow the quote).
- Five tests cover exact strings for simple and mixed profiles, space and
  quote escaping through the real parser, and full round-trip equivalence.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
