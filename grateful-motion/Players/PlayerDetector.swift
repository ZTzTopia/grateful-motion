import Foundation
import Combine
import Cocoa

@MainActor
class PlayerDetector: ObservableObject {
	private let center = DistributedNotificationCenter.default()
	private var observers: [NSObjectProtocol] = []

	let scrobbleEngine: ScrobbleEngine
	@Published var isPlaying = false
	@Published var currentTrack: Track?

	private var lastPlayerState: String?
	private var timer: Timer?

	init(scrobbleEngine: ScrobbleEngine) {
		self.scrobbleEngine = scrobbleEngine
	}

	func start() {
		startAppleMusicDetector()
	}

	func stop() {
		stopTimer()
		observers.forEach { center.removeObserver($0) }
		observers.removeAll()
	}

	private func startAppleMusicDetector() {
		let observer = center.addObserver(
			forName: NSNotification.Name("com.apple.Music.playerInfo"),
			object: nil,
			queue: nil
		) { [weak self] notification in
			guard let userInfo = notification.userInfo, let playerState = userInfo["Player State"] as? String else {
				return
			}

            NSLog("PlayerDetector: User info: \(userInfo)")

			let title = userInfo["Name"] as? String
			let artist = userInfo["Artist"] as? String
			let album = userInfo["Album"] as? String
			let albumArtist = userInfo["Album Artist"] as? String
			let totalTime = userInfo["Total Time"] as? Int

			Task { @MainActor in
				self?.processAppleMusicState(
					playerState: playerState,
					title: title,
					artist: artist,
					album: album,
					albumArtist: albumArtist,
					totalTime: totalTime
				)
			}
		}

		observers.append(observer)
		startTimer()
	}

	private func startTimer() {
		timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.checkAppleMusicStatus()
			}
		}
	}

	private func stopTimer() {
		timer?.invalidate()
		timer = nil
	}

	private func checkAppleMusicStatus() {
		NotificationCenter.default.post(name: .checkAppleMusicStatus, object: nil)
	}

	private func processAppleMusicState(
		playerState: String,
		title: String?,
		artist: String?,
		album: String?,
		albumArtist: String?,
		totalTime: Int?
	) {
		lastPlayerState = playerState

		let state: Track.PlayerState = playerState == "Playing" ? .playing : .paused
		if state == .playing {
			guard let title, let artist else { return }

			let duration: TimeInterval = {
				guard let totalTime else { return 0 }
				return TimeInterval(totalTime) / 1000.0
			}()

			let track = Track(
				title: title,
				artist: artist,
				albumArtist: albumArtist,
				album: album,
				duration: duration,
				playerState: .playing
			)

			if self.currentTrack == nil || !self.isPlaying || self.currentTrack?.isSameTrack(as: track) == false {
				self.isPlaying = true
				self.scrobbleEngine.isPlaying = true
				self.currentTrack = track
				Task {
					await self.scrobbleEngine.updateTrack(track)
				}
			}

			return
		}

        NSLog("PlayerDetector: Apple Music is not paused or stopped")

		self.isPlaying = false
		self.scrobbleEngine.isPlaying = false
		self.scrobbleEngine.stopProgressTimer()
		self.scrobbleEngine.stopSrobbleTimer()
	}
}

extension Notification.Name {
	static let checkAppleMusicStatus = Notification.Name("checkAppleMusicStatus")
}
