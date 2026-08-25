import Foundation

/// Renders a profile as the forwarding-only `ssh` invocation RelayBar
/// effectively runs. The grammar matches what the Quick Add importer
/// accepts, so a copied command can be pasted back into Quick Add, shared in
/// docs, or run by hand — TCP listeners always name their bind address
/// explicitly (bare-port and `localhost` binds behave identically under the
/// default `GatewayPorts=no`, and the importer normalizes to `localhost`).
public enum SSHCommandFormatter {
    public static func command(for tunnel: Tunnel) -> String {
        var parts: [String] = ["ssh", "-N", "-T"]
        for rule in tunnel.rules {
            parts.append(rule.kind.sshOption)
            parts.append(shellQuoted(specification(for: rule)))
        }
        if tunnel.hasReverseSOCKS, let policy = tunnel.reverseSOCKSPolicy {
            parts.append("-o")
            parts.append(shellQuoted("PermitRemoteOpen=\(policy.sshValue)"))
        }
        parts.append("-o")
        parts.append(
            shellQuoted(
                "StreamLocalBindMask=\(tunnel.streamLocalSettings.bindMaskArgument)"
            )
        )
        if tunnel.streamLocalSettings.unlinkStaleSocket {
            parts.append("-o")
            parts.append("StreamLocalBindUnlink=yes")
        }
        parts.append(contentsOf: tunnel.additionalArguments.map(shellQuoted))
        parts.append(shellQuoted(tunnel.sshHost))
        return parts.joined(separator: " ")
    }

    /// Forwarding flags as raw argv tokens — no shell quoting. The Linux
    /// supervisor embeds these directly in ssh's argument vector and must
    /// produce the same normalized grammar as `command(for:)`.
    public static func forwardingArguments(for tunnel: Tunnel) -> [String] {
        var arguments: [String] = []
        for rule in tunnel.rules {
            arguments.append(rule.kind.sshOption)
            arguments.append(specification(for: rule))
        }
        return arguments
    }

    private static func specification(for rule: ForwardingRule) -> String {
        if rule.kind.isDynamic {
            return listenSpecification(for: rule)
        }
        let destination = rule.destination?.specification ?? ""
        return "\(listenSpecification(for: rule)):\(destination)"
    }

    private static func listenSpecification(for rule: ForwardingRule) -> String {
        switch rule.listen.kind {
        case .unix:
            return rule.listen.path ?? ""
        case .tcp:
            guard let endpoint = rule.listen.tcp else { return "" }
            let bindName = endpoint.bindAddress
                .flatMap { $0.isEmpty ? nil : $0 } ?? "localhost"
            return "\(SSHForwardingFormat.bracketIPv6(bindName)):\(endpoint.port)"
        }
    }

    /// Backslash-escapes every character outside the safe set. Unlike shell
    /// quote-wrapping this composes freely (spaces and quotes mixed in one
    /// token), and both POSIX shells and the importer's tokenizer read a
    /// backslash outside single quotes as one literal character.
    private static func shellQuoted(_ token: String) -> String {
        token.reduce(into: "") { result, character in
            if character.isLetter || character.isNumber
                || "-._/:=@[]%,".contains(character)
            {
                result.append(character)
            } else {
                result.append("\\")
                result.append(character)
            }
        }
    }
}
