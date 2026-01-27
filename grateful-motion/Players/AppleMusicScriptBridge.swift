import Foundation

@MainActor
class AppleMusicScriptBridge {
    static let shared = AppleMusicScriptBridge()

    private let scriptSource = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            try
                set pState to player state as string
                set pPos to player position
                set pDur to 0

                try
                    set pDur to duration of current track
                end try

                set rMode to song repeat as string

                return (pPos as string) & "|" & pState & "|" & rMode & "|" & (pDur as string)
            on error errMsg
                return "Error: " & errMsg
            end try
        end tell
    else
        return "Music not running"
    end if
    """

    func getPlayerStatus() -> (position: TimeInterval, isPlaying: Bool, repeatMode: Track.RepeatMode, duration: TimeInterval) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            return (0, false, .off, 0)
        }

        let result = script.executeAndReturnError(&error)

        if let error = error {
            let errorMsg = error.description
            NSLog("AppleMusicScriptBridge: Error: \(errorMsg)")
            return (0, false, .off, 0)
        }

        let resultString = result.stringValue ?? ""
        let components = resultString.components(separatedBy: "|")

        if resultString.hasPrefix("Error:") {
            NSLog("AppleMusicScriptBridge: \(resultString)")
            return (0, false, .off, 0)
        }

        if resultString.contains("Music not running") {
            return (0, false, .off, 0)
        }

        if components.count >= 4 {
            let posStr = components[0].replacingOccurrences(of: ",", with: ".")
            let position = Double(posStr) ?? 0.0
            
            let pState = components[1].lowercased()
            let isPlaying = pState == "playing" || pState == "kpsp"
            
            let rModeStr = components[2].lowercased()
            var repeatMode: Track.RepeatMode = .off

            if rModeStr.contains("one") || rModeStr == "krmo" {
                repeatMode = .one
            } else if rModeStr.contains("all") || rModeStr == "krml" {
                repeatMode = .all
            }
            
            let durStr = components[3].replacingOccurrences(of: ",", with: ".")
            let duration = Double(durStr) ?? 0.0

            return (position, isPlaying, repeatMode, duration)
        }
        
        NSLog("AppleMusicScriptBridge: Invalid result format, components: \(components.count)")
        return (0, false, .off, 0)
    }
}
