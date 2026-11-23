import Foundation

/// Which items may open the popup by themselves. Every kind is enabled and quiet mode is off by default.
/// Quiet mode is a manual switch: it stays on, across restarts, until the user turns it off.
public struct PopupSettings: Codable, Sendable, Hashable {
    public var disabledKinds: Set<String>
    public var quietMode: Bool

    public init(disabledKinds: Set<String> = [], quietMode: Bool = false) {
        self.disabledKinds = disabledKinds
        self.quietMode = quietMode
    }

    public static let `default` = PopupSettings()

    public func isEnabled(kind: String) -> Bool {
        !disabledKinds.contains(kind)
    }

    public mutating func setKind(_ kind: String, enabled: Bool) {
        if enabled {
            disabledKinds.remove(kind)
        } else {
            disabledKinds.insert(kind)
        }
    }

    enum CodingKeys: String, CodingKey {
        case disabledKinds = "disabled_kinds"
        case quietMode = "quiet_mode"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disabledKinds = try c.decodeIfPresent(Set<String>.self, forKey: .disabledKinds) ?? []
        quietMode = try c.decodeIfPresent(Bool.self, forKey: .quietMode) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(disabledKinds.sorted(), forKey: .disabledKinds)
        try c.encode(quietMode, forKey: .quietMode)
    }
}
