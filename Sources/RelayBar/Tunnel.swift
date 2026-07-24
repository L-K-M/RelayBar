import Foundation

enum ForwardingRuleKind: String, Codable, CaseIterable, Sendable {
    case local
    case localDynamic
    case remote
    case remoteDynamic

    var label: String {
        switch self {
        case .local: "Local"
        case .localDynamic: "Local SOCKS"
        case .remote: "Remote"
        case .remoteDynamic: "Remote SOCKS"
        }
    }

    var sshOption: String {
        switch self {
        case .local: "-L"
        case .localDynamic: "-D"
        case .remote, .remoteDynamic: "-R"
        }
    }

    var listensRemotely: Bool {
        self == .remote || self == .remoteDynamic
    }

    var isDynamic: Bool {
        self == .localDynamic || self == .remoteDynamic
    }
}

struct TCPListenEndpoint: Codable, Equatable, Hashable, Sendable {
    var bindAddress: String?
    var port: Int

    init(bindAddress: String? = nil, port: Int) {
        self.bindAddress = bindAddress
        self.port = port
    }

    var specification: String {
        guard let bindAddress else { return String(port) }
        return "\(SSHForwardingFormat.bracketIPv6(bindAddress)):\(port)"
    }

    var displayText: String {
        let host = bindAddress.flatMap { $0.isEmpty ? nil : $0 } ?? "localhost"
        return "\(host):\(port)"
    }

    var exposesBeyondLoopback: Bool {
        guard let bindAddress else { return false }
        let normalized = SSHForwardingFormat.unbracket(bindAddress).lowercased()
        return !["localhost", "127.0.0.1", "::1"].contains(normalized)
    }
}

struct ForwardListenEndpoint: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case tcp
        case unix
    }

    var kind: Kind
    var tcp: TCPListenEndpoint?
    var path: String?

    static func tcp(bindAddress: String? = nil, port: Int) -> ForwardListenEndpoint {
        ForwardListenEndpoint(
            kind: .tcp,
            tcp: TCPListenEndpoint(bindAddress: bindAddress, port: port),
            path: nil
        )
    }

    static func unix(path: String) -> ForwardListenEndpoint {
        ForwardListenEndpoint(kind: .unix, tcp: nil, path: path)
    }

    var specification: String {
        switch kind {
        case .tcp: tcp?.specification ?? ""
        case .unix: path ?? ""
        }
    }

    var displayText: String {
        switch kind {
        case .tcp: tcp?.displayText ?? "Invalid TCP listener"
        case .unix: path ?? "Invalid Unix socket"
        }
    }

    var isStructurallyValid: Bool {
        switch kind {
        case .tcp:
            tcp != nil && path == nil
        case .unix:
            tcp == nil && path != nil
        }
    }
}

struct TCPDestinationEndpoint: Codable, Equatable, Hashable, Sendable {
    var host: String
    var port: Int

    var specification: String {
        "\(SSHForwardingFormat.bracketIPv6(host)):\(port)"
    }

    var displayText: String {
        "\(host):\(port)"
    }
}

struct ForwardDestinationEndpoint: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case tcp
        case unix
    }

    var kind: Kind
    var tcp: TCPDestinationEndpoint?
    var path: String?

    static func tcp(host: String, port: Int) -> ForwardDestinationEndpoint {
        ForwardDestinationEndpoint(
            kind: .tcp,
            tcp: TCPDestinationEndpoint(host: host, port: port),
            path: nil
        )
    }

    static func unix(path: String) -> ForwardDestinationEndpoint {
        ForwardDestinationEndpoint(kind: .unix, tcp: nil, path: path)
    }

    var specification: String {
        switch kind {
        case .tcp: tcp?.specification ?? ""
        case .unix: path ?? ""
        }
    }

    var displayText: String {
        switch kind {
        case .tcp: tcp?.displayText ?? "Invalid TCP destination"
        case .unix: path ?? "Invalid Unix socket"
        }
    }

    var isStructurallyValid: Bool {
        switch kind {
        case .tcp:
            tcp != nil && path == nil
        case .unix:
            tcp == nil && path != nil
        }
    }
}

