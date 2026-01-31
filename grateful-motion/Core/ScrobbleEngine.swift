import Foundation
import Combine

class ScrobbleEngine: ObservableObject, @unchecked Sendable {
	@Published var currentTrack: Track?
    @Published var previousTrack: Track?

	@Published var currentPlaybackTime: TimeInterval = 0
	@Published var repeatMode: Track.RepeatMode = .off
	@Published var isScrobblingEnabled = true
    @Published var isPlaying = false
	@Published var sessionKey: String?
	@Published var recentScrobbles: [ScrobbleRecord] = []

	@Published var scrobbleCount: Int = 0

    @Published var lastArtworkURL: URL?

	private var artworkFetchTask: Task<Void, Never>?

	private var lastFMClient: LastFMClient
	private var scrobbleDatabase: ScrobbleDatabase
	let metadataProcessor: MetadataProcessor

	private var cancellables = Set<AnyCancellable>()
	@MainActor private var progressTimer: Timer?
	@MainActor private var scrobbleTimer: Timer?
	@MainActor private var lastPosition: TimeInterval = 0
	@MainActor private var consecutiveZeroPolls = 0

    private var replayHandled = false
    private var endHandled = false

	init(lastFMClient: LastFMClient, scrobbleDatabase: ScrobbleDatabase, metadataProcessor: MetadataProcessor) {
		self.lastFMClient = lastFMClient
		self.scrobbleDatabase = scrobbleDatabase
		self.metadataProcessor = metadataProcessor

		loadRecentScrobbles()
	}

	@MainActor
	func updateTrack(_ track: Track?) async {
        guard isScrobblingEnabled else { return }

		if let track = track {
			let processedTrack = metadataProcessor.process(track)
            previousTrack = currentTrack
			currentTrack = processedTrack
			lastPosition = 0
			currentPlaybackTime = 0
			consecutiveZeroPolls = 0

			NSLog("ScrobbleEngine: New track: \(processedTrack.title) - \(processedTrack.artist) with duration \(processedTrack.duration)")

			if let cachedTrack = recentScrobbles.first(where: { $0.track.isSameTrack(as: processedTrack) })?.track,
			   let tracks = cachedTrack.similarTracks, !tracks.isEmpty,
			   let artists = cachedTrack.similarArtists, !artists.isEmpty {
				NSLog("ScrobbleEngine: Using cached similar items for: \(processedTrack.title)")
				currentTrack?.similarTracks = tracks
				currentTrack?.similarArtists = artists
			}

			Task {
				try? await lastFMClient.updateNowPlaying(track: processedTrack)

                let immediateArtwork = try? await lastFMClient.fetchArtwork(
                    track: processedTrack,
                    username: lastFMClient.credentials.username,
                    allowFallback: true,
                    skipRecentTracks: true
                )

                if let artworkURL = immediateArtwork {
                    NSLog("ScrobbleEngine: Got immediate artwork from generic metadata: \(artworkURL)")
                    await MainActor.run {
                        self.currentTrack?.artworkURL = artworkURL
                        self.lastArtworkURL = artworkURL
                    }
                }

                let maxAttempts = 8
                for attempt in 1...maxAttempts {
                    let delay: UInt64 = switch attempt {
                        case 1, 2: 500_000_000
                        case 3, 4: 1_000_000_000
                        default: 2_000_000_000
                    }

                    try? await Task.sleep(nanoseconds: delay)

                    let recentTracksArtwork = try? await lastFMClient.fetchArtwork(
                        track: processedTrack,
                        username: lastFMClient.credentials.username,
                        allowFallback: false,
                        skipRecentTracks: false,
                        requireNewTrack: true
                    )

                    if let artworkURL = recentTracksArtwork {
                        NSLog("ScrobbleEngine: Found authoritative artwork on attempt \(attempt): \(artworkURL)")
                        await MainActor.run {
                            self.currentTrack?.artworkURL = artworkURL
                            self.lastArtworkURL = artworkURL
                        }

                        break
                    }

                    NSLog("ScrobbleEngine: Polling attempt \(attempt)/\(maxAttempts) - stale data or no artwork")
                }
            }

			startProgressTimer()
            scheduleScrobble(for: processedTrack)
		}
	}

