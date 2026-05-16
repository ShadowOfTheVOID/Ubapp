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
        let obj = toJSON()
        return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
    }

    private func toJSON() -> [String: Any] {
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
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String
        else { throw NSError(domain: "TagMessage", code: 0) }
        switch type {
        case "hello":
            return .hello(peerId: j["peerId"] as! String, displayName: j["displayName"] as! String)
        case "start":
            return .start(
                variant: TagVariant(rawValue: j["variant"] as! String) ?? .classic,
                startingItId: j["startingItId"] as! String,
                startTimeMs: (j["startTimeMs"] as! NSNumber).int64Value,
                peerIds: j["peerIds"] as! [String],
                peerNames: (j["peerNames"] as? [String: String]) ?? [:],
                durationOverrideSec: (j["durationOverrideSec"] as? NSNumber)?.intValue)
        case "tag":
            return .tag(taggerId: j["taggerId"] as! String, victimId: j["victimId"] as! String,
                        timeMs: (j["timeMs"] as! NSNumber).int64Value)
        case "unfreeze":
            return .unfreeze(unfreezerId: j["unfreezerId"] as! String, victimId: j["victimId"] as! String,
                             timeMs: (j["timeMs"] as! NSNumber).int64Value)
        case "end":
            return .end(reason: j["reason"] as! String, winnerId: j["winnerId"] as? String)
        case "tutorial_call":
            return .tutorialCall
        case "tutorial_vote":
            return .tutorialVote(voterId: j["voterId"] as! String, yes: j["yes"] as! Bool)
        case "tutorial_state":
            return .tutorialState(
                isOpen: j["isOpen"] as! Bool,
                yesCount: j["yesCount"] as! Int, noCount: j["noCount"] as! Int,
                eligibleCount: j["eligibleCount"] as! Int,
                result: j["result"] as? Bool,
                tutorialShown: j["tutorialShown"] as! Bool)
        default: throw NSError(domain: "TagMessage", code: 1)
        }
    }
}
