import Foundation

protocol ModelDownloadServiceDelegate: AnyObject {
    func downloadDidUpdateProgress(_ progress: Double)
    func downloadDidComplete(modelPath: String)
    func downloadDidFail(error: Error)
}

class ModelDownloadService: NSObject {
    static let shared = ModelDownloadService()

    weak var delegate: ModelDownloadServiceDelegate?

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?

    private(set) var isDownloading = false

    enum DownloadError: LocalizedError {
        case alreadyDownloading
        case directoryCreationFailed(Error)
        case fileMoveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .alreadyDownloading:
                return "A download is already in progress."
            case .directoryCreationFailed(let error):
                return "Failed to create models directory: \(error.localizedDescription)"
            case .fileMoveFailed(let error):
                return "Failed to move downloaded model: \(error.localizedDescription)"
            }
        }
    }

    func startDownload() {
        guard !isDownloading else {
            delegate?.downloadDidFail(error: DownloadError.alreadyDownloading)
            return
        }

        do {
            try SettingsManager.shared.ensureModelsDirectoryExists()
        } catch {
            delegate?.downloadDidFail(error: DownloadError.directoryCreationFailed(error))
            return
        }

        isDownloading = true

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        let request = URLRequest(url: SettingsManager.defaultModelURL)
        downloadTask = session?.downloadTask(with: request)
        downloadTask?.resume()

        Log.general.info(
            "Started model download from: \(SettingsManager.defaultModelURL, privacy: .public)")
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        isDownloading = false
        Log.general.info("Model download cancelled")
    }
}

extension ModelDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destinationPath = SettingsManager.shared.defaultModelPath
        let destinationURL = URL(fileURLWithPath: destinationPath)

        do {
            // Remove any existing file at the destination
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)

            isDownloading = false
            self.downloadTask = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil

            Log.general.info("Model downloaded to: \(destinationPath, privacy: .public)")
            delegate?.downloadDidComplete(modelPath: destinationPath)
        } catch {
            isDownloading = false
            self.downloadTask = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil

            Log.general.error(
                "Failed to move downloaded model: \(error.localizedDescription, privacy: .public)"
            )
            delegate?.downloadDidFail(error: DownloadError.fileMoveFailed(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        delegate?.downloadDidUpdateProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error else { return }

        // Ignore cancellation errors (user-initiated)
        if (error as NSError).code == NSURLErrorCancelled {
            return
        }

        isDownloading = false
        downloadTask = nil
        self.session?.finishTasksAndInvalidate()
        self.session = nil

        Log.general.error("Model download failed: \(error.localizedDescription, privacy: .public)")
        delegate?.downloadDidFail(error: error)
    }
}
