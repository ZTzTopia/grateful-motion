import Foundation

struct Track: Codable, Identifiable {
	let id: UUID
	var title: String
	var artist: String
	var albumArtist: String?
	var album: String?
	var duration: TimeInterval
	let playerState: PlayerState
	var repeatMode: RepeatMode = .off
	var lastPlayedAt: Date
	var artworkURL: URL?

	enum PlayerState: String, Codable {
		case playing
		case paused
		case stopped
	}

	enum RepeatMode: String, Codable {
		case off
		case one
		case all
	}

	init(
        title: String,
        artist: String,
        albumArtist: String? = nil,
        album: String? = nil,
        duration: TimeInterval,
        playerState: PlayerState = .playing,
        artworkURL: URL? = nil
    ) {
		self.id = UUID()
		self.title = title
		self.artist = artist
		self.albumArtist = albumArtist
		self.album = album
		self.duration = duration
		self.playerState = playerState
		self.lastPlayedAt = Date()
        self.artworkURL = artworkURL
	}
}

extension Track {
	func displayName() -> String {
		"\(artist) - \(title)"
	}

	func formattedDuration(_ time: TimeInterval) -> String {
		let minutes = Int(time / 60)
		let seconds = Int(time.truncatingRemainder(dividingBy: 60))
		return String(format: "%d:%02d", minutes, seconds)
	}

    // TODO: Move it to utils
    func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "’", with: "'")
    }

	func isSameTrack(as other: Track?) -> Bool {
		guard let other = other else { return false }

        let titleMatch = normalize(title) == normalize(other.title)
        let artistMatch = normalize(artist) == normalize(other.artist)
        // Should we compare the album too? or this is bad detection?

		if duration == 0 || other.duration == 0 {
			return titleMatch && artistMatch
		}

        let durationMatch = abs(duration - other.duration) < 2
		return titleMatch && artistMatch && durationMatch
	}
}
