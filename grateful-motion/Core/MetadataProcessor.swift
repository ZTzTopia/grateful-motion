import Foundation
import Combine

struct ReplacementRule: Codable, Identifiable {
	let id: UUID
	var pattern: String
	var replacement: String
	var enabled: Bool
	var targetFields: [String]
	var useCase: RuleUseCase

	enum RuleUseCase: String, Codable {
		case display
		case scrobble
		case both
	}

	init(pattern: String, replacement: String, enabled: Bool = true, targetFields: [String] = ["title", "artist"], useCase: RuleUseCase = .both) {
		self.id = UUID()
		self.pattern = pattern
		self.replacement = replacement
		self.enabled = enabled
		self.targetFields = targetFields
		self.useCase = useCase
	}
}

struct FilterRule: Codable, Identifiable {
	let id: UUID
	var pattern: String
	var enabled: Bool
	var matchType: MatchType
	var logic: FilterLogic

	enum MatchType: String, Codable {
		case regex
		case exact
		case contains
	}

	enum FilterLogic: String, Codable {
		case include
		case exclude
		case includeAny
		case excludeAny
		case all
		case none
	}

	init(pattern: String, enabled: Bool = true, matchType: MatchType = .regex, logic: FilterLogic = .exclude) {
		self.id = UUID()
		self.pattern = pattern
		self.enabled = enabled
		self.matchType = matchType
		self.logic = logic
	}
}

class MetadataProcessor: ObservableObject {
	@Published var replacementRules: [ReplacementRule] = []
	@Published var filterRules: [FilterRule] = []

	init() {
		loadDefaultRules()
	}

	func process(_ track: Track) -> Track {
		var processed = track

		if !matchesFilters(processed) {
			return processed
		}

		processed = applyReplacements(processed)
		processed = applyArtistSplitting(processed)

		return processed
	}

	private func matchesFilters(_ track: Track) -> Bool {
		guard !filterRules.isEmpty else { return true }

		let activeRules = filterRules.filter { $0.enabled }
		guard !activeRules.isEmpty else { return true }

		for rule in activeRules {
			let matches = checkFilterRule(rule, track: track)

			switch rule.logic {
			case .exclude:
				if matches { return false }
			case .include:
				if !matches { return false }
			case .includeAny:
				if matches { return true }
			case .excludeAny:
				if matches { return false }
			case .all:
				if !matches { return false }
			case .none:
				if matches { return false }
			}
		}

		return true
	}

	private func checkFilterRule(_ rule: FilterRule, track: Track) -> Bool {
		let text = "\(track.artist) - \(track.title)"

		switch rule.matchType {
		case .regex:
			let regex = try? NSRegularExpression(pattern: rule.pattern)
			let range = NSRange(text.startIndex..., in: text)
			return regex?.firstMatch(in: text, range: range) != nil
		case .exact:
			return text == rule.pattern
		case .contains:
			return text.contains(rule.pattern)
		}
	}

	private func applyReplacements(_ track: Track) -> Track {
		var processed = track
		let activeRules = replacementRules.filter { $0.enabled }

		for rule in activeRules {
			for field in rule.targetFields {
				switch field {
				case "title":
					processed.title = applyRule(rule, to: processed.title)
				case "artist":
					processed.artist = applyRule(rule, to: processed.artist)
				case "album":
					if let album = processed.album {
						processed = Track(
							title: processed.title,
							artist: processed.artist,
							albumArtist: processed.albumArtist,
							album: applyRule(rule, to: album),
							duration: processed.duration,
							playerState: processed.playerState
						)
					}
				default:
					break
				}
			}
		}

		return processed
	}

	private func applyRule(_ rule: ReplacementRule, to text: String) -> String {
		guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return text }

		let range = NSRange(text.startIndex..., in: text)
		let template = expandReplacementTemplate(rule.replacement)

