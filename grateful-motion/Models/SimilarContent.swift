import Foundation

struct SimilarTrack: Identifiable, Codable {
	let id = UUID()
	let name: String
	let artist: String
	let match: Double
	let url: String?
}

struct SimilarArtist: Identifiable, Codable {
	let id = UUID()
	let name: String
	let match: Double
	let url: String?
}
