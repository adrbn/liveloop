//
//  WebcamClaims.swift
//  LiveLoop
//
//  Who needs the real webcam: the virtual camera, a clip recording, or both.
//  The first claim switches it on, the last release switches it off, and a
//  second owner never restarts it (a restart would cut into a recording).
//

struct WebcamClaims {
    enum Owner { case virtualCamera, clip }

    private var owners: Set<Owner> = []

    var isOn: Bool { !owners.isEmpty }

    /// Returns true when the webcam must be switched on for this claim.
    mutating func claim(_ owner: Owner) -> Bool {
        let wasOn = isOn
        owners.insert(owner)
        return !wasOn
    }

    /// Returns true when nobody needs the webcam any more, so it must go off.
    mutating func release(_ owner: Owner) -> Bool {
        guard owners.remove(owner) != nil else { return false }
        return !isOn
    }
}
