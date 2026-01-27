import Foundation

struct ScrobbleRecord: Codable, Identifiable {
	let id: UUID
	let track: Track
	let timestamp: Date
	let status: ScrobbleStatus

	enum ScrobbleStatus: String, Codable {
		case success
		case failed
		case queued
	}

	init(track: Track, timestamp: Date = Date(), status: ScrobbleStatus = .success) {
		self.id = UUID()
		self.track = track
		self.timestamp = timestamp
		self.status = status
	}
}
