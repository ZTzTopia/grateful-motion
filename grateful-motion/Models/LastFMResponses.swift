import Foundation

struct TrackInfoResponse: Codable {
	let track: LastFMTrack
}

struct MobileSessionResponse: Codable {
	let session: Session

	struct Session: Codable {
		let name: String
		let key: String
	}
}

struct LastFMTrack: Codable {
	let name: String
	let artist: LastFMArtist
	let album: LastFMAlbum?
}

struct LastFMArtist: Codable {
	let name: String
}

struct LastFMAlbum: Codable {
	let title: String
	let image: [LastFMImage]
}

struct LastFMImage: Codable {
	let urlString: String
	let size: String

	enum CodingKeys: String, CodingKey {
		case urlString = "#text"
		case size
	}

	var url: URL? { URL(string: urlString) }
}

struct RecentTracksResponse: Codable {
	let recenttracks: RecentTracksContainer
}

struct RecentTracksContainer: Codable {
	let track: [RecentTrack]
}

struct RecentTrackAttr: Codable {
	let nowplaying: String?
}

struct RecentTrack: Codable {
	let name: String
	let artist: RecentTrackArtist
	let album: RecentTrackAlbum?
	let image: [LastFMImage]
	let attr: RecentTrackAttr?

	enum CodingKeys: String, CodingKey {
		case name
		case artist
		case album
		case image
		case attr = "@attr"
	}
}

struct RecentTrackArtist: Codable {
	let name: String

	enum CodingKeys: String, CodingKey {
		case name = "#text"
	}
}

struct RecentTrackAlbum: Codable {
	let name: String

	enum CodingKeys: String, CodingKey {
		case name = "#text"
	}
}

struct SimilarTracksResponse: Codable {
	let similartracks: SimilarTracksContainer
}

struct SimilarTracksContainer: Codable {
	let track: [SimilarTrackItem]
}

struct SimilarTrackItem: Codable {
	let name: String
	let artist: SimilarTrackArtist
	let match: Double
	let url: String?
}

struct SimilarTrackArtist: Codable {
	let name: String
}

struct SimilarArtistsResponse: Codable {
	let similarartists: SimilarArtistsContainer
}

struct SimilarArtistsContainer: Codable {
	let artist: [SimilarArtistItem]
}

struct SimilarArtistItem: Codable {
	let name: String
	let match: String
	let url: String?
}
