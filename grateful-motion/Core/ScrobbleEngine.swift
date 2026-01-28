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

	@Published var similarTracks: [SimilarTrack] = []
	@Published var similarArtists: [SimilarArtist] = []
	@Published var scrobbleCount: Int = 0

    @Published var lastArtworkURL: URL?

	private var artworkFetchTask: Task<Void, Never>?
	private var similarItemsFetchTask: Task<Void, Never>?
	
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

			Task {
				try? await lastFMClient.updateNowPlaying(track: processedTrack)

                artworkFetchTask?.cancel()
                artworkFetchTask = Task {
                    let maxRetries = 8
                    var retryCount = 0
                    var delay: TimeInterval = 0.5
                    let maxDelay: TimeInterval = 8

                    // TODO: Find the better way without wait 1.5s
                    try? await Task.sleep(nanoseconds: 1_500_000_000)

                    while retryCount < maxRetries && !Task.isCancelled {
                        if let artworkURL = try? await lastFMClient.fetchArtwork(
                            track: processedTrack,
                            username: lastFMClient.credentials.username
                        ) {
                            NSLog("ScrobbleEngine: Successfully fetched track artwork image: \(artworkURL)")
                            await MainActor.run {
                                self.currentTrack?.artworkURL = artworkURL
                                self.lastArtworkURL = artworkURL
                            }

                            return
                        }

                        retryCount += 1
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        delay = min(delay * 2, maxDelay)
                    }

                    NSLog("ScrobbleEngine: Artwork fetch gave up after \(retryCount) retries")
                }
			}

			Task {
				async let tracksTask = lastFMClient.getSimilarTracks(
					track: processedTrack,
					limit: 5
				)
				async let artistsTask = lastFMClient.getSimilarArtists(
					track: processedTrack,
					limit: 5
				)

				do {
					let (tracks, artists) = try await (tracksTask, artistsTask)
					Task { @MainActor in
						self.similarTracks = tracks
						self.similarArtists = artists
					}
				} catch {
					NSLog("ScrobbleEngine: Failed to fetch similar items: \(error)")
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
