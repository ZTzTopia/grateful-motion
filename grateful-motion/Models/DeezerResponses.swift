import Foundation

struct DeezerSearchResponse<T: Decodable>: Decodable {
	let data: [T]
	let total: Int
}

struct DeezerTrack: Decodable {
	let album: DeezerAlbum?
	let artist: DeezerArtist?
	let title: String
}

struct DeezerAlbum: Decodable {
	let cover: String
	let cover_small: String
	let cover_medium: String
	let cover_big: String
	let cover_xl: String
	let title: String
}

struct DeezerArtist: Decodable {
	let picture: String
	let picture_small: String
	let picture_medium: String
	let picture_big: String
	let picture_xl: String
	let name: String
}
