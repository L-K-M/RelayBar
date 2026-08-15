# Task 047 — Force Safe SSH Master Invariants

Status: Complete

Created: 2026-08-14

Completed: 2026-08-14

## Outcome

Every SSH multiplexing master RelayBar owns remains a foreground,
non-interactive transport and cannot gain forwarding or local-command authority
from host configuration beyond the behavior RelayBar presents.

## Delivery Boundary

Harden the forwarding-profile and Remote Files masters. Continue to trust and
honor the user's normal connection, authentication, host-key, identity, agent,
and proxy configuration. Child-process shutdown and PID ownership are separate
tasks.

## Work

- Apply one shared set of forced OpenSSH options to both master builders.
- Disable configured forking, local commands, tun devices, agent forwarding,
  X11 forwarding, and implicit gateway binding.
- Keep trusted identity, host-key, ProxyJump, and authentication behavior.
- Document the options RelayBar owns and the SSH-config trust boundary.

## Acceptance

- Deterministic argument tests prove every forced invariant occurs exactly once
  on both master command lines.
- Real `/usr/bin/ssh -G` tests prove hostile host values cannot override the
  forced invariants.
- The same configuration evaluation proves aliases, identities, host-key
  policy, users, ports, and jump hosts remain effective.
- System and security specifications describe the implemented policy.
- `swift test -Xswiftc -warnings-as-errors`, the unsigned Release Xcode build,
  and `git diff --check` pass.

## Evidence

- Local OpenSSH 9.2 `ssh -G` evaluation passed every forced-policy and
  preserved-connection assertion on 2026-08-14.
- GitHub Actions run `31847241096` passed the complete Swift package with
  warnings as errors and the unsigned Release Xcode build for commit
  `80c9f64` on 2026-08-14.
- GLM identified a latent two-pipe test-harness deadlock and an over-broad
  SSH-config trust claim. Commit `80c9f64` addressed both; the two review
  threads were answered and resolved after green CI. Its follow-up exhausted
  three 300-second API attempts without producing another review.
- `git diff --check` passed on 2026-08-14.
- No manual UI or live-SSH check was required: this task changes structured
  master arguments, covers their real OpenSSH evaluation, and does not change
  the transport, authentication, or forwarding operation paths.
