import Darwin
import Foundation

struct LiveBroadcastPayload: Codable, Sendable {
    let fen: String
    let perspective: String
    let sideToMove: String
    let confidence: Double
    let notes: String
    let campConfidence: Double?
    let campDetectionReason: String?
    let timestamp: Double
    let boardDetected: Bool?
}

@MainActor
final class LiveScreenBroadcastService: ObservableObject {
    static let udpPort: UInt16 = 49876

    @Published private(set) var isBroadcastActive: Bool = false
    @Published private(set) var receivedFrameCount: Int = 0
    @Published private(set) var lastReceivedDate: Date?

    var onPayloadReceived: ((LiveBroadcastPayload) -> Void)?

    private final class UDPState: @unchecked Sendable {
        var fd: Int32 = -1
        var isRunning: Bool = false
    }

    private let udpState = UDPState()
    private let listenQueue = DispatchQueue(label: "com.example.ChessBotAssistant.udpListener", qos: .userInteractive)
    private var inactivityTimer: Timer?

    init() {
        startListening()
        startInactivityWatchdog()
    }

    deinit {
        udpState.isRunning = false
        if udpState.fd >= 0 {
            close(udpState.fd)
            udpState.fd = -1
        }
    }

    func startListening() {
        guard !udpState.isRunning else { return }
        udpState.isRunning = true

        let state = udpState
        listenQueue.async { [weak self] in
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else {
                state.isRunning = false
                return
            }

            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

            var tv = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = LiveScreenBroadcastService.udpPort.bigEndian
            addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            guard bindResult == 0 else {
                close(fd)
                state.isRunning = false
                return
            }

            state.fd = fd
            var buffer = [UInt8](repeating: 0, count: 4096)
            let decoder = JSONDecoder()

            while state.isRunning {
                let bytesRead = recv(fd, &buffer, buffer.count, 0)
                if bytesRead > 0 {
                    let data = Data(buffer.prefix(bytesRead))
                    if let payload = try? decoder.decode(LiveBroadcastPayload.self, from: data) {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.isBroadcastActive = true
                            self.receivedFrameCount += 1
                            self.lastReceivedDate = Date()
                            self.onPayloadReceived?(payload)
                        }
                    }
                } else if bytesRead < 0 {
                    let err = errno
                    if err != EAGAIN && err != EWOULDBLOCK && err != EINTR {
                        break
                    }
                }
            }

            if state.fd >= 0 {
                close(state.fd)
                state.fd = -1
            }
            state.isRunning = false
        }
    }

    func stopListening() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        udpState.isRunning = false
        if udpState.fd >= 0 {
            close(udpState.fd)
            udpState.fd = -1
        }
        isBroadcastActive = false
    }

    private func startInactivityWatchdog() {
        inactivityTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let last = self.lastReceivedDate, Date().timeIntervalSince(last) > 4.0 {
                    if self.isBroadcastActive {
                        self.isBroadcastActive = false
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        inactivityTimer = timer
    }
}
