import Foundation

struct DeveloperImagePaths: Sendable {
    let image: URL
    let trustCache: URL
    let buildManifest: URL
}

struct DeveloperImageArtifact: Sendable {
    let label: String
    let remoteURL: URL
    let localName: String
}

enum DeveloperImageStore {
    static let artifacts: [DeveloperImageArtifact] = [
        DeveloperImageArtifact(
            label: "developer image",
            remoteURL: URL(string: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg")!,
            localName: "Image.dmg"
        ),
        DeveloperImageArtifact(
            label: "trust cache",
            remoteURL: URL(string: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache")!,
            localName: "Image.dmg.trustcache"
        ),
        DeveloperImageArtifact(
            label: "build manifest",
            remoteURL: URL(string: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/BuildManifest.plist")!,
            localName: "BuildManifest.plist"
        )
    ]

    static var paths: DeveloperImagePaths {
        DeveloperImagePaths(
            image: directory.appendingPathComponent("Image.dmg"),
            trustCache: directory.appendingPathComponent("Image.dmg.trustcache"),
            buildManifest: directory.appendingPathComponent("BuildManifest.plist")
        )
    }

    static func isPresent(_ artifact: DeveloperImageArtifact) -> Bool {
        let url = directory.appendingPathComponent(artifact.localName)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return false
        }
        return size > 0
    }

    static func download(_ artifact: DeveloperImageArtifact) async throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        let (temporaryURL, response) = try await URLSession.shared.download(from: artifact.remoteURL)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw DeveloperImageError.badDownloadResponse(artifact.label)
        }

        let destination = directory.appendingPathComponent(artifact.localName)
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: temporaryURL, to: destination)
    }

    static func removeAll() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        try manager.removeItem(at: directory)
    }

    private static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeveloperImage", isDirectory: true)
    }
}

enum DeveloperImageError: LocalizedError {
    case badDownloadResponse(String)

    var errorDescription: String? {
        switch self {
        case .badDownloadResponse(let item):
            return "The \(item) download did not return a valid file."
        }
    }
}
