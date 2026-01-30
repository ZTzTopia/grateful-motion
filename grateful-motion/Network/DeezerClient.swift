import Foundation

@MainActor
class DeezerClient {
 	static let shared = DeezerClient()
	private let session = URLSession.shared
	private let baseURL = "https://api.deezer.com"

	private init() {}

    func customPercentEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

	func searchTrack(artist: String?, album: String?, track: String) async throws -> [DeezerTrack] {
		var query = "?strict=on&q="

		if !track.isEmpty {
			query += "track:\"\(customPercentEncode(track))\" "
		}

		if let artist = artist, !artist.isEmpty {
			query += "artist:\"\(customPercentEncode(artist))\" "
		}

		if let album = album, !album.isEmpty {
			query += "album:\"\(customPercentEncode(album))\" "
		}

		let url = URL(string: "\(baseURL)/search/track\(query)")!
		return try await performRequest(url: url, responseType: DeezerSearchResponse<DeezerTrack>.self).data
	}

	func searchArtist(name: String) async throws -> [DeezerArtist] {
		let query = "?q=\(customPercentEncode(name))"
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
