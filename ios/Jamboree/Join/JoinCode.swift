import Foundation

/// Encodes / decodes a 7-character base-36 join code that maps to an IPv4
/// address. The port is fixed at `HostServer.defaultPort` (7654), so the host
/// only needs to share the IP. A 7-char base-36 string covers every IPv4
/// (36⁷ ≈ 78B > 4.29B). Codes are displayed split for readability
/// ("ABCD-EFG") and decoded case-insensitively, stripping non-alphanumerics.
enum JoinCode {
    static let defaultPort: UInt16 = 7654
    static let codeLength = 7
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// IPv4 string → 7-char uppercase base-36 code, hyphenated as 4-3.
    static func encode(ip: String) -> String? {
        guard let n = ipToUInt32(ip) else { return nil }
        var num = UInt64(n)
        var chars = [Character](repeating: "0", count: codeLength)
        for i in (0..<codeLength).reversed() {
            chars[i] = alphabet[Int(num % 36)]
            num /= 36
        }
        let raw = String(chars).uppercased()
        let split = raw.index(raw.startIndex, offsetBy: 4)
        return "\(raw[..<split])-\(raw[split...])"
    }

    /// User-entered text → IPv4 string. Accepts:
    ///   - a join code ("ABCD-EFG", "abcdefg", "ABCD EFG")
    ///   - a raw IPv4 ("192.168.1.42")
    /// Returns nil if neither form parses.
    static func decode(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(".") { return parseIp(trimmed) }
        let cleaned = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == codeLength else { return nil }
        var n: UInt64 = 0
        for c in cleaned {
            guard let i = alphabet.firstIndex(of: c) else { return nil }
            n = n * 36 + UInt64(i)
        }
        guard n <= 0xFFFF_FFFF else { return nil }
        return uint32ToIp(UInt32(n))
    }

    private static func parseIp(_ s: String) -> String? {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for p in parts {
            guard let v = Int(p), (0...255).contains(v) else { return nil }
            bytes.append(UInt8(v))
        }
        return bytes.map(String.init).joined(separator: ".")
    }

    private static func ipToUInt32(_ s: String) -> UInt32? {
        guard let ip = parseIp(s) else { return nil }
        let bytes = ip.split(separator: ".").compactMap { UInt32($0) }
        guard bytes.count == 4 else { return nil }
        return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
    }

    private static func uint32ToIp(_ n: UInt32) -> String {
        let a = (n >> 24) & 0xFF, b = (n >> 16) & 0xFF
        let c = (n >> 8) & 0xFF, d = n & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}
