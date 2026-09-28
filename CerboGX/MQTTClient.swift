import Foundation
import Network
import Security

/// Minimal MQTT 3.1.1 client for the Cerbo GX broker.
/// Secured Venus OS profiles require TLS on port 8883 and the GX network password.
final class MQTTClient: @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        var host: String
        var port: UInt16
        var useTLS: Bool
        var username: String
        var password: String
    }

    enum Event: Sendable {
        case state(LinkState)
        case messages([(topic: String, payload: Data)])
    }

    var onEvent: ((Event) -> Void)?

    private let queue = DispatchQueue(label: "cerbo.mqtt")
    private var connection: NWConnection?
    /// Raw bytes. Kept as an Array so indexes stay zero-based. `Data.removeFirst`
    /// leaves `startIndex` nonzero, and the next `buffer[i]` traps.
    private var buffer = [UInt8]()
    private var config: Configuration?
    private var generation = 0
    private var sessionReady = false
    private var stopped = true
    private var retryAttempt = 0
    private var nextPacketID: UInt16 = 1
    private var pending: [Data] = []

    func start(_ config: Configuration) {
        queue.async {
            self.stopped = false
            self.retryAttempt = 0
            self.config = config
            self.open()
        }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.generation += 1
            self.sessionReady = false
            self.pending.removeAll()
            self.buffer.removeAll()
            self.connection?.cancel()
            self.connection = nil
        }
    }

    func subscribe(topic: String) {
        queue.async {
            let packet = self.subscribePacket(topic: topic)
            self.enqueue(packet)
        }
    }

    func publish(topic: String, payload: Data) {
        queue.async {
            self.enqueue(self.publishPacket(topic: topic, payload: payload))
        }
    }

    func ping() {
        queue.async {
            self.enqueue(Data([0xC0, 0x00]))
        }
    }

    private func open() {
        guard !stopped, let config else { return }
        generation += 1
        let gen = generation
        sessionReady = false
        pending.removeAll()
        buffer.removeAll()
        connection?.cancel()

        let parameters: NWParameters
        if config.useTLS {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in
                // Venus OS ships a self-signed certificate.
                complete(true)
            }, queue)
            if let name = config.host.cString(using: .utf8) {
                name.withUnsafeBufferPointer { buffer in
                    if let base = buffer.baseAddress {
                        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, base)
                    }
                }
            }
            parameters = NWParameters(tls: tls)
        } else {
            parameters = .tcp
        }
        parameters.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: config.port) else {
            emit(.state(.failed("Port \(config.port) is invalid.")))
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(config.host), port: nwPort, using: parameters)
        self.connection = connection
        emit(.state(.connecting))

        connection.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                guard let self, gen == self.generation else { return }
                switch state {
                case .ready:
                    self.send(self.connectPacket(config))
                    self.receive(gen: gen)
                case .failed(let error):
                    self.handleDrop(error, gen: gen)
                case .waiting(let error):
                    let text = error.localizedDescription
                    if text.localizedCaseInsensitiveContains("local network") {
                        self.emit(.state(.failed("Allow Local Network access for Cerbo GX in Settings.")))
                        self.stopped = true
                        connection.cancel()
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func handleDrop(_ error: NWError?, gen: Int) {
        guard gen == generation, !stopped else { return }
        sessionReady = false
        connection?.cancel()
        connection = nil
        let message = error.map(Self.describe) ?? "Connection closed."
        if message.localizedCaseInsensitiveContains("local network") {
            emit(.state(.failed("Allow Local Network access for Cerbo GX in Settings.")))
            stopped = true
            return
        }
        emit(.state(.failed(message)))
        let attempt = retryAttempt
        retryAttempt = min(retryAttempt + 1, 5)
        let delay = min(20.0, pow(2.0, Double(attempt)))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation, !self.stopped else { return }
            self.open()
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            return "Network error: \(code.summary)"
        case .dns:
            return "Could not find the Cerbo on the network."
        case .tls:
            return "TLS handshake failed. The GX certificate was rejected."
        default:
            return error.localizedDescription
        }
    }

    private func receive(gen: Int) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            self?.queue.async {
                guard let self, gen == self.generation else { return }
                if let data, !data.isEmpty {
                    self.ingest([UInt8](data))
                }
                if let error {
                    self.handleDrop(error, gen: gen)
                    return
                }
                if isComplete {
                    self.handleDrop(nil, gen: gen)
                    return
                }
                self.receive(gen: gen)
            }
        }
    }

    private func ingest(_ data: [UInt8]) {
        buffer.append(contentsOf: data)
        var batch: [(topic: String, payload: Data)] = []
        while let packet = popPacket() {
            switch packet[0] & 0xF0 {
            case 0x20:
                handleConnAck(packet)
            case 0x30:
                if let message = parsePublish(packet) {
                    batch.append(message)
                    let qos = (packet[0] >> 1) & 0x03
                    if qos > 0, let id = packetIdentifier(packet) {
                        enqueue(Data([0x40, 0x02, UInt8(id >> 8), UInt8(id & 0xFF)]))
                    }
                }
            default:
                break
            }
        }
        if !batch.isEmpty {
            emit(.messages(batch))
        }
    }

    private func handleConnAck(_ packet: Data) {
        guard let body = body(of: packet), body.count >= 2 else { return }
        let code = body[body.startIndex + 1]
        switch code {
        case 0:
            sessionReady = true
            retryAttempt = 0
            let queued = pending
            pending.removeAll()
            queued.forEach(send)
            emit(.state(.connected))
        case 4, 5:
            stopped = true
            emit(.state(.failed(code == 4
                ? "The Cerbo rejected that username or password."
                : "The Cerbo refused the connection. Check the network password.")))
            connection?.cancel()
        default:
            stopped = true
            emit(.state(.failed("MQTT connection refused (code \(code)).")))
            connection?.cancel()
        }
    }

    private func popPacket() -> Data? {
        guard buffer.count >= 2 else { return nil }
        var index = 1
        var multiplier = 1
        var length = 0
        while index < buffer.count {
            let byte = Int(buffer[index])
            length += (byte & 0x7F) * multiplier
            index += 1
            if byte & 0x80 == 0 {
                if length > 2_000_000 {
                    buffer.removeAll()
                    return nil
                }
                let total = index + length
                guard buffer.count >= total else { return nil }
                let packet = Data(buffer.prefix(total))
                buffer.removeFirst(total)
                return packet
            }
            multiplier *= 128
            if multiplier > 128 * 128 * 128 * 128 {
                buffer.removeAll()
                return nil
            }
        }
        return nil
    }

    private func body(of packet: Data) -> Data? {
        var index = 1
        while index < packet.count {
            let continued = packet[index] & 0x80 != 0
            index += 1
            if !continued { return packet.subdata(in: index..<packet.count) }
        }
        return nil
    }

    private func parsePublish(_ packet: Data) -> (String, Data)? {
        guard let body = body(of: packet), body.count >= 2 else { return nil }
        let topicLength = Int(body[0]) << 8 | Int(body[1])
        guard body.count >= 2 + topicLength else { return nil }
        let topic = String(data: body.subdata(in: 2..<(2 + topicLength)), encoding: .utf8) ?? ""
        var offset = 2 + topicLength
        let qos = (packet[0] >> 1) & 0x03
        if qos > 0 { offset += 2 }
        guard offset <= body.count else { return nil }
        return (topic, Data(body.dropFirst(offset)))
    }

    private func packetIdentifier(_ packet: Data) -> UInt16? {
        guard let body = body(of: packet), body.count >= 4 else { return nil }
        let topicLength = Int(body[0]) << 8 | Int(body[1])
        let offset = 2 + topicLength
        guard body.count >= offset + 2 else { return nil }
        return UInt16(body[offset]) << 8 | UInt16(body[offset + 1])
    }

    private func enqueue(_ packet: Data) {
        if sessionReady {
            send(packet)
        } else {
            pending.append(packet)
        }
    }

    private func send(_ packet: Data) {
        connection?.send(content: packet, completion: .contentProcessed { _ in })
    }

    /// One ID per app install so iPhone and iPad can stay connected at the same time.
    private static let clientIDKey = "cerbo.mqttClientId"

    private static func clientID() -> Data {
        if let saved = UserDefaults.standard.string(forKey: clientIDKey), !saved.isEmpty {
            return Data(saved.utf8)
        }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10)
        let id = "cerbogx-\(suffix)"
        UserDefaults.standard.set(id, forKey: clientIDKey)
        return Data(id.utf8)
    }

    private func connectPacket(_ config: Configuration) -> Data {
        let clientID = Self.clientID()
        var flags: UInt8 = 0x02
        let user = Data(config.username.utf8)
        let pass = Data(config.password.utf8)
        if !user.isEmpty { flags |= 0x80 }
        if !pass.isEmpty { flags |= 0x40 }
        var payload = Data()
        payload.append(encoded(clientID))
        if flags & 0x80 != 0 { payload.append(encoded(user)) }
        if flags & 0x40 != 0 { payload.append(encoded(pass)) }

        var variable = Data([0x00, 0x04]) + Data("MQTT".utf8)
        variable.append(0x04)
        variable.append(flags)
        variable.append(0x00)
        variable.append(30)
        return packet(type: 0x10, body: variable + payload)
    }

    private func subscribePacket(topic: String) -> Data {
        let id = nextPacketID
        nextPacketID = nextPacketID &+ 1
        if nextPacketID == 0 { nextPacketID = 1 }
        var body = Data([UInt8(id >> 8), UInt8(id & 0xFF)])
        body.append(encoded(Data(topic.utf8)))
        body.append(0x00)
        return packet(type: 0x82, body: body)
    }

    private func publishPacket(topic: String, payload: Data) -> Data {
        packet(type: 0x30, body: encoded(Data(topic.utf8)) + payload)
    }

    private func packet(type: UInt8, body: Data) -> Data {
        Data([type]) + encodedLength(body.count) + body
    }

    private func encoded(_ data: Data) -> Data {
        var out = Data([UInt8(data.count >> 8), UInt8(data.count & 0xFF)])
        out.append(data)
        return out
    }

    private func encodedLength(_ length: Int) -> Data {
        var value = length
        var bytes = Data()
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value > 0
        return bytes
    }

    private func emit(_ event: Event) {
        let handler = onEvent
        DispatchQueue.main.async {
            handler?(event)
        }
    }
}

enum LinkState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

private extension POSIXErrorCode {
    var summary: String {
        switch self {
        case .ECONNREFUSED: return "connection refused"
        case .ETIMEDOUT: return "timed out"
        case .EHOSTUNREACH, .ENETUNREACH: return "host unreachable"
        case .ECONNRESET: return "connection reset"
        default: return "connection failed"
        }
    }
}
