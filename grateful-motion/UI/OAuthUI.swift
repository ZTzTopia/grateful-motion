import SwiftUI

struct OAuthView: View {
	var client: LastFMClient
	@Environment(\.dismiss) var dismiss

	@State private var username = ""
	@State private var password = ""
	@State private var isLoading = false
	@State private var errorMessage: String?
	@State private var showSuccess = false
	@State private var showLogoutAlert = false

	var body: some View {
		VStack {
			Text("Connect to Last.fm")
				.font(.title)
				.padding(.top)

			if let currentUsername = client.credentials.username {
				VStack(spacing: 16) {
					Label("Logged in as", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)

					Text(currentUsername)
						.font(.title2)
						.fontWeight(.bold)

					Button("Logout", role: .destructive) {
						showLogoutAlert = true
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
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
				}
				.padding(20)
			} else {
				Form {
					Section {
						TextField("Username", text: $username)
							.textFieldStyle(.roundedBorder)
							.autocorrectionDisabled()

						SecureField("Password", text: $password)
							.textFieldStyle(.roundedBorder)

						if let error = errorMessage {
							Text(error)
								.foregroundColor(.red)
								.font(.caption)
						}
					}

					if isLoading {
						ProgressView("Authenticating...")
							.padding()
					}

					if showSuccess {
						Label("Authenticated!", systemImage: "checkmark.circle.fill")
							.foregroundColor(.green)
							.padding()
					}

					Section {
						Button(action: {
							Task {
								await authenticate()
							}
						}) {
							Text("Login")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.borderedProminent)
						.disabled(isLoading || username.isEmpty || password.isEmpty || showSuccess)
					}
				}
				.formStyle(.grouped)
			}

			HStack {
				Button("Cancel") {
					dismiss()
				}
				.keyboardShortcut(.cancelAction)

				Spacer()

				if showSuccess && client.credentials.username == nil {
					Button("Done") {
						dismiss()
					}
					.keyboardShortcut(.defaultAction)
				}
			}
			.padding()
		}
		.frame(width: 400, height: 320)
	}

	private func authenticate() async {
		isLoading = true
		errorMessage = nil

		do {
			let (sessionKey, name) = try await client.getMobileSession(username: username, password: password)

			await MainActor.run {
				client.credentials.username = name
				client.credentials.sessionKey = sessionKey

				isLoading = false
				showSuccess = true

				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					dismiss()
				}
			}
		} catch {
			await MainActor.run {
				isLoading = false
				errorMessage = "Authentication failed. Please check your credentials."
			}
		}
	}
}
