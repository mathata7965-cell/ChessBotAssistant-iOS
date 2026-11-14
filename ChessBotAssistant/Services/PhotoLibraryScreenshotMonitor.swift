import Foundation
import Photos
import UIKit

@MainActor
final class PhotoLibraryScreenshotMonitor: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastDetectedScreenshotDate: Date?
    @Published private(set) var hasDeletableScreenshot: Bool = false

    var onNewScreenshot: ((UIImage) -> Void)?

    private var fetchResult: PHFetchResult<PHAsset>?
    private var lastProcessedAssetID: String?
    private var lastProcessedAsset: PHAsset?
    private var inFlightAssetID: String?
    private var inFlightTimestamp: Date = .distantPast
    private var pollTimer: Timer?

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

            let recentCheckOptions = PHFetchOptions()
            recentCheckOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            recentCheckOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            recentCheckOptions.fetchLimit = 1
            let latestAny = PHAsset.fetchAssets(with: recentCheckOptions).firstObject ?? initial.firstObject

            if let latestCreated = latestAny?.creationDate,
               Date().timeIntervalSince(latestCreated) <= 180.0 {
                self.lastProcessedAssetID = nil
            } else {
                self.lastProcessedAssetID = latestAny?.localIdentifier
            }

            PHPhotoLibrary.shared().register(self)
            isMonitoring = true

            pollTimer?.invalidate()
            let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                Task { @MainActor [weak self] in
                    self?.pollLatestScreenshotAsset()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer

            if self.lastProcessedAssetID == nil {
                pollLatestScreenshotAsset()
            }
        }
    }

    func checkForRecentScreenshotNow() {
        if isMonitoring {
            pollLatestScreenshotAsset()
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        inFlightAssetID = nil
        if isMonitoring {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            isMonitoring = false
        }
    }

    private func pollLatestScreenshotAsset() {
        guard isMonitoring else { return }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        let latest = PHAsset.fetchAssets(with: options)
        guard let asset = latest.firstObject else { return }
        guard let creationDate = asset.creationDate,
              Date().timeIntervalSince(creationDate) <= 120.0 else {
            return
        }

        enqueueAssetIfReady(asset, creationDate: creationDate)
    }

    private func enqueueAssetIfReady(_ asset: PHAsset, creationDate: Date) {
        let assetID = asset.localIdentifier
        guard assetID != lastProcessedAssetID else { return }
        if inFlightAssetID == assetID && Date().timeIntervalSince(inFlightTimestamp) < 2.0 {
            return
        }

        inFlightAssetID = assetID
        inFlightTimestamp = Date()

        let reqOptions = PHImageRequestOptions()
        reqOptions.deliveryMode = .opportunistic
        reqOptions.resizeMode = .fast
        reqOptions.isNetworkAccessAllowed = true
        reqOptions.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 960, height: 2080),
            contentMode: .aspectFit,
            options: reqOptions
        ) { [weak self] image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let image, image.size.width * image.scale >= 240 else {
                    if !isDegraded && self.inFlightAssetID == assetID {
                        self.inFlightAssetID = nil
                    }
                    return
                }
                guard self.lastProcessedAssetID != assetID else { return }
                self.lastProcessedAssetID = assetID
                self.inFlightAssetID = nil
                self.lastProcessedAsset = asset
                self.lastDetectedScreenshotDate = creationDate
                self.hasDeletableScreenshot = true
                self.onNewScreenshot?(image)
            }
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
            self.lastProcessedAsset = latest
            self.lastProcessedAssetID = latest.localIdentifier
            self.hasDeletableScreenshot = true
            return await loadUIImage(from: latest)
        }

        // Fallback: latest image in photo library if screenshot subtype wasn't set
        let fallbackOptions = PHFetchOptions()
        fallbackOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fallbackOptions.fetchLimit = 1
        let fallbackResult = PHAsset.fetchAssets(with: .image, options: fallbackOptions)
        guard let asset = fallbackResult.firstObject else { return nil }
        self.lastProcessedAsset = asset
        self.lastProcessedAssetID = asset.localIdentifier
        self.hasDeletableScreenshot = true
        return await loadUIImage(from: asset)
    }

    func deleteLastDetectedScreenshot() async -> Bool {
        guard let asset = lastProcessedAsset else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
            self.lastProcessedAsset = nil
            self.hasDeletableScreenshot = false
            return true
        } catch {
            return false
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self, self.isMonitoring, let currentFetch = self.fetchResult else { return }
            guard let changes = changeInstance.changeDetails(for: currentFetch) else { return }
            self.fetchResult = changes.fetchResultAfterChanges

            let inserted = changes.insertedObjects
            guard let newestAsset = inserted.first ?? changes.fetchResultAfterChanges.firstObject else { return }
            guard newestAsset.localIdentifier != self.lastProcessedAssetID else { return }

            if let created = newestAsset.creationDate, Date().timeIntervalSince(created) <= 120.0 {
                self.enqueueAssetIfReady(newestAsset, creationDate: created)
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