		return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
	}

	private func expandReplacementTemplate(_ template: String) -> String {
		return template
			.replacingOccurrences(of: "$N", with: "")
			.replacingOccurrences(of: "$$N", with: "")
	}

	private func applyArtistSplitting(_ track: Track) -> Track {
		let normalizedArtist = normalizeArtistSeparators(track.artist)

		let artistComponents = normalizedArtist.components(separatedBy: ", ")
		guard artistComponents.count > 1 else { return track }

		let primaryArtist = artistComponents[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

		return Track(
			title: track.title,
			artist: primaryArtist,
			albumArtist: track.albumArtist ?? track.artist,
			album: track.album,
			duration: track.duration,
			playerState: track.playerState
		)
	}

	private func normalizeArtistSeparators(_ artist: String) -> String {
		var result = artist

		result = result.replacingOccurrences(of: "&", with: ", ")
		result = result.replacingOccurrences(of: " / ", with: ", ")

		let andPattern = "(?i)\\band\\b"
		if let regex = try? NSRegularExpression(pattern: andPattern) {
			let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
			for match in matches.reversed() {
				if let range = Range(match.range, in: result) {
					result = result.replacingCharacters(in: range, with: ", ")
				}
			}
		}

		let aPattern = "(?i)\\ba\\b"
		if let regex = try? NSRegularExpression(pattern: aPattern) {
			let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
			for match in matches.reversed() {
				if let range = Range(match.range, in: result) {
					if shouldSplitOnA(result, range: range) {
						result = result.replacingCharacters(in: range, with: ", ")
					}
				}
			}
		}

		while result.contains(", ,") {
			result = result.replacingOccurrences(of: ", ,", with: ", ")
		}
		while result.contains(" ,") {
			result = result.replacingOccurrences(of: " ,", with: ", ")
		}

		return result.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
	}

	private func shouldSplitOnA(_ text: String, range: Range<String.Index>) -> Bool {
		let words = text.components(separatedBy: .whitespaces)
		let rangeStart = text.distance(from: text.startIndex, to: range.lowerBound)
		let rangeEnd = text.distance(from: text.startIndex, to: range.upperBound)

		var currentIndex = 0
		var wordIndex = 0

		for word in words {
			let wordStart = currentIndex
			let wordEnd = currentIndex + word.count
			currentIndex = wordEnd + 1

			if rangeStart >= wordStart && rangeEnd <= wordEnd {
				break
			}
			wordIndex += 1
		}

		if wordIndex == 0 || wordIndex >= words.count - 1 {
			return false
		}

		let beforeWord = words[wordIndex - 1].lowercased()
		let afterWord = words[wordIndex + 1].lowercased()

		let skipBefore = ["the", "a", "an", "in", "on", "at", "for", "to", "with", "from", "by", "as", "of", "this", "that"]
		let skipAfter = ["the", "a", "an", "one", "few", "little", "lot", "bit", "great", "good", "bad", "new", "old"]

		if skipBefore.contains(beforeWord) || skipAfter.contains(afterWord) {
			return false
		}

		return true
	}

	func loadDefaultRules() {
		replacementRules = [
			ReplacementRule(
				pattern: "\\s*([—–])\\s*Radio\\s*$",
				replacement: "",
				enabled: true,
				targetFields: ["title"],
				useCase: .both
			),
			ReplacementRule(
				pattern: "\\s*([—–])\\s*电台\\s*$",
				replacement: "",
				enabled: true,
				targetFields: ["title"],
				useCase: .both
			),
			ReplacementRule(
				pattern: "\\s*([—–])\\s*ラジオ\\s*$",
				replacement: "",
				enabled: true,
				targetFields: ["title"],
				useCase: .both
			),
			ReplacementRule(
				pattern: "\\s*([—–])\\s*Radio\\s*$",
				replacement: "",
				enabled: true,
				targetFields: ["album"],
				useCase: .both
			),
			ReplacementRule(
				pattern: "\\s*([—–])\\s*电台\\s*$",
				replacement: "",
				enabled: true,
				targetFields: ["album"],
				useCase: .both
			),
			ReplacementRule(
				pattern: "\\s*([—–])\\s*ラジオ\\s*$",
				replacement: "",
				enabled: true,
				targetFields: ["album"],
				useCase: .both
			),
			ReplacementRule(
				pattern: "\\s*[—–]\\s*",
				replacement: " - ",
				enabled: true,
				targetFields: ["album"],
				useCase: .both
			),
			ReplacementRule(
				pattern: ";",
				replacement: ", ",
				enabled: true,
				targetFields: ["artist"],
				useCase: .both
			)
		]
	}

	func addRule(_ rule: ReplacementRule) {
		replacementRules.append(rule)
	}

	func removeRule(_ rule: ReplacementRule) {
		replacementRules.removeAll { $0.id == rule.id }
	}

	func addFilterRule(_ rule: FilterRule) {
		filterRules.append(rule)
	}

	func removeFilterRule(_ rule: FilterRule) {
		filterRules.removeAll { $0.id == rule.id }
	}
}