	@MainActor
	private func startProgressTimer() {
		progressTimer?.invalidate()
		progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
			guard let self = self else { return }

            if let currentTrack = self.currentTrack {
				Task { @MainActor in
					let status = AppleMusicScriptBridge.shared.getPlayerStatus()

					guard status.position > 0 || status.isPlaying else {
						self.handleFailedPoll()
						return
					}

                    let isAtStart = status.position < 2
//                    let isAtEnd = status.position >= currentTrack.duration - 2

//                    if let previousTrack = self.previousTrack {
                        let replayDetected =
                            !self.replayHandled &&
//                            currentTrack.isSameTrack(as: previousTrack) &&
//                            self.lastPosition >= currentTrack.duration - 2 &&
                            isAtStart

                        if replayDetected {
                            NSLog("ScrobbleEngine: Replay detected, schedule new scrobble...")

                            self.replayHandled = true
//                            self.endHandled = false

                            let track = Track(
                                title: currentTrack.title,
                                artist: currentTrack.artist,
                                albumArtist: currentTrack.albumArtist,
                                album: currentTrack.album,
                                duration: currentTrack.duration,
                                playerState: .playing,
                                artworkURL: currentTrack.artworkURL
                            )

                            self.previousTrack = currentTrack
                            self.currentTrack = track

                            self.lastPosition = 0
                            self.currentPlaybackTime = 0

                            self.scheduleScrobble(for: currentTrack)

                            Task {
                                try? await self.lastFMClient.updateNowPlaying(track: currentTrack)
                            }
                        }
//                    }

                    if !isAtStart && self.replayHandled {
                        self.replayHandled = false
                    }

//                    if isAtEnd && !self.endHandled {
//                        let track = Track(
//                            title: currentTrack.title,
//                            artist: currentTrack.artist,
//                            albumArtist: currentTrack.albumArtist,
//                            album: currentTrack.album,
//                            duration: currentTrack.duration,
//                            playerState: .playing,
//                            artworkURL: currentTrack.artworkURL
//                        )
//
//                        self.replayHandled = false
//                        self.endHandled = true
//                        self.previousTrack = currentTrack
//                        self.currentTrack = track
//                    }

					let delta = max(status.position - self.lastPosition, 0)
					if delta == 0 {
						self.consecutiveZeroPolls += 1
						if self.consecutiveZeroPolls >= 10 {
							NSLog("ScrobbleEngine: Poll position unchanged for 5 seconds")
						}
					} else {
						self.consecutiveZeroPolls = 0
					}

					self.lastPosition = status.position
					self.currentPlaybackTime = status.position
				}
			}
		}
	}

	@MainActor
	private func handleFailedPoll() {
		consecutiveZeroPolls += 1
	}

	@MainActor
	public func stopProgressTimer() {
		progressTimer?.invalidate()
		progressTimer = nil
	}

	@MainActor
	private func scheduleScrobble(for track: Track) {
		scrobbleTimer?.invalidate()

        if track.duration < 30.0 {
            NSLog("ScrobbleEngine: Track duration is less than 30 seconds: \(track.duration)")
            return
        }

        let scrobbleDelay = min(240, track.duration / 2)
		let scrobbleDate = Date().addingTimeInterval(scrobbleDelay)

		NSLog("ScrobbleEngine: Scheduling scrobble in \(scrobbleDelay)s (min 240s or half duration)")

		scrobbleTimer = Timer(fire: scrobbleDate, interval: 0, repeats: false) { [weak self] _ in
			guard let self = self, let current = self.currentTrack else {
				return
			}

			Task {
				try? await self.lastFMClient.scrobble(track: current, timestamp: Date())

                let record = ScrobbleRecord(
                    track: current,
                    timestamp: Date(),
                    status: .success
                )

                self.scrobbleDatabase.saveScrobble(record)

                await MainActor.run {
                    self.scrobbleCount += 1
                    self.recentScrobbles.insert(record, at: 0)

                    if self.recentScrobbles.count > 10 {
                        self.recentScrobbles.removeLast()
                    }

                    NSLog("ScrobbleEngine: Scrobble saved, history updated (count: \(self.recentScrobbles.count))")
                }
            }
		}

		RunLoop.main.add(scrobbleTimer!, forMode: .common)
	}

    @MainActor
    public func stopSrobbleTimer() {
        scrobbleTimer?.invalidate()
        scrobbleTimer = nil
    }

	func toggleRepeatMode() {
		switch repeatMode {
		case .off:
			repeatMode = .one
		case .one:
			repeatMode = .all
		case .all:
			repeatMode = .off
		}

		NSLog("ScrobbleEngine: Repeat mode changed to: \(repeatMode)")
	}

	func loadRecentScrobbles() {
		Task {
			let scrobbles = scrobbleDatabase.fetchScrobbles(limit: 10)
			let totalCount = scrobbleDatabase.countScrobbles()
			await MainActor.run {
				self.recentScrobbles = scrobbles
				self.scrobbleCount = totalCount
			}
		}
	}

	func clearRecentScrobbles() {
		Task {
			await MainActor.run {
				self.recentScrobbles = []
				self.scrobbleCount = 0
			}
		}
	}
}
