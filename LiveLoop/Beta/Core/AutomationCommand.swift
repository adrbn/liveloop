//
//  AutomationCommand.swift
//  LiveLoop
//
//  Beta — commands accepted through the `liveloop://` URL scheme, so Shortcuts,
//  Stream Deck, Raycast, Alfred or AppleScript (`open location`) can drive
//  LiveLoop. Parsing is strict: unknown verbs and malformed clip names are
//  rejected rather than guessed.
//
//      liveloop://toggle            liveloop://loop   (alias: away)
//      liveloop://live  (back)      liveloop://start  (on)
//      liveloop://stop  (off)       liveloop://clip?name=Coffee%20break
//

import Foundation

enum AutomationCommand: Equatable {
    case toggle
    case loop
    case live
    case startCamera
    case stopCamera
    case selectClip(String)

    static let scheme = "liveloop"
    static let maxClipNameLength = 200

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        // `liveloop://toggle` puts the verb in the host; `liveloop:toggle` in the path.
        let segments = ([components.host ?? ""] + components.path.split(separator: "/").map(String.init))
            .filter { !$0.isEmpty }
        guard let verb = segments.first?.lowercased() else { return nil }

        switch verb {
        case "toggle": self = .toggle
        case "loop", "away": self = .loop
        case "live", "back": self = .live
        case "start", "on": self = .startCamera
        case "stop", "off": self = .stopCamera
        case "clip":
            let fromQuery = components.queryItems?.first { $0.name.lowercased() == "name" }?.value
            let fromPath = segments.dropFirst().joined(separator: "/")
            guard let name = Self.validClipName(fromQuery ?? fromPath) else { return nil }
            self = .selectClip(name)
        default:
            return nil
        }
    }

    /// The link that runs this command — what Settings ▸ Beta offers to copy.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .toggle: components.host = "toggle"
        case .loop: components.host = "loop"
        case .live: components.host = "live"
        case .startCamera: components.host = "start"
        case .stopCamera: components.host = "stop"
        case .selectClip(let name):
            components.host = "clip"
            let value = name.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? ""
            components.percentEncodedQuery = "name=" + value
        }
        // Always valid: a fixed verb plus, at most, one percent-encoded value.
        return components.url!
    }

    /// `&`, `=`, `+` and `#` would split or end the query, so they're escaped too.
    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))

    /// How a clip link finds its clip: same name, ignoring case, accents and
    /// surrounding spaces.
    static func clipNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let trim = { (name: String) in name.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trim(lhs).compare(trim(rhs), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// One link per distinct name, in order: clips sharing a name share a link.
    static func linkableClipNames(_ names: [String]) -> [String] {
        names.reduce(into: [String]()) { unique, raw in
            guard let name = validClipName(raw), !unique.contains(where: { clipNamesMatch($0, name) }) else { return }
            unique.append(name)
        }
    }

    private static func validClipName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxClipNameLength else { return nil }
        return name
    }
}
