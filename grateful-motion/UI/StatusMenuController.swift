import Cocoa
import Combine

@MainActor
class StatusMenuController: NSObject, NSMenuDelegate {
    private let scrobbleEngine: ScrobbleEngine
    private let lastFMClient: LastFMClient
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    private let onOpenSettings: () -> Void
    private let onOpenAuth: () -> Void

    private let menu = NSMenu()
    private var artworkCache: [URL: NSImage] = [:]
    private var artworkTasks: [URL: Task<NSImage?, Never>] = [:]
    private var placeholderImage: NSImage!
    private var similarItemsTasks: [String: Task<(artists: [SimilarArtist], tracks: [SimilarTrack]), Error>] = [:]

    private var isMenuOpen = false
    private var needsMenuUpdate = false

    init(scrobbleEngine: ScrobbleEngine, lastFMClient: LastFMClient, statusItem: NSStatusItem, onOpenSettings: @escaping () -> Void, onOpenAuth: @escaping () -> Void) {
        self.scrobbleEngine = scrobbleEngine
        self.lastFMClient = lastFMClient
        self.statusItem = statusItem
        self.onOpenSettings = onOpenSettings
        self.onOpenAuth = onOpenAuth

        super.init()

        self.placeholderImage = StatusMenuController.createPlaceholderImage()

        self.statusItem.menu = self.menu
        self.menu.delegate = self

        updateMenu()
        setupSubscriptions()
    }

    private func setupMenu() {
    }

    private func setupSubscriptions() {
        scrobbleEngine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleStateChange()
            }
            .store(in: &cancellables)

