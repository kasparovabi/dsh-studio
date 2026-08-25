import Foundation

// A session id arrives from the server and is then used as a path component on
// this machine, so it is checked against the shape dsh actually mints before it
// can name anything on disk. It lives outside the model because both the model
// and the salvage reader need it, and the reader runs off the main actor.
enum SessionID {
    static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }
}
