import Foundation

/// The Linux tray's monolithic long-lived master invocation.
///
/// Mirrors the macOS app's `ssh -N -T -M -S` grammar and enforced option
/// set, except forwarding rules ride the same command line instead of being
/// installed through the control channel after connect. Combined with
/// `ExitOnForwardFailure=yes`, any bind failure becomes a process exit that
/// the shared retry schedule treats like a connect failure.
public enum SSHMasterInvocation {
    public static func arguments(
        tunnel: Tunnel,
        controlSocketPath: String
    ) -> [String] {
        var arguments = [
            "-N",
            "-T",
            "-M",
            "-S", controlSocketPath
        ]
        arguments.append(contentsOf: SSHMasterPolicy.enforcedArguments)
        arguments.append(contentsOf: [
            "-o", "StreamLocalBindMask=\(tunnel.streamLocalSettings.bindMaskArgument)",
            // Only sockets whose inode RelayBar recorded may be removed, so
            // stale-socket cleanup stays opt-in per profile, as on macOS.
            "-o", "StreamLocalBindUnlink=\(tunnel.streamLocalSettings.unlinkStaleSocket ? "yes" : "no")"
        ])

        if tunnel.hasReverseSOCKS, let policy = tunnel.reverseSOCKSPolicy {
            arguments.append(contentsOf: ["-o", "PermitRemoteOpen=\(policy.sshValue)"])
        }

        arguments.append(contentsOf: SSHCommandFormatter.forwardingArguments(for: tunnel))

        arguments.append(contentsOf: tunnel.additionalArguments)
        arguments.append(tunnel.sshHost)
        return arguments
    }
}
