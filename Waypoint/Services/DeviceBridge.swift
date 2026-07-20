import Darwin
import Foundation
import IDevice

final class DeviceBridge: @unchecked Sendable {
    static let localDevVPNAddress = "10.7.0.1"
    static let remotePairingPort: UInt16 = 49_152

    private let queue = DispatchQueue(label: "app.waypoint.device-bridge", qos: .userInitiated)

    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var remoteServer: OpaquePointer?
    private var locationClient: OpaquePointer?

    deinit {
        cleanupAll()
    }

    func connect(pairingFile: URL) async throws {
        try await perform {
            try self.connectSynchronously(pairingPath: pairingFile.path)
        }
    }

    func isDeveloperImageMounted() async throws -> Bool {
        try await perform {
            try self.requireTunnel()
            return try self.mountedImageCount() > 0
        }
    }

    func mountDeveloperImage(_ paths: DeveloperImagePaths) async throws {
        try await perform {
            try self.requireTunnel()
            if try self.mountedImageCount() > 0 { return }
            try self.mountDeveloperImageSynchronously(paths)
        }
    }

    func setLocation(_ coordinate: SelectedCoordinate) async throws {
        try await perform {
            guard coordinate.isValid else { throw DeviceBridgeError.invalidCoordinate }
            try self.requireTunnel()
            try self.ensureLocationClient()
            guard let locationClient = self.locationClient else {
                throw DeviceBridgeError.message("The location-simulation client was not created.")
            }
            do {
                try self.consume(
                    location_simulation_set(locationClient, coordinate.latitude, coordinate.longitude),
                    fallback: "The device rejected the simulated location."
                )
            } catch {
                self.cleanupAll()
                throw error
            }
        }
    }

    func clearLocation() async throws {
        try await perform {
            try self.requireTunnel()
            try self.ensureLocationClient()
            guard let locationClient = self.locationClient else {
                throw DeviceBridgeError.message("The location-simulation client was not created.")
            }

            do {
                try self.consume(
                    location_simulation_clear(locationClient),
                    fallback: "The device could not restore its real location."
                )
                self.cleanupLocationSession()
            } catch {
                self.cleanupAll()
                throw error
            }
        }
    }

