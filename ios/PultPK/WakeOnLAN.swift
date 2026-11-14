import Foundation
import Darwin

enum WakeOnLAN {
    static func magicPacket(mac: String) -> [UInt8]? {
        let hex = mac.filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return [UInt8](repeating: 0xFF, count: 6) + (0..<16).flatMap { _ in bytes }
    }

    private static func sendUDP(_ data: [UInt8], host: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }
        let n = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                sendto(fd, data, data.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return n == data.count
    }

    /// Отправляет magic packet напрямую на ПК и широковещательно.
    static func send(mac: String, pcIP: String) -> Bool {
        guard let packet = magicPacket(mac: mac) else { return false }
        var targets = [pcIP, "255.255.255.255"]
        let parts = pcIP.split(separator: ".")
        if parts.count == 4 { targets.append(parts[0...2].joined(separator: ".") + ".255") }
        var sent = false
        for _ in 0..<3 {
            for host in targets {
                for port: UInt16 in [9, 7] where sendUDP(packet, host: host, port: port) { sent = true }
            }
            usleep(150_000)
        }
        return sent
    }

    static func isOnline(host: String, port: String) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/manifest.json") else { return false }
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.5)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
