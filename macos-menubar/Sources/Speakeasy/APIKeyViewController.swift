import AppKit

protocol APIKeyViewControllerDelegate: AnyObject {
    func apiKeyDidSave(key: String)
    func apiKeyDidCancel()
}

class APIKeyViewController: NSViewController {
    weak var delegate: APIKeyViewControllerDelegate?

    var apiKeyTextField: PasteableTextField!
    var saveButton: NSButton!
    var cancelButton: NSButton!

    private let placeholderText = "sk-..."

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 100))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyLabel = NSTextField(labelWithString: "OpenAI API Key:")

        // Use a regular text field just like the working login, but make it taller
        apiKeyTextField = PasteableTextField()
        apiKeyTextField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        apiKeyTextField.placeholderString = placeholderText

        // If there's an existing key, show it
        if let existingKey = SettingsManager.shared.getOpenAIKey(), !existingKey.isEmpty {
            apiKeyTextField.stringValue = existingKey
        }

        saveButton = NSButton(title: "Save", target: self, action: #selector(saveButtonPressed))
        saveButton.bezelStyle = .rounded

        cancelButton = NSButton(
            title: "Cancel", target: self, action: #selector(cancelButtonPressed))
        cancelButton.bezelStyle = .rounded

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(keyLabel)
        stackView.addArrangedSubview(apiKeyTextField)

        let buttonStackView = NSStackView()
        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .centerY
        buttonStackView.spacing = 8
        buttonStackView.distribution = .fillProportionally
        buttonStackView.addArrangedSubview(saveButton)
        buttonStackView.addArrangedSubview(cancelButton)
        stackView.addArrangedSubview(buttonStackView)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10),

            // Make the text field wide enough for the API key
            apiKeyTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
            apiKeyTextField.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @objc func saveButtonPressed() {
        let apiKey = apiKeyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        delegate?.apiKeyDidSave(key: apiKey)
    }

    @objc func cancelButtonPressed() {
        delegate?.apiKeyDidCancel()
    }
}
