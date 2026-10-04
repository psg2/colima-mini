import Foundation
import Testing

@testable import ColimaCore

struct RepositoryLinkTests {
    @Test func commonRemoteFormsOpenTheBranchPage() {
        let expected = "https://github.com/psg2/colima-mini/tree/feature/logs"
        for remote in [
            "git@github.com:psg2/colima-mini.git", "https://github.com/psg2/colima-mini.git",
            "https://github.com/psg2/colima-mini", "ssh://git@github.com/psg2/colima-mini.git\n",
        ] {
            #expect(RepositoryLink.webURL(remote: remote, branch: "feature/logs")?.absoluteString == expected, "\(remote)")
        }
        #expect(
            RepositoryLink.webURL(remote: "git@gitlab.com:group/sub/app.git", branch: "main")?
                .absoluteString == "https://gitlab.com/group/sub/app/-/tree/main")
        #expect(RepositoryLink.webURL(remote: "git@github.com:o/r.git", branch: "HEAD")?.absoluteString == "https://github.com/o/r")
    }

    @Test func localPathsAndUnknownFormsHaveNoWebPage() {
        for remote in ["/Users/me/repos/app.git", "file:///tmp/app.git", "not a remote", ""] {
            #expect(RepositoryLink.webURL(remote: remote, branch: "main") == nil, "\(remote)")
        }
    }
}
