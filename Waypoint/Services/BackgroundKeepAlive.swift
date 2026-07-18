import AVFoundation
import CoreLocation
import Foundation
import UIKit

@MainActor
final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundKeepAlive()

    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private var isAudioNodeAttached = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private(set) var isRunning = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 1_000
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func start() throws {
        guard !isRunning else { return }

        do {
            try startSilentAudio()
        } catch {
            stop()
            throw error
        }
        isRunning = true
        startLocationKeepAlive()

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Waypoint location session") { [weak self] in
            Task { @MainActor in
                guard let self, self.backgroundTask != .invalid else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        audioPlayer.stop()
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        isRunning = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRunning else { return }
        startLocationUpdatesIfAuthorized()
    }

    private func startLocationKeepAlive() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
            startLocationUpdatesIfAuthorized()
        case .authorizedAlways:
            startLocationUpdatesIfAuthorized()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func startLocationUpdatesIfAuthorized() {
        guard locationManager.authorizationStatus == .authorizedAlways
                || locationManager.authorizationStatus == .authorizedWhenInUse else {
            return
        }
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.startUpdatingLocation()
    }

    private func startSilentAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)
        guard let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000),
              let samples = buffer.floatChannelData?[0] else {
            throw BackgroundKeepAliveError.audioBufferCreationFailed
        }

        buffer.frameLength = buffer.frameCapacity
        samples.update(repeating: 0, count: Int(buffer.frameCapacity))

        if !isAudioNodeAttached {
            audioEngine.attach(audioPlayer)
            audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: format)
            isAudioNodeAttached = true
        }

        audioPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        audioEngine.prepare()
        try audioEngine.start()
        audioPlayer.play()
    }
}

enum BackgroundKeepAliveError: LocalizedError {
    case audioBufferCreationFailed

    var errorDescription: String? {
        "The background audio keepalive could not create its silent buffer."
    }
}