struct ForwardingRule: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var kind: ForwardingRuleKind
    var listen: ForwardListenEndpoint
    var destination: ForwardDestinationEndpoint?

    init(
        id: UUID = UUID(),
        kind: ForwardingRuleKind,
        listen: ForwardListenEndpoint,
        destination: ForwardDestinationEndpoint? = nil
    ) {
        self.id = id
        self.kind = kind
        self.listen = listen
        self.destination = destination
    }

    static func localTCP(
        id: UUID = UUID(),
        bindAddress: String? = nil,
        port: Int,
        destinationHost: String,
        destinationPort: Int
    ) -> ForwardingRule {
        ForwardingRule(
            id: id,
            kind: .local,
            listen: .tcp(bindAddress: bindAddress, port: port),
            destination: .tcp(host: destinationHost, port: destinationPort)
        )
    }

    var specification: String {
        if kind.isDynamic {
            return listen.specification
        }
        return "\(listen.specification):\(destination?.specification ?? "")"
    }

    var sshArguments: [String] {
        [kind.sshOption, specification]
    }

    var createdLocalSocketPath: String? {
        guard kind == .local, listen.kind == .unix else { return nil }
        return listen.path
    }

    var displaySummary: String {
        switch kind {
        case .local:
            "\(listen.displayText) → \(destination?.displayText ?? "Invalid destination")"
        case .localDynamic:
            "\(listen.displayText) → SOCKS via server"
        case .remote:
            "\(listen.displayText) ⇠ \(destination?.displayText ?? "Invalid destination")"
        case .remoteDynamic:
            "\(listen.displayText) ⇠ SOCKS via Mac"
        }
    }

    func displaySummary(runtimePort: Int?) -> String {
        guard
            kind.listensRemotely,
            case .tcp = listen.kind,
            listen.tcp?.port == 0,
            let runtimePort
        else {
            return displaySummary
        }

        var resolved = self
        resolved.listen.tcp?.port = runtimePort
        return resolved.displaySummary
    }

    func copyableListenEndpoint(runtimePort: Int?) -> String? {
        switch listen.kind {
        case .unix:
            return listen.path
        case .tcp:
            guard var endpoint = listen.tcp else { return nil }
            if endpoint.port == 0 {
                guard let runtimePort else { return nil }
                endpoint.port = runtimePort
            }
            return endpoint.displayText
        }
    }

    var localBrowserURL: URL? {
        guard
            kind == .local,
            listen.kind == .tcp,
            let endpoint = listen.tcp
        else {
            return nil
        }

        var host = endpoint.bindAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        host = SSHForwardingFormat.unbracket(host)
        if host.isEmpty || ["*", "0.0.0.0", "::"].contains(host.lowercased()) {
            host = "localhost"
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host.contains(":") ? "[\(host)]" : host
        components.port = endpoint.port
        components.path = "/"
        return components.url
    }

    var isValid: Bool {
        guard listen.isStructurallyValid else { return false }

        switch listen.kind {
        case .tcp:
            guard let tcp = listen.tcp else { return false }
            let validPortRange = kind.listensRemotely ? 0...65_535 : 1...65_535
            guard
                validPortRange.contains(tcp.port),
                SSHArgumentPolicy.isValidBindAddress(tcp.bindAddress)
            else {
                return false
            }
        case .unix:
            guard
                !kind.isDynamic,
                let path = listen.path,
                SSHArgumentPolicy.isValidSocketPath(path)
            else {
                return false
            }
        }

        if kind.isDynamic {
            return destination == nil
        }

        guard let destination, destination.isStructurallyValid else { return false }
        switch destination.kind {
        case .tcp:
            guard let tcp = destination.tcp else { return false }
            return SSHArgumentPolicy.isValidDestinationHost(tcp.host)
                && (1...65_535).contains(tcp.port)
        case .unix:
            guard let path = destination.path else { return false }
            return SSHArgumentPolicy.isValidSocketPath(path)
        }
    }
}

enum ReverseSOCKSPolicy: Equatable, Sendable {
    case any
    case none
    case allow([String])

    var sshValue: String {
        switch self {
        case .any: "any"
        case .none: "none"
        case .allow(let destinations): destinations.joined(separator: " ")
        }
    }

    var displayText: String {
        switch self {
        case .any: "Any destination"
        case .none: "No destinations"
        case .allow(let destinations): destinations.joined(separator: ", ")
        }
    }

    var isValid: Bool {
        switch self {
        case .any, .none:
            true
        case .allow(let destinations):
            !destinations.isEmpty
                && destinations.allSatisfy(SSHArgumentPolicy.isValidPermitRemoteOpenDestination)
        }
    }
}

extension ReverseSOCKSPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case destinations
    }

    private enum Kind: String, Codable {
        case any
        case none
        case allow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .any:
            self = .any
        case .none:
            self = .none
        case .allow:
            self = .allow(try container.decode([String].self, forKey: .destinations))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            try container.encode(Kind.any, forKey: .kind)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .allow(let destinations):
            try container.encode(Kind.allow, forKey: .kind)
            try container.encode(destinations, forKey: .destinations)
        }
    }
}

