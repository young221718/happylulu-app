import CryptoKit
import Foundation

func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "HappyLuluRelease", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
    let arguments = CommandLine.arguments
    let feedOnly = arguments.count == 4 && arguments[1] == "--feed-only"
    try require(feedOnly || arguments.count == 5, "Pass feed, archive, notes, public key (or --feed-only feed public key)")
    let feed = try Data(contentsOf: URL(fileURLWithPath: arguments[feedOnly ? 2 : 1]))
    let keyString = arguments[feedOnly ? 3 : 4]
    guard let keyData = Data(base64Encoded: keyString) else {
        throw NSError(domain: "HappyLuluRelease", code: 1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let range = feed.range(of: marker),
          feed.range(of: marker, in: range.upperBound..<feed.endIndex) == nil,
          let block = String(data: feed[range.lowerBound...], encoding: .utf8) else {
        throw NSError(domain: "HappyLuluRelease", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Missing or ambiguous feed signature"])
    }
    let lines = block.split(separator: "\n")
    guard let signatureLine = lines.first(where: { $0.hasPrefix("edSignature: ") }),
          let signature = Data(base64Encoded: String(signatureLine.dropFirst(13))),
          let lengthLine = lines.first(where: { $0.hasPrefix("length: ") }),
          let length = Int(lengthLine.dropFirst(8)) else {
        throw NSError(domain: "HappyLuluRelease", code: 1)
    }
    let payload = Data(feed[..<range.lowerBound])
    try require(payload.count == length && key.isValidSignature(signature, for: payload), "Invalid signed appcast bytes")
    if !feedOnly {
        let document = try XMLDocument(data: feed)
        let enclosures = try document.nodes(forXPath: "//item/enclosure")
        let notes = try document.nodes(forXPath: "//item/sparkle:releaseNotesLink")
        try require(enclosures.count == 1 && notes.count == 1, "Expected one archive and one release note")
        for (node, path) in [(enclosures[0], arguments[2]), (notes[0], arguments[3])] {
            guard let element = node as? XMLElement,
                  let value = element.attribute(forName: "sparkle:edSignature")?.stringValue,
                  let signature = Data(base64Encoded: value) else {
                throw NSError(domain: "HappyLuluRelease", code: 1)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            try require(key.isValidSignature(signature, for: data), "Invalid signature for \(URL(fileURLWithPath: path).lastPathComponent)")
        }
    }
    print("PASS signed appcast" + (feedOnly ? "" : ", archive and release notes"))
} catch {
    FileHandle.standardError.write(Data("FAIL update signatures: \(error.localizedDescription)\n".utf8))
    exit(1)
}
