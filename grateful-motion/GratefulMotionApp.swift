import SwiftUI
import AppKit
import Combine

/*
import SwiftUI
import SwiftData

@main
struct grateful_motionApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
*/

@main
struct GratefulMotionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var scrobbleEngine: ScrobbleEngine?
    var playerDetector: PlayerDetector?
    var lastFMClient: LastFMClient?
    var statusMenuController: StatusMenuController?

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var authWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupApp()
    }

    func setupApp() {
        let client = LastFMClient()
        let scrobbleDatabase = ScrobbleDatabase()
        let metadataProcessor = MetadataProcessor()

        self.lastFMClient = client

        scrobbleEngine = ScrobbleEngine(
            lastFMClient: client,
            scrobbleDatabase: scrobbleDatabase,
            metadataProcessor: metadataProcessor
        )

        playerDetector = PlayerDetector(scrobbleEngine: scrobbleEngine!)
        playerDetector?.start()

        statusMenuController = StatusMenuController(
            scrobbleEngine: scrobbleEngine!,
            lastFMClient: lastFMClient!,
            statusItem: statusItem!,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onOpenAuth: { [weak self] in self?.showAuthenticate() }
        )
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Grateful")
            button.isEnabled = true
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let contentView = SettingsView(engine: scrobbleEngine!, client: lastFMClient!)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAuthenticate() {
        if authWindow == nil {
            let contentView = OAuthView(client: lastFMClient!)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "Last.fm Authentication"
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.isReleasedWhenClosed = false
            authWindow = window
        }

        authWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        playerDetector?.stop()
    }
}