struct StreamLocalSettings: Codable, Equatable, Sendable {
    var bindMask: UInt16
    var unlinkStaleSocket: Bool

    init(bindMask: UInt16 = 0o177, unlinkStaleSocket: Bool = false) {
        self.bindMask = bindMask
        self.unlinkStaleSocket = unlinkStaleSocket
    }

    var bindMaskArgument: String {
        String(format: "%04o", bindMask)
    }

    var isValid: Bool {
        bindMask <= 0o777
    }
}

struct Tunnel: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var sshHost: String
    var additionalArguments: [String]
    var rules: [ForwardingRule]
    var reverseSOCKSPolicy: ReverseSOCKSPolicy?
    var streamLocalSettings: StreamLocalSettings

    init(
        id: UUID = UUID(),
        name: String,
        sshHost: String,
        additionalArguments: [String] = [],
        rules: [ForwardingRule],
        reverseSOCKSPolicy: ReverseSOCKSPolicy? = nil,
        streamLocalSettings: StreamLocalSettings = StreamLocalSettings()
    ) {
        self.id = id
        self.name = name
        self.sshHost = sshHost
        self.additionalArguments = additionalArguments
        self.rules = rules
        self.reverseSOCKSPolicy = reverseSOCKSPolicy
        self.streamLocalSettings = streamLocalSettings
    }

    init(
        id: UUID = UUID(),
        name: String,
        localPort: Int,
        destinationHost: String,
        destinationPort: Int,
        sshHost: String,
        bindAddress: String? = nil,
        additionalArguments: [String] = []
    ) {
        self.init(
            id: id,
            name: name,
            sshHost: sshHost,
            additionalArguments: additionalArguments,
            rules: [
                .localTCP(
                    bindAddress: bindAddress,
                    port: localPort,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            ]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sshHost
        case additionalArguments
        case rules
        case reverseSOCKSPolicy
        case streamLocalSettings
        case localPort
        case destinationHost
        case destinationPort
        case bindAddress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sshHost = try container.decode(String.self, forKey: .sshHost)
        additionalArguments = try container.decodeIfPresent(
            [String].self,
            forKey: .additionalArguments
        ) ?? []

        if let decodedRules = try container.decodeIfPresent(
            [ForwardingRule].self,
            forKey: .rules
        ) {
            rules = decodedRules
            reverseSOCKSPolicy = try container.decodeIfPresent(
                ReverseSOCKSPolicy.self,
                forKey: .reverseSOCKSPolicy
            )
            streamLocalSettings = try container.decodeIfPresent(
                StreamLocalSettings.self,
                forKey: .streamLocalSettings
            ) ?? StreamLocalSettings()
        } else {
            let localPort = try container.decode(Int.self, forKey: .localPort)
            let destinationHost = try container.decode(String.self, forKey: .destinationHost)
            let destinationPort = try container.decode(Int.self, forKey: .destinationPort)
            let bindAddress = try container.decodeIfPresent(String.self, forKey: .bindAddress)
            rules = [
                .localTCP(
                    bindAddress: bindAddress,
                    port: localPort,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            ]
            reverseSOCKSPolicy = nil
            streamLocalSettings = StreamLocalSettings()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sshHost, forKey: .sshHost)
        try container.encode(additionalArguments, forKey: .additionalArguments)
        try container.encode(rules, forKey: .rules)
        try container.encodeIfPresent(reverseSOCKSPolicy, forKey: .reverseSOCKSPolicy)
        try container.encode(streamLocalSettings, forKey: .streamLocalSettings)
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? (rules.first?.displaySummary ?? sshHost) : trimmedName
    }

    var displaySummary: String {
        if rules.count == 1 {
            return singleRuleSummary(rules[0], runtimePort: nil)
        }
        return "\(rules.count) forwarding rules via \(sshHost)"
    }

    func displaySummary(runtimePorts: [UUID: Int]) -> String {
        if rules.count == 1, let rule = rules.first {
            return singleRuleSummary(rule, runtimePort: runtimePorts[rule.id])
        }
        return "\(rules.count) forwarding rules via \(sshHost)"
    }

    private func singleRuleSummary(
        _ rule: ForwardingRule,
        runtimePort: Int?
    ) -> String {
        let summary = rule.displaySummary(runtimePort: runtimePort)
        guard rule.kind == .remoteDynamic, let reverseSOCKSPolicy else {
            return summary
        }
        return "\(summary) · \(reverseSOCKSPolicy.displayText)"
    }

    var unambiguousBrowserURL: URL? {
        guard rules.count == 1 else { return nil }
        return rules[0].localBrowserURL
    }

    var browserURL: URL? {
        unambiguousBrowserURL
    }

    var exposesBeyondLoopback: Bool {
        rules.contains { rule in
            rule.listen.tcp?.exposesBeyondLoopback == true
        }
    }

    var usesUnixSockets: Bool {
        rules.contains { rule in
            rule.listen.kind == .unix || rule.destination?.kind == .unix
        }
    }

    var hasReverseSOCKS: Bool {
        rules.contains { $0.kind == .remoteDynamic }
    }

    var createdLocalSocketPaths: [String] {
        rules.compactMap(\.createdLocalSocketPath)
    }

    var forwardArguments: [String] {
        rules.flatMap(\.sshArguments)
    }

    var isSafeToRun: Bool {
        guard
            !rules.isEmpty,
            Set(rules.map(\.id)).count == rules.count,
            rules.allSatisfy(\.isValid),
            streamLocalSettings.isValid,
            SSHArgumentPolicy.isValidHostTarget(sshHost),
            SSHArgumentPolicy.areAdditionalArgumentsSafe(additionalArguments),
            !hasConflictingListeners
        else {
            return false
        }

        if hasReverseSOCKS {
            guard let reverseSOCKSPolicy, reverseSOCKSPolicy.isValid else { return false }
        }
        return true
    }

    var hasConflictingListeners: Bool {
        for firstIndex in rules.indices {
            for secondIndex in rules.indices where secondIndex > firstIndex {
                let first = rules[firstIndex]
                let second = rules[secondIndex]
                guard first.kind.listensRemotely == second.kind.listensRemotely else {
                    continue
                }
                if SSHForwardingFormat.listenersOverlap(first.listen, second.listen) {
                    return true
                }
            }
        }
        return false
    }

    // Compatibility accessors keep Remote Files and legacy callers source-compatible.
    var localPort: Int {
        rules.first?.listen.tcp?.port ?? 0
    }

    var destinationHost: String {
        rules.first?.destination?.tcp?.host ?? ""
    }

    var destinationPort: Int {
        rules.first?.destination?.tcp?.port ?? 0
    }

    var bindAddress: String? {
        rules.first?.listen.tcp?.bindAddress
    }

    var forwardSpec: String {
        rules.first?.specification ?? ""
    }

    var localEndpoint: String {
        rules.first?.listen.displayText ?? ""
    }

    var destinationEndpoint: String {
        rules.first?.destination?.displayText ?? rules.first?.kind.label ?? ""
    }
}

enum SSHForwardingFormat {
    static func unbracket(_ value: String) -> String {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return value }
        return String(value.dropFirst().dropLast())
    }

    static func bracketIPv6(_ value: String) -> String {
        let unbracketed = unbracket(value)
        return unbracketed.contains(":") ? "[\(unbracketed)]" : unbracketed
    }

    static func listenersOverlap(
        _ first: ForwardListenEndpoint,
        _ second: ForwardListenEndpoint
    ) -> Bool {
        guard first.kind == second.kind else { return false }
        switch first.kind {
        case .unix:
            return first.path == second.path
        case .tcp:
            guard
                let firstTCP = first.tcp,
                let secondTCP = second.tcp,
                firstTCP.port == secondTCP.port
            else {
                return false
            }
            if firstTCP.port == 0 { return false }
            return bindAddressesOverlap(firstTCP.bindAddress, secondTCP.bindAddress)
        }
    }

    private static func bindAddressesOverlap(_ first: String?, _ second: String?) -> Bool {
        let first = normalizedBind(first)
        let second = normalizedBind(second)
        if first == "any" || second == "any" { return true }
        if first == "loopback" && second == "loopback" { return true }
        return first == second
    }

    private static func normalizedBind(_ bindAddress: String?) -> String {
        guard let bindAddress else { return "any" }
        let value = unbracket(bindAddress)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["", "*", "0.0.0.0", "::"].contains(value) {
            return "any"
        }
        if ["localhost", "127.0.0.1", "::1"].contains(value) {
            return "loopback"
        }
        return value
    }
}

enum TunnelPhase: Equatable {
    case stopped
    case starting
    case retrying(attempt: Int, maxAttempts: Int, delay: TimeInterval, message: String)
    case running
    case failed(String)
}
