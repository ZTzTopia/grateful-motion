import Foundation
import Combine
import CommonCrypto

@MainActor
class LastFMClient: ObservableObject {
	private let apiKey = Secrets.lastFMAPIKey
	private let apiSecret = Secrets.lastFMAPISecret
	private let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!

	private let session: URLSession

	private var lastConfirmedSignature: String?

	var hasConfirmedSignature: Bool {
		lastConfirmedSignature != nil
	}

	private static let encryptionKey: [UInt8] = [
		0x2a, 0x7e, 0x4f, 0x9c, 0x1b, 0x6d, 0x8a, 0x3e,
		0x5c, 0x2f, 0x9d, 0x7a, 0x1e, 0x4b, 0x8c, 0x3f,
		0x6d, 0x2a, 0x7e, 0x4f, 0x9c, 0x1b, 0x6d, 0x8a,
		0x3e, 0x5c, 0x2f, 0x9d, 0x7a, 0x1e, 0x4b, 0x8c
	]
	private static let iv: [UInt8] = [
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
		0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
	]

	struct LastFMCredentials: Codable {
		var sessionKey: String?
		var username: String?
	}

	@Published var credentials: LastFMCredentials {
		didSet {
			saveCredentials()
		}
	}

	init() {
		self.session = URLSession.shared
		self.credentials = Self.loadCredentials()
	}

	private static func encrypt(_ data: Data) throws -> Data {
		let keyData = Data(encryptionKey)
		let ivData = Data(iv)

		let bufferSize = data.count + kCCBlockSizeAES128
		var buffer = [UInt8](repeating: 0, count: bufferSize)
		var numBytesEncrypted: size_t = 0

		let cryptStatus = buffer.withUnsafeMutableBytes { outputBytes in
			data.withUnsafeBytes { dataBytes in
				keyData.withUnsafeBytes { keyBytes in
					ivData.withUnsafeBytes { ivBytes in
						CCCrypt(
							CCOperation(kCCEncrypt),
							CCAlgorithm(kCCAlgorithmAES),
							CCOptions(kCCOptionPKCS7Padding),
							keyBytes.baseAddress, kCCKeySizeAES256,
							ivBytes.baseAddress,
							dataBytes.baseAddress, data.count,
							outputBytes.baseAddress, bufferSize,
							&numBytesEncrypted
						)
					}
				}
			}
		}

		guard cryptStatus == kCCSuccess else {
			throw NSError(domain: "LastFMClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encryption failed"])
		}

