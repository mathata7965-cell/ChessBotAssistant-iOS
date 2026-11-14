import Foundation
import Photos
import UIKit

@MainActor
final class PhotoLibraryScreenshotMonitor: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastDetectedScreenshotDate: Date?

    var onNewScreenshot: ((UIImage) -> Void)?

    private var fetchResult: PHFetchResult<PHAsset>?
    private var lastProcessedAssetID: String?

    override init() {
        super.init()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestPermissionAndStart() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        guard status == .authorized || status == .limited else {
            isMonitoring = false
            return false
        }
        startMonitoring()
        return true
    }

    func startMonitoring() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status
        guard status == .authorized || status == .limited else {
            isMonitoring = false
            return
        }

        if !isMonitoring {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType == %d AND ((mediaSubtype & %d) != 0)",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let initial = PHAsset.fetchAssets(with: options)
            self.fetchResult = initial
            self.lastProcessedAssetID = initial.firstObject?.localIdentifier
            PHPhotoLibrary.shared().register(self)
            isMonitoring = true
        }
    }

    func stopMonitoring() {
        if isMonitoring {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            isMonitoring = false
        }
    }

    func fetchLatestScreenshot() async -> UIImage? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        guard status == .authorized || status == .limited else { return nil }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND ((mediaSubtype & %d) != 0)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        let result = PHAsset.fetchAssets(with: options)
        if let latest = result.firstObject {
            return await loadUIImage(from: latest)
        }

        // Fallback: latest image in photo library if screenshot subtype wasn't set
        let fallbackOptions = PHFetchOptions()
        fallbackOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fallbackOptions.fetchLimit = 1
        let fallbackResult = PHAsset.fetchAssets(with: .image, options: fallbackOptions)
        guard let asset = fallbackResult.firstObject else { return nil }
        return await loadUIImage(from: asset)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self, self.isMonitoring, let currentFetch = self.fetchResult else { return }
            guard let changes = changeInstance.changeDetails(for: currentFetch) else { return }
            self.fetchResult = changes.fetchResultAfterChanges

            let inserted = changes.insertedObjects
            guard let newestAsset = inserted.first ?? changes.fetchResultAfterChanges.firstObject else { return }
            guard newestAsset.localIdentifier != self.lastProcessedAssetID else { return }

            if let created = newestAsset.creationDate, Date().timeIntervalSince(created) < 15.0 {
                self.lastProcessedAssetID = newestAsset.localIdentifier
                self.lastDetectedScreenshotDate = created
                if let image = await self.loadUIImage(from: newestAsset) {
                    self.onNewScreenshot?(image)
                }
            }
        }
    }

    private func loadUIImage(from asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            var resumed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded && !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
