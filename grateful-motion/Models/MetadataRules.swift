import Foundation

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
