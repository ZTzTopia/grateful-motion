import Foundation
import SQLite3

class ScrobbleDatabase {
	private var db: OpaquePointer?
	private let dbPath: String

	init() {
		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let appDir = appSupportURL.appendingPathComponent("grateful-motion", isDirectory: true)

		try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

		dbPath = appDir.appendingPathComponent("scrobbles.db").path

		openDatabase()
		createTables()
	}

	private func openDatabase() {
		sqlite3_open(dbPath, &db)
	}

	private func createTables() {
		let createScrobblesTable = """
		CREATE TABLE IF NOT EXISTS scrobbles (
			id TEXT PRIMARY KEY,
			title TEXT NOT NULL,
			artist TEXT NOT NULL,
			album TEXT,
			albumArtist TEXT,
			duration REAL,
			timestamp REAL NOT NULL,
			status TEXT NOT NULL,
			artworkURL TEXT
		);
		"""

		sqlite3_exec(db, createScrobblesTable, nil, nil, nil)
	}

	func saveScrobble(_ record: ScrobbleRecord) {
		let insertSQL = """
		INSERT OR REPLACE INTO scrobbles (id, title, artist, album, albumArtist, duration, timestamp, status, artworkURL)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
		"""

		var statement: OpaquePointer?
		if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
			sqlite3_bind_text(statement, 1, (record.id.uuidString as NSString).utf8String, -1, nil)
			sqlite3_bind_text(statement, 2, (record.track.title as NSString).utf8String, -1, nil)
			sqlite3_bind_text(statement, 3, (record.track.artist as NSString).utf8String, -1, nil)
			sqlite3_bind_text(statement, 4, (record.track.album as NSString?)?.utf8String, -1, nil)
			sqlite3_bind_text(statement, 5, (record.track.albumArtist as NSString?)?.utf8String, -1, nil)
			sqlite3_bind_double(statement, 6, record.track.duration)
			sqlite3_bind_double(statement, 7, record.timestamp.timeIntervalSince1970)
			sqlite3_bind_text(statement, 8, (record.status.rawValue as NSString).utf8String, -1, nil)
			sqlite3_bind_text(statement, 9, (record.track.artworkURL?.absoluteString as NSString?)?.utf8String, -1, nil)

			sqlite3_step(statement)
		}

		sqlite3_finalize(statement)
	}

	func saveScrobbles(_ records: [ScrobbleRecord]) {
		for record in records {
			saveScrobble(record)
		}
	}

	func fetchScrobbles(limit: Int = 100) -> [ScrobbleRecord] {
		var records: [ScrobbleRecord] = []

		let querySQL = """
		SELECT id, title, artist, album, albumArtist, duration, timestamp, status, artworkURL
		FROM scrobbles
		ORDER BY timestamp DESC
		LIMIT ?;
		"""

		var statement: OpaquePointer?
		if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
			sqlite3_bind_int(statement, 1, Int32(limit))

			while sqlite3_step(statement) == SQLITE_ROW {
				let id = String(cString: sqlite3_column_text(statement, 0))
				let title = String(cString: sqlite3_column_text(statement, 1))
				let artist = String(cString: sqlite3_column_text(statement, 2))
				let album = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : nil
				let albumArtist = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
				let duration = sqlite3_column_double(statement, 5)
				let timestamp = sqlite3_column_double(statement, 6)
				let status = String(cString: sqlite3_column_text(statement, 7))
				let artworkURLString = sqlite3_column_text(statement, 8) != nil ? String(cString: sqlite3_column_text(statement, 8)) : nil

				var track = Track(
                    // id: id
					title: title,
					artist: artist,
					albumArtist: albumArtist,
					album: album,
					duration: duration,
					playerState: .stopped,
                    artworkURL: artworkURLString != nil ? URL(string: artworkURLString!) : nil
				)

				let record = ScrobbleRecord(
					track: track,
					timestamp: Date(timeIntervalSince1970: timestamp),
					status: ScrobbleRecord.ScrobbleStatus(rawValue: status) ?? .success
				)

				records.append(record)
			}
		}

		sqlite3_finalize(statement)
		return records
	}

	deinit {
		sqlite3_close(db)
	}
}

struct LogEntry: Identifiable {
	let id = UUID()
	let type: String
	let message: String
	let timestamp: Date
	let extraData: String?
}