        scrobbleEngine.$lastArtworkURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleStateChange()
            }
            .store(in: &cancellables)

        scrobbleEngine.$recentScrobbles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleStateChange()
            }
            .store(in: &cancellables)

        scrobbleEngine.$isScrobblingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleStateChange()
            }
            .store(in: &cancellables)
    }

    private func handleStateChange() {
        if isMenuOpen {
            refreshLiveItems()
        } else {
            needsMenuUpdate = true
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == self.menu {
            isMenuOpen = true
            if needsMenuUpdate {
                updateMenu()
                needsMenuUpdate = false
            }
            return
        }

        guard let track = menu.items.first?.representedObject as? Track else { return }

        let hasLoaders = menu.items.contains { $0.tag == 101 || $0.tag == 102 }
        if hasLoaders {
            fetchSimilarData(in: menu, for: track)
        }
    }

    private func refreshSimilarData(_ menu: NSMenu, for track: Track) {
        let artistsHeaderIndex = menu.items.firstIndex(where: { $0.title == "Similar Artists" })

        if let index = artistsHeaderIndex {
            while menu.items.count > index + 1 {
                menu.removeItem(at: index + 1)
            }
        }

        let tracksHeaderIndex = menu.items.firstIndex(where: { $0.title == "Similar Tracks" })

        if let index = tracksHeaderIndex {
            while menu.items.count > index + 1 {
                menu.removeItem(at: index + 1)
            }
        }

        rebuildSimilarSection(in: menu, for: track)
    }

    private func rebuildSimilarSection(in menu: NSMenu, for track: Track) {
        let loadingArtists = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        loadingArtists.isEnabled = false
        loadingArtists.tag = 101
        loadingArtists.representedObject = track
        menu.addItem(loadingArtists)

        menu.addItem(NSMenuItem.separator())

        let tracksHeader = NSMenuItem(title: "Similar Tracks", action: nil, keyEquivalent: "")
        tracksHeader.isEnabled = false
        menu.addItem(tracksHeader)

        let loadingTracks = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        loadingTracks.isEnabled = false
        loadingTracks.tag = 102
        loadingTracks.representedObject = track
        menu.addItem(loadingTracks)

        fetchSimilarData(in: menu, for: track)
    }

    private func fetchSimilarData(in menu: NSMenu, for track: Track) {
        let taskKey = "\(track.artist)-\(track.title)"
        if similarItemsTasks[taskKey] != nil { return }

        let task = Task {
            async let artists = lastFMClient.getSimilarArtists(track: track)
            async let tracks = lastFMClient.getSimilarTracks(track: track)
            return try await (artists: artists, tracks: tracks)
        }

        similarItemsTasks[taskKey] = task

        Task { @MainActor in
            do {
                let (artists, tracks) = try await task.value
                self.populateSubmenu(menu, artists: artists, tracks: tracks, setLoaded: true)
            } catch {
                self.handleSubmenuError(in: menu)
            }
            self.similarItemsTasks[taskKey] = nil
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu == self.menu {
            isMenuOpen = false
        }
    }

    private func refreshLiveItems() {
        guard !menu.items.isEmpty else { return }

        if let firstItem = menu.items.first {
            updateNowPlayingItem(firstItem)
        }

        var toggleIndex = -1
        for (index, item) in menu.items.enumerated() {
            if item.action == #selector(toggleScrobbling) {
                toggleIndex = index
                break
            }
        }

        if toggleIndex >= 0 {
            let isEnabled = scrobbleEngine.isScrobblingEnabled
            let toggleTitle = isEnabled ? "Pause Scrobbling" : "Resume Scrobbling"
            menu.items[toggleIndex].title = toggleTitle
        }

        menu.update()
    }

    private func updateNowPlayingItem(_ item: NSMenuItem) {
        if scrobbleEngine.isPlaying, let track = scrobbleEngine.currentTrack {
            let oldTrack = item.representedObject as? Track
            let isDifferentTrack = oldTrack?.title != track.title || oldTrack?.artist != track.artist

            let album = track.album ?? ""
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 1
            paragraphStyle.paragraphSpacing = 1

            let title = "\(track.title) - \(track.artist)"
            let line1 = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ])

            let line2Attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor
            ]

            let fullString = NSMutableAttributedString()
            fullString.append(line1)
            if !album.isEmpty {
                fullString.append(NSAttributedString(string: "\n"))
                fullString.append(NSAttributedString(string: album, attributes: line2Attributes))
            }

            fullString.addAttributes([.paragraphStyle: paragraphStyle], range: NSRange(location: 0, length: fullString.length))

            item.attributedTitle = fullString
            item.representedObject = track

            if isDifferentTrack {
                item.submenu = createSkeletonSubmenu(for: track)
            }

            if let artworkURL = track.artworkURL {
                if let cachedImage = artworkCache[artworkURL] {
                    item.image = cachedImage
                } else {
                    fetchAndCacheArtwork(url: artworkURL) { [weak self] image in
                        if let image = image {
                            self?.artworkCache[artworkURL] = image
                            item.image = image
                        }
                    }
                }
            } else {
                item.image = placeholderImage
            }
        } else {
            item.attributedTitle = NSAttributedString(string: "No Music Playing", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor
            ])
            item.image = placeholderImage
            item.submenu = nil
        }
    }

    private func updateMenu() {
        menu.removeAllItems()

        if scrobbleEngine.isPlaying, let track = scrobbleEngine.currentTrack {
            let item = createTrackMenuItem(track: track, isPlaying: true)
            menu.addItem(item)
        } else {
            let emptyItem = NSMenuItem(title: "No Music Playing", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(NSMenuItem.separator())

        if !scrobbleEngine.recentScrobbles.isEmpty {
            for record in scrobbleEngine.recentScrobbles.prefix(10) {
                let item = createTrackMenuItem(track: record.track, isPlaying: false)
                menu.addItem(item)
            }
        } else {
            let emptyHistory = NSMenuItem(title: "No recent tracks", action: nil, keyEquivalent: "")
            emptyHistory.isEnabled = false
            menu.addItem(emptyHistory)
        }

        menu.addItem(NSMenuItem.separator())

        let isEnabled = scrobbleEngine.isScrobblingEnabled
        let toggleTitle = isEnabled ? "Pause Scrobbling" : "Resume Scrobbling"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleScrobbling), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if lastFMClient.credentials.sessionKey != nil {
            let signOutItem = NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: "")
            signOutItem.target = self
            menu.addItem(signOutItem)
        } else {
            let signInItem = NSMenuItem(title: "Sign In to Last.fm...", action: #selector(signIn), keyEquivalent: "")
            signInItem.target = self
            menu.addItem(signInItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Grateful Motion", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private static func createPlaceholderImage() -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)

        image.lockFocus()

        let cornerRadius: CGFloat = 6
        let rect = NSRect(origin: .zero, size: size)

        let backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3)
        backgroundColor.setFill()

        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let textColor = NSColor.labelColor.withAlphaComponent(0.4)
        if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music") {
            let styledSymbol = symbol.withSymbolConfiguration(config)
            let symbolSize = NSSize(width: 16, height: 16)
            let symbolRect = NSRect(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            textColor.set()
            styledSymbol?.draw(in: symbolRect)
        }

        image.unlockFocus()

        return image
    }

    private func createTrackMenuItem(track: Track, isPlaying: Bool) -> NSMenuItem {
        let album = track.album ?? ""
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1
        paragraphStyle.paragraphSpacing = 1

        let title = "\(track.title) - \(track.artist)"
        let line1 = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: isPlaying ? .bold : .regular),
            .foregroundColor: NSColor.labelColor
        ])

        let line2Attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let fullString = NSMutableAttributedString()
        fullString.append(line1)
        if !album.isEmpty {
            fullString.append(NSAttributedString(string: "\n"))
            fullString.append(NSAttributedString(string: album, attributes: line2Attributes))
        }

        fullString.addAttributes([.paragraphStyle: paragraphStyle], range: NSRange(location: 0, length: fullString.length))

        let item = NSMenuItem()
        item.attributedTitle = fullString
        item.target = self
        item.action = nil
        item.representedObject = track

        item.image = placeholderImage

        if let artworkURL = track.artworkURL {
            if let cachedImage = artworkCache[artworkURL] {
                item.image = cachedImage
            } else {
                fetchAndCacheArtwork(url: artworkURL) { [weak self] image in
                    if let image = image {
                        self?.artworkCache[artworkURL] = image
                        item.image = image
                    }
                }
            }
        }

        item.submenu = createSkeletonSubmenu(for: track)

        return item
    }

    private func createSkeletonSubmenu(for track: Track) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self

        let copyTrackItem = NSMenuItem(title: "Copy Track", action: #selector(copyTrack(_:)), keyEquivalent: "")
        copyTrackItem.representedObject = track
        copyTrackItem.target = self
        submenu.addItem(copyTrackItem)

        let copyArtistItem = NSMenuItem(title: "Copy Artist", action: #selector(copyArtist(_:)), keyEquivalent: "")
        copyArtistItem.representedObject = track
        copyArtistItem.target = self
        submenu.addItem(copyArtistItem)

        let copyAlbumItem = NSMenuItem(title: "Copy Album", action: #selector(copyAlbum(_:)), keyEquivalent: "")
        copyAlbumItem.representedObject = track
        copyAlbumItem.target = self
        submenu.addItem(copyAlbumItem)

        let copyArtistAlbumItem = NSMenuItem(title: "Copy Artist Album", action: #selector(copyArtistAlbum(_:)), keyEquivalent: "")
        copyArtistAlbumItem.representedObject = track
        copyArtistAlbumItem.target = self
        submenu.addItem(copyArtistAlbumItem)

        let openLastfmItem = NSMenuItem(title: "View on Last.fm", action: #selector(openLastfmURL(_:)), keyEquivalent: "")
        openLastfmItem.representedObject = track
        openLastfmItem.target = self
        submenu.addItem(openLastfmItem)

        let openAppleMusicItem = NSMenuItem(title: "View on Apple Music", action: #selector(openAppleMusicURL(_:)), keyEquivalent: "")
        openAppleMusicItem.representedObject = track
        openAppleMusicItem.target = self
        submenu.addItem(openAppleMusicItem)

        submenu.addItem(NSMenuItem.separator())

        let artistsHeader = NSMenuItem(title: "Similar Artists", action: nil, keyEquivalent: "")
        artistsHeader.isEnabled = false
        submenu.addItem(artistsHeader)

        let loadingArtists = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        loadingArtists.isEnabled = false
        loadingArtists.tag = 101
        loadingArtists.representedObject = track
        submenu.addItem(loadingArtists)

        submenu.addItem(NSMenuItem.separator())

        let tracksHeader = NSMenuItem(title: "Similar Tracks", action: nil, keyEquivalent: "")
        tracksHeader.isEnabled = false
        submenu.addItem(tracksHeader)

        let loadingTracks = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        loadingTracks.isEnabled = false
        loadingTracks.tag = 102
        loadingTracks.representedObject = track
        submenu.addItem(loadingTracks)

        return submenu
    }

    private func fetchAndCacheArtwork(url: URL, completion: @escaping (NSImage?) -> Void) {
        if let existingTask = artworkTasks[url] {
            Task { @MainActor in
                let image = await existingTask.value
                completion(image)
            }
            return
        }

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self = self else { return nil }

            let maxRetries = 5
            var attempt = 0
            var delay: TimeInterval = 0.5
            let maxDelay: TimeInterval = 8

            while !Task.isCancelled && attempt < maxRetries {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        return self.resizeImage(image, targetSize: NSSize(width: 32, height: 32))
                    }
                } catch {
                }

                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * 2, maxDelay)
            }

            return nil
        }

        artworkTasks[url] = task

        Task { @MainActor in
            let image = await task.value

            if self.artworkTasks[url] == task {
                self.artworkTasks[url] = nil
            }

            completion(image)
        }
    }

    private func resizeImage(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let newSize = targetSize
        let newImage = NSImage(size: newSize)

        let cornerRadius: CGFloat = 6

        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: newSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }

    private func populateSubmenu(_ menu: NSMenu, artists: [SimilarArtist], tracks: [SimilarTrack], setLoaded: Bool = false) {
        if let artistsLoadingIndex = menu.items.firstIndex(where: { $0.tag == 101 }) {
            menu.removeItem(at: artistsLoadingIndex)

            let artistsIndex = menu.items.firstIndex(where: { $0.title == "Similar Artists" }) ?? artistsLoadingIndex
            if artists.isEmpty {
                let emptyItem = NSMenuItem(title: "No similar artists found", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.insertItem(emptyItem, at: artistsIndex + 1)
            } else {
                for artist in artists.reversed() {
                    let artistItem = NSMenuItem(title: "\(artist.name) (\(Int(artist.match * 100))%)", action: #selector(openSimilarArtist(_:)), keyEquivalent: "")
                    artistItem.target = self
                    artistItem.representedObject = artist
                    menu.insertItem(artistItem, at: artistsIndex + 1)
                }
            }

            if setLoaded {
                let loadedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                loadedItem.isEnabled = false
                loadedItem.tag = 200
                loadedItem.isHidden = true
                menu.insertItem(loadedItem, at: artistsIndex)
            }
        }

        if let tracksLoadingIndex = menu.items.firstIndex(where: { $0.tag == 102 }) {
            menu.removeItem(at: tracksLoadingIndex)

            let tracksIndex = menu.items.firstIndex(where: { $0.title == "Similar Tracks" }) ?? tracksLoadingIndex
            if tracks.isEmpty {
                let emptyItem = NSMenuItem(title: "No similar tracks found", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.insertItem(emptyItem, at: tracksIndex + 1)
            } else {
                for similarTrack in tracks.reversed() {
                    let trackItem = NSMenuItem(title: "\(similarTrack.name) - \(similarTrack.artist) (\(Int(similarTrack.match * 100))%)", action: #selector(openSimilarTrack(_:)), keyEquivalent: "")
                    trackItem.target = self
                    trackItem.representedObject = similarTrack
                    menu.insertItem(trackItem, at: tracksIndex + 1)
                }
            }

            if setLoaded {
                let loadedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                loadedItem.isEnabled = false
                loadedItem.tag = 200
                loadedItem.isHidden = true
                menu.insertItem(loadedItem, at: tracksIndex)
            }
        }
    }

    private func handleSubmenuError(in menu: NSMenu) {
        if let artistsLoadingIndex = menu.items.firstIndex(where: { $0.tag == 101 }) {
            let item = menu.items[artistsLoadingIndex]
            item.title = "Failed to load"
            item.isEnabled = false
        }
        if let tracksLoadingIndex = menu.items.firstIndex(where: { $0.tag == 102 }) {
            let item = menu.items[tracksLoadingIndex]
            item.title = "Failed to load"
            item.isEnabled = false
        }
    }

    @objc private func copyTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(track.title) - \(track.artist)", forType: .string)
    }

    @objc private func copyArtist(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(track.artist, forType: .string)
    }

    @objc private func copyAlbum(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let album = track.album {
            pasteboard.setString(album, forType: .string)
        }
    }

    @objc private func copyArtistAlbum(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let artist = track.albumArtist ?? track.artist
        if let album = track.album {
            pasteboard.setString("\(artist) - \(album)", forType: .string)
        } else {
            pasteboard.setString(artist, forType: .string)
        }
    }

    @objc private func openLastfmURL(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        let encodedArtist = track.artist.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
        let encodedTitle = track.title.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.last.fm/music/\(encodedArtist)/_/\(encodedTitle)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAppleMusicURL(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        let searchTerm = "\(track.artist) \(track.title)"
        guard let encodedTerm = searchTerm.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else { return }
        if let url = URL(string: "music://music.apple.com/search?term=\(encodedTerm)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSimilarArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? SimilarArtist else { return }
        let preferredService = UserDefaults.standard.string(forKey: "preferredService") ?? "lastfm"

        if preferredService == "applemusic" {
            guard let encodedTerm = artist.name.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else { return }
            if let url = URL(string: "music://music.apple.com/search?term=\(encodedTerm)") {
                NSWorkspace.shared.open(url)
            }
        } else {
            if let urlString = artist.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func openSimilarTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? SimilarTrack else { return }
        let preferredService = UserDefaults.standard.string(forKey: "preferredService") ?? "lastfm"

        if preferredService == "applemusic" {
            let searchTerm = "\(track.artist) \(track.name)"
            guard let encodedTerm = searchTerm.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else { return }
            if let url = URL(string: "music://music.apple.com/search?term=\(encodedTerm)") {
                NSWorkspace.shared.open(url)
            }
        } else {
            if let urlString = track.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func showSimilarArtists(_ sender: NSMenuItem) {
    }

    @objc private func showSimilarTracks(_ sender: NSMenuItem) {
    }

    @objc private func toggleScrobbling() {
        scrobbleEngine.isScrobblingEnabled.toggle()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func signIn() {
        onOpenAuth()
    }

    @objc private func signOut() {
        lastFMClient.logout()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
