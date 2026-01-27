import Foundation

@MainActor
class DeezerClient {
 	static let shared = DeezerClient()
	private let session = URLSession.shared
	private let baseURL = "https://api.deezer.com"

	private init() {}

	func searchTrack(artist: String?, album: String?, track: String) async throws -> [DeezerTrack] {
		var query = "?strict=on&q="

		if !track.isEmpty {
			query += "track:\"\(track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track)\" "
		}

		if let artist = artist, !artist.isEmpty {
			query += "artist:\"\(artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? artist)\" "
		}

		if let album = album, !album.isEmpty {
			query += "album:\"\(album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? album)\" "
		}

		let url = URL(string: "\(baseURL)/search/track\(query)")!
		return try await performRequest(url: url, responseType: DeezerSearchResponse<DeezerTrack>.self).data
	}

	func searchArtist(name: String) async throws -> [DeezerArtist] {
		let query = "?q=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
		let url = URL(string: "\(baseURL)/search/artist\(query)")!
		return try await performRequest(url: url, responseType: DeezerSearchResponse<DeezerArtist>.self).data
	}

	private func performRequest<T: Decodable>(url: URL, responseType: T.Type) async throws -> T {
		let (data, response) = try await session.data(from: url)
		guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
			NSLog("DeezerClient: Request failed for URL: \(url)")
			throw NSError(domain: "DeezerClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request failed"])
		}

		do {
			return try JSONDecoder().decode(T.self, from: data)
		} catch {
            NSLog("DeezerClient: Failed to decode response: \(error.localizedDescription)")
			throw error
		}
	}
}

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
