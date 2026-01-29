import SwiftUI
import Foundation

struct SettingsView: View {
	@ObservedObject var engine: ScrobbleEngine
	@ObservedObject var client: LastFMClient
	@Environment(\.dismiss) var dismiss

	@State private var showLogoutAlert = false
	@AppStorage("preferredService") private var preferredService: String = "lastfm"

	@State private var showReplacementRuleSheet = false
	@State private var showFilterRuleSheet = false
	@State private var currentEditingRule: ReplacementRule?
	@State private var currentEditingFilterRule: FilterRule?

	var body: some View {
		VStack {
			Form {
				Section(header: Text("Last.fm Account")) {
					if let username = client.credentials.username {
						HStack {
							Text("Logged in as")
								.foregroundColor(.secondary)
							Text(username)
								.font(.headline)
							Spacer()
						}

						Button("Logout", role: .destructive) {
							showLogoutAlert = true
						}
						.confirmationDialog(
							"Are you sure you want to logout?",
							isPresented: $showLogoutAlert,
							titleVisibility: .visible
						) {
							Button("Logout", role: .destructive) {
								client.logout()
							}
							Button("Cancel", role: .cancel) { }
						}
					} else {
						Text("Not logged in")
							.foregroundColor(.secondary)
					}
				}

				Section {
					Toggle("Enable Scrobbling", isOn: $engine.isScrobblingEnabled)
				}

				Section(header: Text("Music Service")) {
					Picker("Open Links In", selection: $preferredService) {
						Text("Last.fm").tag("lastfm")
						Text("Apple Music").tag("applemusic")
					}
				}

				Section(header: Text("Replacement Rules")) {
					ForEach(engine.metadataProcessor.replacementRules) { rule in
						HStack {
							Toggle("", isOn: Binding(
								get: { rule.enabled },
								set: { newValue in
									if let index = engine.metadataProcessor.replacementRules.firstIndex(where: { $0.id == rule.id }) {
										engine.metadataProcessor.replacementRules[index].enabled = newValue
									}
								}
							))
							VStack(alignment: .leading, spacing: 2) {
								Text(rule.pattern)
									.font(.system(.body, design: .monospaced))
								Text("→ \(rule.replacement)")
									.font(.system(.caption, design: .monospaced))
									.foregroundColor(.secondary)
							}
							Spacer()
							Text(rule.targetFields.joined(separator: ", "))
								.font(.caption)
								.foregroundColor(.secondary)
						}
						.contextMenu {
							Button("Edit", systemImage: "pencil") {
								currentEditingRule = rule
								showReplacementRuleSheet = true
							}
							Button("Delete", systemImage: "trash", role: .destructive) {
								engine.metadataProcessor.removeRule(rule)
							}
						}
					}

					Button("Add Replacement Rule") {
						currentEditingRule = nil
						showReplacementRuleSheet = true
					}
					.buttonStyle(.borderless)
				}

				Section(header: Text("Filter Rules")) {
					ForEach(engine.metadataProcessor.filterRules) { rule in
						HStack {
							Toggle("", isOn: Binding(
								get: { rule.enabled },
								set: { newValue in
									if let index = engine.metadataProcessor.filterRules.firstIndex(where: { $0.id == rule.id }) {
										engine.metadataProcessor.filterRules[index].enabled = newValue
									}
								}
							))
							VStack(alignment: .leading, spacing: 2) {
								Text(rule.pattern)
									.font(.system(.body, design: .monospaced))
								HStack(spacing: 4) {
									Text(rule.matchType.rawValue.uppercased())
										.font(.caption2)
										.padding(.horizontal, 4)
										.padding(.vertical, 1)
										.background(Color.accentColor.opacity(0.2))
										.cornerRadius(3)
									Text(rule.logic.rawValue)
										.font(.caption2)
										.padding(.horizontal, 4)
										.padding(.vertical, 1)
										.background(Color.accentColor.opacity(0.2))
										.cornerRadius(3)
								}
							}
							Spacer()
						}
						.contextMenu {
							Button("Edit", systemImage: "pencil") {
								currentEditingFilterRule = rule
								showFilterRuleSheet = true
							}
							Button("Delete", systemImage: "trash", role: .destructive) {
								engine.metadataProcessor.removeFilterRule(rule)
							}
						}
					}

					Button("Add Filter Rule") {
						currentEditingFilterRule = nil
						showFilterRuleSheet = true
					}
					.buttonStyle(.borderless)
				}

				Section {
					Button("Reset to Default Rules", role: .destructive) {
						engine.metadataProcessor.loadDefaultRules()
					}
				}

				Section {
					Text("Current Track:")
						.font(.headline)
					if let track = engine.currentTrack {
						Text(track.displayName())
					} else {
						Text("No track playing")
					}
				}
			}
			.formStyle(.grouped)

			HStack {
				Spacer()
				Button("Done") {
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
			.padding()
		}
		.frame(width: 500, height: 600)
		.sheet(isPresented: $showReplacementRuleSheet) {
			ReplacementRuleSheet(
				rule: currentEditingRule,
				onSave: { newRule in
					if let existingRule = currentEditingRule {
						if let index = engine.metadataProcessor.replacementRules.firstIndex(where: { $0.id == existingRule.id }) {
							engine.metadataProcessor.replacementRules[index] = newRule
						}
					} else {
						engine.metadataProcessor.addRule(newRule)
					}
					currentEditingRule = nil
					showReplacementRuleSheet = false
				},
				onCancel: {
					currentEditingRule = nil
					showReplacementRuleSheet = false
				}
			)
		}
		.sheet(isPresented: $showFilterRuleSheet) {
			FilterRuleSheet(
				rule: currentEditingFilterRule,
				onSave: { newRule in
					if let existingRule = currentEditingFilterRule {
						if let index = engine.metadataProcessor.filterRules.firstIndex(where: { $0.id == existingRule.id }) {
							engine.metadataProcessor.filterRules[index] = newRule
						}
					} else {
						engine.metadataProcessor.addFilterRule(newRule)
					}
					currentEditingFilterRule = nil
					showFilterRuleSheet = false
				},
				onCancel: {
					currentEditingFilterRule = nil
					showFilterRuleSheet = false
				}
			)
		}
	}
}

struct ReplacementRuleSheet: View {
	@Environment(\.dismiss) var dismiss

	let rule: ReplacementRule?
	let onSave: (ReplacementRule) -> Void
	let onCancel: () -> Void

	@State private var pattern: String
	@State private var replacement: String
	@State private var targetTitle: Bool
	@State private var targetArtist: Bool
	@State private var targetAlbum: Bool
	@State private var useDisplay: Bool
	@State private var useScrobble: Bool

	init(rule: ReplacementRule?, onSave: @escaping (ReplacementRule) -> Void, onCancel: @escaping () -> Void) {
		self.rule = rule
		self.onSave = onSave
		self.onCancel = onCancel

		_pattern = State(initialValue: rule?.pattern ?? "")
		_replacement = State(initialValue: rule?.replacement ?? "")
		_targetTitle = State(initialValue: rule?.targetFields.contains("title") ?? true)
		_targetArtist = State(initialValue: rule?.targetFields.contains("artist") ?? true)
		_targetAlbum = State(initialValue: rule?.targetFields.contains("album") ?? false)
		_useDisplay = State(initialValue: rule?.useCase == .display || rule?.useCase == .both)
		_useScrobble = State(initialValue: rule?.useCase == .scrobble || rule?.useCase == .both)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(rule == nil ? "Add Replacement Rule" : "Edit Replacement Rule")
				.font(.title2)
				.fontWeight(.bold)

			Form {
				Section("Pattern (Regex)") {
					TextField("Enter pattern", text: $pattern)
						.font(.system(.body, design: .monospaced))
				}

				Section("Replacement") {
					TextField("Enter replacement", text: $replacement)
						.font(.system(.body, design: .monospaced))
				}

				Section("Target Fields") {
					Toggle("Title", isOn: $targetTitle)
					Toggle("Artist", isOn: $targetArtist)
					Toggle("Album", isOn: $targetAlbum)
				}

				Section("Apply To") {
					Toggle("Display", isOn: $useDisplay)
					Toggle("Scrobble", isOn: $useScrobble)
				}
			}
			.formStyle(.grouped)

			HStack {
				Button("Cancel", role: .cancel) {
					onCancel()
				}
				.keyboardShortcut(.escape, modifiers: [])

				Spacer()

				Button("Save") {
					let useCase: ReplacementRule.RuleUseCase
					if useDisplay && useScrobble {
						useCase = .both
					} else if useDisplay {
						useCase = .display
					} else {
						useCase = .scrobble
					}

					var targetFields: [String] = []
					if targetTitle { targetFields.append("title") }
					if targetArtist { targetFields.append("artist") }
					if targetAlbum { targetFields.append("album") }

					let newRule = ReplacementRule(
						pattern: pattern,
						replacement: replacement,
						enabled: rule?.enabled ?? true,
						targetFields: targetFields,
						useCase: useCase
					)
					onSave(newRule)
				}
				.disabled(pattern.isEmpty)
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding()
		.frame(width: 500, height: 500)
	}
}

struct FilterRuleSheet: View {
	@Environment(\.dismiss) var dismiss

	let rule: FilterRule?
	let onSave: (FilterRule) -> Void
	let onCancel: () -> Void

	@State private var pattern: String
	@State private var matchType: FilterRule.MatchType
	@State private var logic: FilterRule.FilterLogic

	init(rule: FilterRule?, onSave: @escaping (FilterRule) -> Void, onCancel: @escaping () -> Void) {
		self.rule = rule
		self.onSave = onSave
		self.onCancel = onCancel

		_pattern = State(initialValue: rule?.pattern ?? "")
		_matchType = State(initialValue: rule?.matchType ?? .regex)
		_logic = State(initialValue: rule?.logic ?? .exclude)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(rule == nil ? "Add Filter Rule" : "Edit Filter Rule")
				.font(.title2)
				.fontWeight(.bold)

			Form {
				Section("Pattern") {
					TextField("Enter pattern", text: $pattern)
						.font(.system(.body, design: .monospaced))
				}

				Section("Match Type") {
					Picker("Match Type", selection: $matchType) {
						Text("Regex").tag(FilterRule.MatchType.regex)
						Text("Exact").tag(FilterRule.MatchType.exact)
						Text("Contains").tag(FilterRule.MatchType.contains)
					}
					.pickerStyle(.segmented)
				}

				Section("Logic") {
					Picker("Logic", selection: $logic) {
						Text("Exclude").tag(FilterRule.FilterLogic.exclude)
						Text("Include").tag(FilterRule.FilterLogic.include)
						Text("Include Any").tag(FilterRule.FilterLogic.includeAny)
						Text("Exclude Any").tag(FilterRule.FilterLogic.excludeAny)
						Text("All").tag(FilterRule.FilterLogic.all)
						Text("None").tag(FilterRule.FilterLogic.none)
					}
					.pickerStyle(.menu)
				}
			}
			.formStyle(.grouped)

			HStack {
				Button("Cancel", role: .cancel) {
					onCancel()
				}
				.keyboardShortcut(.escape, modifiers: [])

				Spacer()

				Button("Save") {
					let newRule = FilterRule(
						pattern: pattern,
						enabled: rule?.enabled ?? true,
						matchType: matchType,
						logic: logic
					)
					onSave(newRule)
				}
				.disabled(pattern.isEmpty)
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding()
		.frame(width: 450, height: 400)
	}
}

struct HistoryView: View {
	@ObservedObject var engine: ScrobbleEngine
	@Environment(\.dismiss) var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Recently Played")
				.font(.title2)
				.fontWeight(.bold)

			List {
				ForEach(engine.recentScrobbles) { record in
					HStack(spacing: 12) {
						VStack(alignment: .leading, spacing: 2) {
							Text(record.track.title)
								.font(.headline)
								.lineLimit(1)
							Text(record.track.artist)
								.font(.subheadline)
								.foregroundColor(.secondary)
								.lineLimit(1)
							if let album = record.track.album {
								Text(album)
									.font(.caption)
									.foregroundColor(.secondary)
									.lineLimit(1)
							}
						}

						Spacer()

						Text(record.timestamp, style: .time)
							.font(.caption2)
							.foregroundColor(.secondary)
					}
					.padding(.vertical, 4)
				}
			}
			.listStyle(.inset)

			HStack {
				Spacer()
				Button("Close") {
					dismiss()
				}
				.keyboardShortcut(.escape, modifiers: [])
			}
		}
		.frame(width: 500, height: 500)
		.padding()
		.onAppear {
			engine.loadRecentScrobbles()
		}
	}
}