    func disconnect() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.cleanupAll()
                continuation.resume()
            }
        }
    }

    /// Waits until every previously submitted bridge operation has finished.
    /// The cellular handoff uses this fence before changing network state so a
    /// periodic location write cannot collide with the transition.
    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume()
            }
        }
    }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result(catching: operation))
            }
        }
    }

    private func connectSynchronously(pairingPath: String) throws {
        cleanupAll()

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(Self.remotePairingPort).bigEndian

        let parsed = Self.localDevVPNAddress.withCString {
            inet_pton(AF_INET, $0, &address.sin_addr)
        }
        guard parsed == 1 else {
            throw DeviceBridgeError.message("The LocalDevVPN loopback address is invalid.")
        }

        var pairingHandle: OpaquePointer?
        try consume(
            pairingPath.withCString { rp_pairing_file_read($0, &pairingHandle) },
            fallback: "The pairing file could not be read. Import a fresh pairing record for this iPhone."
        )
        guard let pairingHandle else {
            throw DeviceBridgeError.message("The pairing file did not create a valid pairing record.")
        }
        defer { rp_pairing_file_free(pairingHandle) }

        let tunnelError = "Waypoint".withCString { hostName in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    tunnel_create_rppairing(
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.stride),
                        hostName,
                        pairingHandle,
                        nil,
                        nil,
                        &adapter,
                        &handshake
                    )
                }
            }
        }

        do {
            try consume(
                tunnelError,
                fallback: "Could not reach this iPhone through LocalDevVPN."
            )
            guard adapter != nil, handshake != nil else {
                throw DeviceBridgeError.message("The developer tunnel opened without valid connection handles.")
            }
        } catch {
            cleanupAll()
            throw error
        }
    }

    private func requireTunnel() throws {
        guard adapter != nil, handshake != nil else {
            throw DeviceBridgeError.message("Prepare the device before starting location simulation.")
        }
    }

    private func mountedImageCount() throws -> Int {
        guard let adapter, let handshake else {
            throw DeviceBridgeError.message("The developer tunnel is not connected.")
        }

        var mounter: OpaquePointer?
        try consume(
            image_mounter_connect_rsd(adapter, handshake, &mounter),
            fallback: "Could not connect to the developer image service."
        )
        guard let mounter else {
            throw DeviceBridgeError.message("The developer image service did not return a client.")
        }
        defer { image_mounter_free(mounter) }

        var devices: UnsafeMutablePointer<plist_t?>?
        var count = 0
        try consume(
            image_mounter_copy_devices(mounter, &devices, &count),
            fallback: "Could not check whether the developer image is mounted."
        )

        if let devices { idevice_plist_array_free(devices, UInt(count)) }
        return count
    }

    private func mountDeveloperImageSynchronously(_ paths: DeveloperImagePaths) throws {
        guard let adapter, let handshake else {
            throw DeviceBridgeError.message("The developer tunnel is not connected.")
        }

        let image = try mappedData(at: paths.image, label: "developer image")
        let trustCache = try mappedData(at: paths.trustCache, label: "trust cache")
        let manifest = try mappedData(at: paths.buildManifest, label: "build manifest")

        var lockdown: OpaquePointer?
        try consume(
            lockdownd_connect_rsd(adapter, handshake, &lockdown),
            fallback: "Could not connect to lockdownd."
        )
        guard let lockdown else {
            throw DeviceBridgeError.message("Lockdownd did not return a client.")
        }
        defer { lockdownd_client_free(lockdown) }

        var chipIDNode: plist_t?
        try consume(
            lockdownd_get_value(lockdown, "UniqueChipID", nil, &chipIDNode),
            fallback: "Could not read this iPhone's chip identifier."
        )
        guard let chipIDNode else {
            throw DeviceBridgeError.message("The chip identifier was missing from the device response.")
        }
        defer { plist_free(chipIDNode) }

        var uniqueChipID: UInt64 = 0
        plist_get_uint_val(chipIDNode, &uniqueChipID)
        guard uniqueChipID != 0 else {
            throw DeviceBridgeError.message("The chip identifier could not be decoded.")
        }

        var mounter: OpaquePointer?
        try consume(
            image_mounter_connect_rsd(adapter, handshake, &mounter),
            fallback: "Could not connect to the developer image service."
        )
        guard let mounter else {
            throw DeviceBridgeError.message("The developer image service did not return a client.")
        }
        defer { image_mounter_free(mounter) }

        let mountError: UnsafeMutablePointer<IdeviceFfiError>? = image.withUnsafeBytes { imageBytes in
            trustCache.withUnsafeBytes { trustBytes in
                manifest.withUnsafeBytes { manifestBytes in
                    image_mounter_mount_personalized_rsd(
                        mounter,
                        adapter,
                        handshake,
                        imageBytes.bindMemory(to: UInt8.self).baseAddress,
                        image.count,
                        trustBytes.bindMemory(to: UInt8.self).baseAddress,
                        trustCache.count,
                        manifestBytes.bindMemory(to: UInt8.self).baseAddress,
                        manifest.count,
                        nil,
                        uniqueChipID
                    )
                }
            }
        }
        try consume(mountError, fallback: "The personalized developer image could not be mounted.")
    }

    private func ensureLocationClient() throws {
        if locationClient != nil { return }
        guard let adapter, let handshake else {
            throw DeviceBridgeError.message("The developer tunnel is not connected.")
        }

        do {
            cleanupLocationSession()
            try consume(
                remote_server_connect_rsd(adapter, handshake, &remoteServer),
                fallback: "Could not connect to the DVT developer service."
            )
            guard let remoteServer else {
                throw DeviceBridgeError.message("The DVT developer service did not return a client.")
            }

            try consume(
                location_simulation_new(remoteServer, &locationClient),
                fallback: "The location-simulation service is unavailable. Check that the developer image is mounted."
            )
            guard locationClient != nil else {
                throw DeviceBridgeError.message("The location-simulation service did not return a client.")
            }
        } catch {
            cleanupAll()
            throw error
        }
    }

    private func mappedData(at url: URL, label: String) throws -> Data {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard !data.isEmpty else {
                throw DeviceBridgeError.message("The \(label) file is empty.")
            }
            return data
        } catch let error as DeviceBridgeError {
            throw error
        } catch {
            throw DeviceBridgeError.message("Could not read the \(label): \(error.localizedDescription)")
        }
    }

    private func consume(
        _ ffiError: UnsafeMutablePointer<IdeviceFfiError>?,
        fallback: String
    ) throws {
        guard let ffiError else { return }

        let code = Int(ffiError.pointee.code)
        let message = ffiError.pointee.message.flatMap(String.init(validatingUTF8:)) ?? fallback
        idevice_error_free(ffiError)
        throw DeviceBridgeError.ffi(code: code, message: message)
    }

    private func cleanupLocationSession() {
        if let locationClient {
            location_simulation_free(locationClient)
            self.locationClient = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
    }

    private func cleanupAll() {
        cleanupLocationSession()
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }
}

enum DeviceBridgeError: LocalizedError, Sendable {
    case invalidCoordinate
    case ffi(code: Int, message: String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "Choose a valid latitude and longitude."
        case .ffi(let code, let message):
            return "\(message) (idevice error \(code))"
        case .message(let message):
            return message
        }
    }
}
