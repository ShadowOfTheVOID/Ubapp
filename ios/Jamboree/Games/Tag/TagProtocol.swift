import Foundation

enum TagVariant: String, CaseIterable {
    case classic, freeze, zombie, hotPotato, bomb
    var displayName: String {
        switch self {
        case .classic: "Classic"; case .freeze: "Freeze tag"
        case .zombie: "Zombie"; case .hotPotato: "Hot potato"; case .bomb: "Bomb"
        }
    }
    var tagline: String {
        switch self {
        case .classic: "Tagger transfers the role on contact."
        case .freeze: "Tagged players freeze. Teammates can unfreeze them."
        case .zombie: "Tagged players become it too. Last survivor wins."
        case .hotPotato: "It must tag before the timer runs out — or they lose."
        case .bomb: "Only it knows their role. Tag before the hidden timer ends."
        }
    }
    /// Default round length. Hot potato uses this as the per-tag countdown;
    /// bomb uses it as the hidden bomb timer.
    var duration: TimeInterval {
        switch self {
        case .classic, .freeze, .zombie: 5 * 60
        case .hotPotato: 30
        case .bomb: 3 * 60
        }
    }
    var hasEarlyEnd: Bool { self != .classic }
    var hidesIt: Bool { self == .bomb }
}

/// Line-oriented JSON messages dispatched on `type`. Mirrors lib/games/tag/tag_protocol.dart.
enum TagMessage {
    case hello(peerId: String, displayName: String)
    case start(variant: TagVariant, startingItId: String, startTimeMs: Int64,
               peerIds: [String], peerNames: [String: String],
               durationOverrideSec: Int?)
    case tag(taggerId: String, victimId: String, timeMs: Int64)
    case unfreeze(unfreezerId: String, victimId: String, timeMs: Int64)
    case end(reason: String, winnerId: String?)
    case tutorialCall
    case tutorialVote(voterId: String, yes: Bool)
    case tutorialState(isOpen: Bool, yesCount: Int, noCount: Int,
                       eligibleCount: Int, result: Bool?, tutorialShown: Bool)

    func encode() -> String {
        let obj = jsonObject()
        return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
    }

    /// The wire dict — used directly by the app-peer join path, which carries
    /// Tag messages over the same `GuestLink` JSON channel browser-tier games
    /// use rather than a second raw socket.
    func jsonObject() -> [String: Any] {
        switch self {
        case let .hello(peerId, displayName):
            return ["type": "hello", "peerId": peerId, "displayName": displayName]
        case let .start(variant, startingItId, startTimeMs, peerIds, peerNames, durationOverrideSec):
            var d: [String: Any] = ["type": "start", "variant": variant.rawValue,
                    "startingItId": startingItId, "startTimeMs": startTimeMs,
                    "peerIds": peerIds, "peerNames": peerNames]
            if let s = durationOverrideSec { d["durationOverrideSec"] = s }
            return d
        case let .tag(taggerId, victimId, timeMs):
            return ["type": "tag", "taggerId": taggerId, "victimId": victimId, "timeMs": timeMs]
        case let .unfreeze(unfreezerId, victimId, timeMs):
            return ["type": "unfreeze", "unfreezerId": unfreezerId, "victimId": victimId, "timeMs": timeMs]
        case let .end(reason, winnerId):
            return ["type": "end", "reason": reason, "winnerId": winnerId as Any]
        case .tutorialCall:
            return ["type": "tutorial_call"]
        case let .tutorialVote(voterId, yes):
            return ["type": "tutorial_vote", "voterId": voterId, "yes": yes]
        case let .tutorialState(isOpen, yesCount, noCount, eligibleCount, result, tutorialShown):
            return ["type": "tutorial_state", "isOpen": isOpen,
                    "yesCount": yesCount, "noCount": noCount, "eligibleCount": eligibleCount,
                    "result": result as Any, "tutorialShown": tutorialShown]
        }
    }

    static func decode(_ raw: String) throws -> TagMessage {
        guard let data = raw.data(using: .utf8),
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw NSError(domain: "TagMessage", code: 0) }
        return try decode(j)
    }

    /// Thrown when a decoded field is missing or the wrong type. Kept as a
    /// thrown error (never a force-unwrap) so a malformed frame from a peer is
    /// caught by the `try?` at every call site instead of trapping and
    /// crashing the host/peer — a malformed-input frame must not be a remote DoS.
    private struct DecodeError: Error {}

    static func decode(_ j: [String: Any]) throws -> TagMessage {
        // Typed field accessors that throw (rather than force-unwrap) on a
        // missing field or type mismatch. JSON numbers arrive as NSNumber.
        func str(_ k: String) throws -> String {
            guard let v = j[k] as? String else { throw DecodeError() }
            return v
        }
        func bool(_ k: String) throws -> Bool {
            guard let v = j[k] as? Bool else { throw DecodeError() }
            return v
        }
        func int(_ k: String) throws -> Int {
            guard let v = j[k] as? NSNumber else { throw DecodeError() }
            return v.intValue
        }
        func int64(_ k: String) throws -> Int64 {
            guard let v = j[k] as? NSNumber else { throw DecodeError() }
            return v.int64Value
        }
        func strArray(_ k: String) throws -> [String] {
            guard let v = j[k] as? [String] else { throw DecodeError() }
            return v
        }

        guard let type = j["type"] as? String else { throw DecodeError() }
        switch type {
        case "hello":
            return .hello(peerId: try str("peerId"), displayName: try str("displayName"))
        case "start":
            return .start(
                variant: TagVariant(rawValue: try str("variant")) ?? .classic,
                startingItId: try str("startingItId"),
                startTimeMs: try int64("startTimeMs"),
                peerIds: try strArray("peerIds"),
                peerNames: (j["peerNames"] as? [String: String]) ?? [:],
                durationOverrideSec: (j["durationOverrideSec"] as? NSNumber)?.intValue)
        case "tag":
            return .tag(taggerId: try str("taggerId"), victimId: try str("victimId"),
                        timeMs: try int64("timeMs"))
        case "unfreeze":
            return .unfreeze(unfreezerId: try str("unfreezerId"), victimId: try str("victimId"),
                             timeMs: try int64("timeMs"))
        case "end":
            return .end(reason: try str("reason"), winnerId: j["winnerId"] as? String)
        case "tutorial_call":
            return .tutorialCall
        case "tutorial_vote":
            return .tutorialVote(voterId: try str("voterId"), yes: try bool("yes"))
        case "tutorial_state":
            return .tutorialState(
                isOpen: try bool("isOpen"),
                yesCount: try int("yesCount"), noCount: try int("noCount"),
                eligibleCount: try int("eligibleCount"),
                result: j["result"] as? Bool,
                tutorialShown: try bool("tutorialShown"))
        default: throw DecodeError()
        }
    }
}
