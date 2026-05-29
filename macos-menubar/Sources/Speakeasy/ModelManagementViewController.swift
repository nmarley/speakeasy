import AppKit

protocol ModelManagementViewControllerDelegate: AnyObject {
    func modelDidFinishDownloading(modelPath: String)
    func modelManagementDidClose()
    func modelDidDelete()
}

class ModelManagementViewController: NSViewController, ModelDownloadServiceDelegate {
    weak var delegate: ModelManagementViewControllerDelegate?

    private var titleLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var actionButton: NSButton!
    private var cancelButton: NSButton!
    private var deleteButton: NSButton!

    private let hasModel: Bool

    init(hasModel: Bool) {
        self.hasModel = hasModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 130))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = 1.0
        progressBar.isIndeterminate = false
        progressBar.isHidden = true

        actionButton = NSButton(title: "", target: self, action: #selector(actionButtonPressed))
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular

        cancelButton = NSButton(
            title: "Close", target: self, action: #selector(closeButtonPressed))
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .regular

        deleteButton = NSButton(
            title: "Delete Model", target: self, action: #selector(deleteButtonPressed))
        deleteButton.bezelStyle = .rounded
        deleteButton.controlSize = .regular
        deleteButton.contentTintColor = .systemRed

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.addArrangedSubview(actionButton)
        buttonStack.addArrangedSubview(deleteButton)
        buttonStack.addArrangedSubview(cancelButton)

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(progressBar)
        stackView.addArrangedSubview(buttonStack)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(
                lessThanOrEqualTo: view.bottomAnchor, constant: -12),
            progressBar.widthAnchor.constraint(equalTo: stackView.widthAnchor),
        ])

        updateForCurrentState()
    }

    private func updateForCurrentState() {
        if ModelDownloadService.shared.isDownloading {
            showDownloadingState()
        } else if hasModel {
            showModelLoadedState()
        } else {
            showNoModelState()
        }
    }

    private func showNoModelState() {
        titleLabel.stringValue = "Whisper Model Required"
        statusLabel.stringValue =
            "Download \(SettingsManager.defaultModelName) (\(SettingsManager.defaultModelSize)) to enable speech-to-text."
        progressBar.isHidden = true
        actionButton.title = "Download Model"
        actionButton.isHidden = false
        actionButton.isEnabled = true
        deleteButton.isHidden = true
        cancelButton.title = "Close"
    }

    private func showDownloadingState() {
        titleLabel.stringValue = "Downloading Model"
        statusLabel.stringValue = "Downloading \(SettingsManager.defaultModelName)..."
        progressBar.isHidden = false
        progressBar.doubleValue = 0
        actionButton.title = "Cancel Download"
        actionButton.isHidden = false
        actionButton.isEnabled = true
        deleteButton.isHidden = true
        cancelButton.title = "Close"
        cancelButton.isEnabled = false
    }

    private func showModelLoadedState() {
        titleLabel.stringValue = "Whisper Model"
        let sizeText: String
        if let size = SettingsManager.shared.modelFileSize() {
            sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            sizeText = SettingsManager.defaultModelSize
        }
        statusLabel.stringValue = "Model: \(SettingsManager.defaultModelName) (\(sizeText))"
        progressBar.isHidden = true
        actionButton.isHidden = true
        deleteButton.isHidden = false
        cancelButton.title = "Close"
        cancelButton.isEnabled = true
    }

    private func showDownloadCompleteState() {
        titleLabel.stringValue = "Download Complete"
        statusLabel.stringValue = "Model \(SettingsManager.defaultModelName) is ready."
        progressBar.isHidden = true
        actionButton.isHidden = true
        deleteButton.isHidden = true
        cancelButton.title = "Close"
        cancelButton.isEnabled = true
    }

    private func showErrorState(message: String) {
        titleLabel.stringValue = "Download Failed"
        statusLabel.stringValue = message
        progressBar.isHidden = true
        actionButton.title = "Retry Download"
        actionButton.isHidden = false
        actionButton.isEnabled = true
        deleteButton.isHidden = true
        cancelButton.title = "Close"
        cancelButton.isEnabled = true
    }

    @objc private func actionButtonPressed() {
        if ModelDownloadService.shared.isDownloading {
            ModelDownloadService.shared.cancelDownload()
            showNoModelState()
        } else {
            ModelDownloadService.shared.delegate = self
            ModelDownloadService.shared.startDownload()
            showDownloadingState()
        }
    }

    @objc private func closeButtonPressed() {
        delegate?.modelManagementDidClose()
    }

    @objc private func deleteButtonPressed() {
        let alert = NSAlert()
        alert.messageText = "Delete Whisper Model?"
        alert.informativeText =
            "This will remove the downloaded model. You will need to download it again to use speech-to-text."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        do {
            try SettingsManager.shared.deleteModel()
            delegate?.modelDidDelete()
            showNoModelState()
        } catch {
            Log.general.error(
                "Failed to delete model: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - ModelDownloadServiceDelegate

    func downloadDidUpdateProgress(_ progress: Double) {
        progressBar.doubleValue = progress
        let pct = Int(progress * 100)
        statusLabel.stringValue =
            "Downloading \(SettingsManager.defaultModelName)... \(pct)%"
    }

    func downloadDidComplete(modelPath: String) {
        showDownloadCompleteState()
        delegate?.modelDidFinishDownloading(modelPath: modelPath)
    }

    func downloadDidFail(error: Error) {
        showErrorState(message: error.localizedDescription)
    }
}
