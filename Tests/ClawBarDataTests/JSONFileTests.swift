import Foundation
import Testing
@testable import ClawBarData

@Suite struct JSONFileTests {
    let dir = TempDir("cb-json")

    @Test func aValueJSONCannotHoldThrowsAndLeavesTheFileAlone() throws {
        let url = dir.write("state.json", "{\"kept\": 1}\n")
        #expect(throws: NotJSON.self) { try JSONFile.write(["costUSD": Double.nan], to: url) }
        #expect(throws: NotJSON.self) { try JSONFile.write(["when": Date()], to: url) }
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == "{\"kept\": 1}\n")
    }
}
