import XCTest
@testable import DshStudio

final class SplitAddressTests: XCTestCase {
    func testBareHostKeepsFallbackPort() {
        let parsed = AppModel.splitAddress("100.83.136.24", fallbackPort: 3080)
        XCTAssertEqual(parsed.host, "100.83.136.24")
        XCTAssertEqual(parsed.port, 3080)
    }

    func testHostWithPort() {
        let parsed = AppModel.splitAddress("100.83.136.24:3123", fallbackPort: 3080)
        XCTAssertEqual(parsed.host, "100.83.136.24")
        XCTAssertEqual(parsed.port, 3123)
    }

    func testOutOfRangePortsFallBack() {
        for raw in ["host:0", "host:70000", "host:-1", "host:abc"] {
            let parsed = AppModel.splitAddress(raw, fallbackPort: 3080)
            XCTAssertEqual(parsed.port, 3080, raw)
            XCTAssertEqual(parsed.host, raw, raw)
        }
    }

    // The bare form used to be cut at its last colon, which turned
    // fd7a:115c::1 into the host "fd7a:115c:" on port 1.
    func testBareIPv6IsNotSplit() {
        let parsed = AppModel.splitAddress("fd7a:115c::1", fallbackPort: 3080)
        XCTAssertEqual(parsed.host, "fd7a:115c::1")
        XCTAssertEqual(parsed.port, 3080)
    }

    func testBracketedIPv6() {
        let parsed = AppModel.splitAddress("[fd7a:115c::1]:3080", fallbackPort: 22)
        XCTAssertEqual(parsed.host, "fd7a:115c::1")
        XCTAssertEqual(parsed.port, 3080)
    }

    func testWhitespaceIsTrimmed() {
        let parsed = AppModel.splitAddress("  host:3123 ", fallbackPort: 3080)
        XCTAssertEqual(parsed.host, "host")
        XCTAssertEqual(parsed.port, 3123)
    }
}

final class SessionIDTests: XCTestCase {
    func testAcceptsWhatDshMints() {
        XCTAssertTrue(SessionID.isSafe("session-c05ef2c4-971a-47b7-9f3d-81a404238b6f"))
        XCTAssertTrue(SessionID.isSafe("32dc9e01-5875-4d19-b8ac-3885b8c81344"))
    }

    // The id becomes a path component, so these are the ones that matter.
    func testRejectsTraversal() {
        for id in ["..", "../..", "a/b", "/etc/passwd", "", "a b", "id\u{0000}"] {
            XCTAssertFalse(SessionID.isSafe(id), id)
        }
    }

    func testRejectsAbsurdLength() {
        XCTAssertFalse(SessionID.isSafe(String(repeating: "a", count: 129)))
    }
}

final class PrivateHostTests: XCTestCase {
    func testAcceptsPrivateRanges() {
        for host in ["127.0.0.1", "localhost", "10.0.0.5", "192.168.1.7", "172.16.0.1", "172.31.255.254", "100.83.136.24"] {
            XCTAssertTrue(AppModel.isPrivateHost(host), host)
        }
    }

    func testRejectsPublicAndMalformed() {
        for host in ["8.8.8.8", "100.200.1.1", "172.32.0.1", "example.com", "100.64.abc.1", "100.64.1.1.evil"] {
            XCTAssertFalse(AppModel.isPrivateHost(host), host)
        }
    }
}

final class SanitizeTests: XCTestCase {
    func testPlainTextIsReturnedUnchanged() {
        let source = "ordinary text\nwith a newline\tand a tab"
        XCTAssertEqual(source.sanitizedForDisplay, source)
    }

    func testBidiAndControlScalarsAreRemoved() {
        let source = "before\u{202E}after\u{0007}\u{2066}end"
        XCTAssertEqual(source.sanitizedForDisplay, "beforeafterend")
    }
}

final class MarkdownTests: XCTestCase {
    func testFencedCodeBecomesOneBlock() {
        let blocks = MarkdownParser.blocks("intro\n```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks.count, 2)
        guard case .code(_, let code, let language) = blocks[1] else {
            return XCTFail("expected a code block, got \(blocks[1])")
        }
        XCTAssertEqual(code, "let x = 1")
        XCTAssertEqual(language, "swift")
    }

    func testCacheReturnsEqualBlocksForRepeatedText() {
        let text = "# heading\n\nparagraph"
        XCTAssertEqual(MarkdownParser.blocks(text).count, MarkdownParser.blocks(text).count)
    }
}
