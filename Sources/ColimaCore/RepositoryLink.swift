import Foundation

// Turns a Git remote into the web page of the checked-out branch, for the
// common SSH and HTTPS remote forms.
package enum RepositoryLink {
    package static func webURL(remote: String, branch: String?) -> URL? {
        var text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scp = text.range(of: #"^[^@/\s]+@([^:/\s]+):(.+)$"#, options: .regularExpression),
            scp.lowerBound == text.startIndex
        {
            // git@github.com:owner/repo.git
            let afterAt = text[text.index(after: text.firstIndex(of: "@")!)...]
            let parts = afterAt.split(separator: ":", maxSplits: 1)
            text = "https://\(parts[0])/\(parts[1])"
        }
        guard var components = URLComponents(string: text),
            let scheme = components.scheme?.lowercased(),
            ["https", "http", "ssh", "git"].contains(scheme), let host = components.host
        else { return nil }
        var path = components.path
        if path.hasSuffix(".git") { path.removeLast(4) }
        while path.hasSuffix("/") { path.removeLast() }
        guard path.split(separator: "/").count >= 2 else { return nil }
        if let branch, !branch.isEmpty, branch != "HEAD" {
            let tree = host.contains("gitlab") ? "/-/tree/" : "/tree/"
            path += tree + branch
        }
        components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        return components.url
    }
    package static func isGitHub(_ url: URL) -> Bool { url.host?.lowercased() == "github.com" }
}

extension Backend {
    // Nil when the folder has no `origin` remote.
    package func repositoryURL(folder: String) async throws -> URL? {
        let git = try toolchain.executable("git")
        guard
            let remote = try? await Command.run(
                git, ["-C", folder, "remote", "get-url", "origin"], environment: toolchain.environment)
        else { return nil }
        let branch = try? await Command.run(
            git, ["-C", folder, "rev-parse", "--abbrev-ref", "HEAD"], environment: toolchain.environment)
        return RepositoryLink.webURL(
            remote: remote, branch: branch?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