		let encryptedData = Data(bytes: buffer, count: numBytesEncrypted)
		return ivData + encryptedData
	}

	private static func decrypt(_ data: Data) throws -> Data {
		guard data.count >= kCCBlockSizeAES128 else {
			throw NSError(domain: "LastFMClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid encrypted data"])
		}

		let keyData = Data(encryptionKey)
		let ivData = data.prefix(kCCBlockSizeAES128)
		let encryptedData = data.suffix(from: kCCBlockSizeAES128)

		let bufferSize = encryptedData.count + kCCBlockSizeAES128
		var buffer = [UInt8](repeating: 0, count: bufferSize)
		var numBytesDecrypted: size_t = 0

		let cryptStatus = buffer.withUnsafeMutableBytes { outputBytes in
			encryptedData.withUnsafeBytes { encryptedBytes in
				keyData.withUnsafeBytes { keyBytes in
					ivData.withUnsafeBytes { ivBytes in
						CCCrypt(
							CCOperation(kCCDecrypt),
							CCAlgorithm(kCCAlgorithmAES),
							CCOptions(kCCOptionPKCS7Padding),
							keyBytes.baseAddress, kCCKeySizeAES256,
							ivBytes.baseAddress,
							encryptedBytes.baseAddress, encryptedData.count,
							outputBytes.baseAddress, bufferSize,
							&numBytesDecrypted
						)
					}
				}
			}
		}

		guard cryptStatus == kCCSuccess else {
			throw NSError(domain: "LastFMClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Decryption failed"])
		}

		return Data(bytes: buffer, count: numBytesDecrypted)
	}

	private static func loadCredentials() -> LastFMCredentials {
		if let encryptedData = UserDefaults.standard.data(forKey: "lastfm_credentials") {
			do {
				let decryptedData = try decrypt(encryptedData)
				if let creds = try? JSONDecoder().decode(LastFMCredentials.self, from: decryptedData) {
					return creds
				}
			} catch {
				NSLog("LastFMClient: Failed to decrypt credentials, returning empty credentials")
			}
		}
		return LastFMCredentials(sessionKey: nil, username: nil)
	}

	private func saveCredentials() {
		guard let data = try? JSONEncoder().encode(credentials) else { return }
		do {
			let encryptedData = try Self.encrypt(data)
			UserDefaults.standard.set(encryptedData, forKey: "lastfm_credentials")
		} catch {
			NSLog("LastFMClient: Failed to encrypt credentials")
		}
	}

	func logout() {
		credentials = LastFMCredentials(sessionKey: nil, username: nil)
	}

	func generateSignature(params: [String: String]) -> String {
		let sortedParams = params.keys.sorted().map { "\($0)\(params[$0]!)" }.joined()
		let signatureSource = sortedParams + apiSecret

		let data = signatureSource.data(using: .utf8)!
		var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))

		_ = data.withUnsafeBytes { (body: UnsafeRawBufferPointer) in
			CC_MD5(body.baseAddress, CC_LONG(data.count), &digest)
		}

		return digest.map { String(format: "%02x", $0) }.joined()
	}

	func updateNowPlaying(track: Track) async throws {
		guard let sessionKey = credentials.sessionKey else { return }

		var params = [
			"method": "track.updateNowPlaying",
			"artist": track.artist,
			"track": track.title,
			"api_key": apiKey,
			"sk": sessionKey
		]

		if let album = track.album {
			params["album"] = album
		}

		if track.duration > 0 {
			params["duration"] = String(Int(track.duration))
		}

		params["api_sig"] = generateSignature(params: params)
		params["format"] = "json"

		_ = try await performRequest(params: params)
	}

	func scrobble(track: Track, timestamp: Date) async throws {
		guard let sessionKey = credentials.sessionKey else { return }

		var params = [
			"method": "track.scrobble",
			"artist": track.artist,
			"track": track.title,
			"timestamp": String(Int(timestamp.timeIntervalSince1970)),
			"api_key": apiKey,
			"sk": sessionKey
		]

		if let album = track.album {
			params["album"] = album
		}

		params["api_sig"] = generateSignature(params: params)
		params["format"] = "json"

		_ = try await performRequest(params: params)
	}

	func love(track: Track) async throws {
		guard let sessionKey = credentials.sessionKey else { return }

		let params = [
			"method": "track.love",
			"artist": track.artist,
			"track": track.title,
			"api_key": apiKey,
			"sk": sessionKey,
			"api_sig": generateSignature(params: [
				"method": "track.love",
				"artist": track.artist,
				"track": track.title,
				"api_key": apiKey,
				"sk": sessionKey
			]),
			"format": "json"
		]

		_ = try await performRequest(params: params)
	}

	struct ArtworkInfo {
		let small: URL?
		let medium: URL?
		let large: URL?
		let extralarge: URL?
	}

	func getTrackInfo(track: Track) async throws -> ArtworkInfo {
		let params = [
			"method": "track.getInfo",
			"artist": track.artist,
			"track": track.title,
			"api_key": apiKey,
			"format": "json"
		]

		let data = try await performRequest(params: params)
		let response = try JSONDecoder().decode(TrackInfoResponse.self, from: data)

		let images = response.track.album?.image ?? []
		return ArtworkInfo(
			small: images.first(where: { $0.size == "small" })?.url,
			medium: images.first(where: { $0.size == "medium" })?.url,
			large: images.first(where: { $0.size == "large" })?.url,
			extralarge: images.first(where: { $0.size == "extralarge" })?.url
		)
	}

	func getRecentTracks(username: String, limit: Int = 1) async throws -> [RecentTrack] {
		let params = [
			"method": "user.getRecentTracks",
			"user": username,
			"limit": String(limit),
			"api_key": apiKey,
			"format": "json"
		]

		let data = try await performRequest(params: params)
		let response = try JSONDecoder().decode(RecentTracksResponse.self, from: data)

		return response.recenttracks.track
	}

	private func isImageEmpty(_ images: [LastFMImage]) -> Bool {
		return images.isEmpty ||
		       images.allSatisfy { $0.urlString.isEmpty } ||
		       images.allSatisfy { $0.urlString.contains("2a96cbd8b46e442fc41c2b86b821562f") }
	}

	func fetchArtwork(track: Track, username: String?, allowFallback: Bool = true, skipRecentTracks: Bool = false, requireNewTrack: Bool = false) async throws -> URL? {
        NSLog("LastFMClient: Fetching artwork for track: \(track.title) by \(track.artist) (allowFallback: \(allowFallback), skipRecentTracks: \(skipRecentTracks), requireNewTrack: \(requireNewTrack))")

		let username = username ?? credentials.username

		if !skipRecentTracks, let username = username, !username.isEmpty {
			do {
				let recentTracks = try await getRecentTracks(username: username, limit: 1)
                if let firstTrack = recentTracks.first, !isImageEmpty(firstTrack.image), firstTrack.attr?.nowplaying == "true" {
                    let currentSignature = "\(firstTrack.artist.name)|\(firstTrack.name)|\(firstTrack.album?.name)"

					if requireNewTrack, let lastSig = lastConfirmedSignature, lastSig == currentSignature {
						NSLog("LastFMClient: Stale data detected. Last.fm still reports '\(currentSignature)'")
						return nil
					}

					lastConfirmedSignature = currentSignature
					NSLog("LastFMClient: Confirmed new track signature: '\(currentSignature)'")

					return firstTrack.image.first(where: { $0.size == "large" })?.url ??
					       firstTrack.image.first(where: { $0.size == "medium" })?.url ??
					       firstTrack.image.first(where: { $0.size == "small" })?.url
				}
			} catch {
                NSLog("LastFMClient: Failed to fetch recent tracks for artwork: \(error.localizedDescription)")
			}
		}

        guard allowFallback else { return nil }

        // FIXME: Change to album.getInfo instead if the recents is empty,
        // if album empty then get the artist. Or maybe we should use this too
        // but request it at last order?
		do {
			let artworkInfo = try await getTrackInfo(track: track)
			if let url = artworkInfo.large ?? artworkInfo.medium ?? artworkInfo.small {
				return url
			}
		} catch {
            NSLog("LastFMClient: Failed to fetch track info for artwork: \(error.localizedDescription)")
		}

		let deezerClient = DeezerClient.shared

		do {
			let deezerTracks = try await deezerClient.searchTrack(
				artist: track.artist,
				album: track.album,
				track: track.title
			)

			if let topTrack = deezerTracks.first {
				if let album = topTrack.album, !album.cover_big.isEmpty {
					return URL(string: album.cover_big)
				}

				if let artist = topTrack.artist, !artist.picture_big.isEmpty {
					return URL(string: artist.picture_big)
				}
			}
		} catch {
            NSLog("LastFMClient: Failed to search Deezer for track: \(error.localizedDescription)")
		}

		do {
			let artists = try await deezerClient.searchArtist(name: track.artist)

			if let topArtist = artists.first, !topArtist.picture_big.isEmpty {
				return URL(string: topArtist.picture_big)
			}
		} catch {
            NSLog("LastFMClient: Failed to search Deezer for artist: \(error.localizedDescription)")
		}

		NSLog("LastFMClient: No artwork found for track: \(track.title) by \(track.artist)")
		return nil
	}

	func getSimilarTracks(track: Track, limit: Int = 5) async throws -> [SimilarTrack] {
		let params = [
			"method": "track.getSimilar",
			"artist": track.artist,
			"track": track.title,
			"limit": String(limit),
			"api_key": apiKey,
			"format": "json"
		]

		let data = try await performRequest(params: params)

		let response = try JSONDecoder().decode(SimilarTracksResponse.self, from: data)

		return response.similartracks.track.map { item in
			SimilarTrack(
				name: item.name,
				artist: item.artist.name,
				match: item.match,
				url: item.url
			)
		}
	}

	func getSimilarArtists(track: Track, limit: Int = 5) async throws -> [SimilarArtist] {
		let params = [
			"method": "artist.getSimilar",
			"artist": track.artist,
			"limit": String(limit),
			"api_key": apiKey,
			"format": "json"
		]

		let data = try await performRequest(params: params)

		let response = try JSONDecoder().decode(SimilarArtistsResponse.self, from: data)

		return response.similarartists.artist.map { item in
			SimilarArtist(
				name: item.name,
				match: Double(item.match) ?? 0.0,
				url: item.url
			)
		}
	}

	func getMobileSession(username: String, password: String) async throws -> (sessionKey: String, username: String) {
		var params = [
			"method": "auth.getMobileSession",
			"api_key": apiKey,
			"username": username,
			"password": password
		]

		params["api_sig"] = generateSignature(params: params)
		params["format"] = "json"

		let data = try await performRequest(params: params)
		let response = try JSONDecoder().decode(MobileSessionResponse.self, from: data)

		return (response.session.key, response.session.name)
	}

	private func performRequest(params: [String: String]) async throws -> Data {
		var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
		components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

		var request = URLRequest(url: components.url!)
		request.httpMethod = "POST"

		let urlString = components.url?.absoluteString ?? "unknown"
//		NSLog("LastFMClient: Request URL: \(urlString)")
        NSLog("LastFMClient: Request URL: %@", urlString)
		NSLog("LastFMClient: Request method: \(request.httpMethod ?? "unknown")")
		NSLog("LastFMClient: Request params: \(params)")

		let (data, response) = try await session.data(for: request)

		NSLog("LastFMClient: Response status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
		if let jsonString = String(data: data, encoding: .utf8) {
			NSLog("LastFMClient: Response body: \(jsonString)")
		}

		guard let httpResponse = response as? HTTPURLResponse,
			  (200...299).contains(httpResponse.statusCode) else {
			throw NSError(domain: "LastFMClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request failed"])
		}

		return data
	}
}

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

struct SimilarTrack: Identifiable {
	let id = UUID()
	let name: String
	let artist: String
	let match: Double
	let url: String?
}

struct SimilarArtist: Identifiable {
	let id = UUID()
	let name: String
	let match: Double
	let url: String?
}
