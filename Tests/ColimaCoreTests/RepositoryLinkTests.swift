import XCTest

@testable import ColimaCore

final class RepositoryLinkTests: XCTestCase {
    func testCommonRemoteFormsOpenTheBranchPage() {
        let expected = "https://github.com/psg2/colima-mini/tree/feature/logs"
        for remote in [
            "git@github.com:psg2/colima-mini.git", "https://github.com/psg2/colima-mini.git",
            "https://github.com/psg2/colima-mini", "ssh://git@github.com/psg2/colima-mini.git\n",
        ] {
            XCTAssertEqual(
                RepositoryLink.webURL(remote: remote, branch: "feature/logs")?.absoluteString, expected,
                remote)
        }
        XCTAssertEqual(
            RepositoryLink.webURL(remote: "git@gitlab.com:group/sub/app.git", branch: "main")?
                .absoluteString, "https://gitlab.com/group/sub/app/-/tree/main")
        XCTAssertEqual(
            RepositoryLink.webURL(remote: "git@github.com:o/r.git", branch: "HEAD")?.absoluteString,
            "https://github.com/o/r")
    }

    func testLocalPathsAndUnknownFormsHaveNoWebPage() {
        for remote in ["/Users/me/repos/app.git", "file:///tmp/app.git", "not a remote", ""] {
            XCTAssertNil(RepositoryLink.webURL(remote: remote, branch: "main"), remote)
        }
    }
}
