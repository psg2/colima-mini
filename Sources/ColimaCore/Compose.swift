import Foundation

// Compose commands for a project the app already lists. The project's folder,
// compose files and env files come from the labels Compose put on its
// containers, so the app runs exactly what `docker compose` ran there.
package enum ComposeAction: String, CaseIterable {
    case up, pull, down, downVolumes

    package var title: String {
        switch self {
        case .up: return "Up"
        case .pull: return "Pull images"
        case .down: return "Down"
        case .downVolumes: return "Down and delete volumes"
        }
    }
    package var arguments: [String] {
        switch self {
        case .up: return ["up", "--detach"]
        case .pull: return ["pull"]
        case .down: return ["down"]
        case .downVolumes: return ["down", "--volumes"]
        }
    }
    // Up and pull read the compose files; down works from the labels alone.
    package var needsFolder: Bool { self == .up || self == .pull }
    package var destructive: Bool { self == .down || self == .downVolumes }
    package var explanation: String {
        switch self {
        case .up:
            return
                "Runs `docker compose up --detach` in the project folder. Containers whose configuration changed are recreated; volumes are kept."
        case .pull:
            return
                "Downloads newer images for the project's services. Containers keep their current image until the next Up."
        case .down:
            return
                "Stops and removes the project's containers and networks. Volumes are kept, so Up brings the data back."
        case .downVolumes:
            return
                "Stops and removes the project's containers and networks, and deletes its volumes, including database data. This can't be undone."
        }
    }
}

package struct ComposeProject: Equatable {
    package let name: String
    package let workingDirectory: String?
    package let configFiles: [String]
    package let environmentFiles: [String]

    init(name: String, labels: [String: String]) {
        func paths(_ key: String) -> [String] {
            (labels[key] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        }
        self.name = name
        workingDirectory = labels["com.docker.compose.project.working_dir"].flatMap {
            $0.isEmpty ? nil : $0
        }
        configFiles = paths("com.docker.compose.project.config_files")
        environmentFiles = paths("com.docker.compose.project.environment_file")
    }

    package var folderExists: Bool {
        guard let workingDirectory else { return false }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &directory)
            && directory.boolValue
            && configFiles.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    func arguments(for action: ComposeAction) throws -> [String] {
        var arguments = ["compose", "--project-name", name]
        if folderExists, let workingDirectory {
            arguments += ["--project-directory", workingDirectory]
            for file in configFiles { arguments += ["--file", file] }
            for file in environmentFiles where FileManager.default.fileExists(atPath: file) {
                arguments += ["--env-file", file]
            }
        } else if action.needsFolder {
            throw AppError.message(
                "\(action.title) needs the project's compose files, but "
                    + (workingDirectory.map { "\($0) no longer exists." } ?? "the folder is unknown."))
        }
        return arguments + action.arguments
    }
}

extension Backend {
    // Reads one container's labels, since `docker ps` joins them with commas and
    // compose file lists contain commas too.
    package func composeProject(_ name: String, containerID: String) async throws -> ComposeProject {
        let output = try await docker(["inspect", "--format", "{{json .Config.Labels}}", containerID])
        let labels =
            (try? JSONDecoder().decode([String: String]?.self, from: Data(output.utf8))) ?? nil
        guard let labels, labels["com.docker.compose.project"] == name else {
            throw AppError.message("\(name) is not a Compose project.")
        }
        return ComposeProject(name: name, labels: labels)
    }

    package func compose(_ action: ComposeAction, project: ComposeProject) async throws {
        _ = try await docker(try project.arguments(for: action), timeout: 600)
    }
}
