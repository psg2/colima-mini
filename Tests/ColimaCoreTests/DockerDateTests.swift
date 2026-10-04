import Foundation
import Testing

@testable import ColimaCore

struct DockerDateTests {
    @Test func dockerTimestampsParseAndTheZeroTimeMeansNever() throws {
        let expected = Date(timeIntervalSince1970: 1_790_882_960.762)
        #expect(
            try abs(#require(DockerDate.parse("2026-10-01T19:29:20.762387404Z")).timeIntervalSince1970 - expected.timeIntervalSince1970)
                <= 0.001)
        #expect(try abs(#require(DockerDate.parse("2026-10-01T16:29:20-03:00")).timeIntervalSince1970 - 1_790_882_960) <= 0.001)
        #expect(try abs(#require(DockerDate.parse("2026-10-01T19:29:20.5Z")).timeIntervalSince1970 - 1_790_882_960.5) <= 0.001)
        #expect(DockerDate.parse("0001-01-01T00:00:00Z") == nil)
        #expect(DockerDate.parse("") == nil)
        #expect(DockerDate.parse("yesterday") == nil)
    }
}
