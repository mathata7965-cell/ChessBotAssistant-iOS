import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import QuartzCore
import ReplayKit
import UIKit

final class BroadcastSampleHandler: RPBroadcastSampleHandler {
    private struct BroadcastPayload: Encodable {
        let fen: String
        let perspective: String
        let sideToMove: String
        let confidence: Double
        let notes: String
        let timestamp: Double
    }

    private var lastProcessedTime: CFTimeInterval = 0
    private var lastBoard: ChessBoardState = .startingPosition
    private var lastPerspective: PieceColor = .white
    private let ciContext = CIContext(options: [.useSoftwareRenderer: true])
    private var udpFD: Int32 = -1

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        lastProcessedTime = 0
        lastBoard = .startingPosition
        lastPerspective = .white
        openUDPSocketIfNeeded()
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        closeUDPSocket()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = CACurrentMediaTime()
        guard now - lastProcessedTime >= 0.45 else { return }
        lastProcessedTime = now

        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            if let orientationAttachment = CMGetAttachment(
                sampleBuffer,
                key: RPVideoSampleOrientationKey as CFString,
                attachmentModeOut: nil
            ) as? NSNumber {
                ciImage = ciImage.oriented(forExifOrientation: Int32(orientationAttachment.uint32Value))
            }
            if ciImage.extent.origin != .zero {
                ciImage = ciImage.transformed(
                    by: CGAffineTransform(translationX: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
                )
            }

            let extent = ciImage.extent
            guard extent.width >= 120, extent.height >= 120 else { return }

            let scale = min(1.0, 480.0 / extent.width)
            let scaledImage: CIImage = scale < 0.99
                ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                : ciImage

            guard let cgImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent) else {
                return
            }

            guard let result = ScreenshotBoardRecognizer.shared.recognizeBoardSync(
                from: cgImage,
                fallbackPerspective: lastPerspective,
                sideToMove: nil,
                previousBoard: lastBoard,
                includePNGCrop: false
            ) else {
                return
            }

            lastBoard = result.boardState
            lastPerspective = result.detectedPerspective

            let payload = BroadcastPayload(
                fen: result.boardState.toFEN(),
                perspective: result.detectedPerspective.rawValue,
                sideToMove: result.boardState.sideToMove.rawValue,
                confidence: result.confidence,
                notes: result.notes,
                timestamp: Date().timeIntervalSince1970
            )
            sendPayloadOverUDP(payload)
        }
    }

    private func openUDPSocketIfNeeded() {
        guard udpFD < 0 else { return }
        udpFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    }

    private func closeUDPSocket() {
        if udpFD >= 0 {
            close(udpFD)
            udpFD = -1
        }
    }

    private func sendPayloadOverUDP(_ payload: BroadcastPayload) {
        openUDPSocketIfNeeded()
        guard udpFD >= 0, let jsonData = try? JSONEncoder().encode(payload) else { return }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(49876).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        jsonData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = sendto(
                        udpFD,
                        baseAddress,
                        jsonData.count,
                        0,
                        saPtr,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }
}
