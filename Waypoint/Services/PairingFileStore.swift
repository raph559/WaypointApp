import Foundation

enum PairingFileStore {
    static let fileName = "rp_pairing_file.plist"

    static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func importFile(at sourceURL: URL) throws {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: sourceURL)
        try replace(with: data)
    }

    static func importBase64(_ encoded: String) throws {
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else {
            throw PairingFileError.invalidPayload
        }
        try replace(with: data)
    }

    static func replace(with data: Data) throws {
        guard !data.isEmpty else { throw PairingFileError.invalidPayload }

        let manager = FileManager.default
        try manager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        var protectedURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? protectedURL.setResourceValues(resourceValues)
    }

    private static var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }
}

enum PairingFileError: LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        "The pairing record is empty or invalid."
    }
}
