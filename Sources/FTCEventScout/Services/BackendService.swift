import AppKit
import Foundation

final class BackendService {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        stop()
    }

    func start(
        username: String,
        token: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        stop()

        do {
            let resourceDirectory = try backendResourceDirectory()
            let dataDirectory = try applicationDataDirectory()
            let pythonURL = try resolveLatestPython()
            let scriptURL = resourceDirectory.appendingPathComponent("web_server.py")
            guard FileManager.default.fileExists(atPath: scriptURL.path) else {
                throw BackendServiceError.missingResources
            }

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let output = LineAccumulator()
            let errors = TextAccumulator()
            let gate = CompletionGate(completion: completion)

            process.executableURL = pythonURL
            process.arguments = [
                "-B",
                scriptURL.path,
                "0",
                "--data-dir", dataDirectory.path,
                "--resource-dir", resourceDirectory.path,
            ]
            process.currentDirectoryURL = dataDirectory
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["FTC_SCOUT_APP"] = "1"
            if !username.isEmpty {
                environment["USERNAME"] = username
            } else {
                environment.removeValue(forKey: "USERNAME")
            }
            if !token.isEmpty {
                environment["TOKEN"] = token
            } else {
                environment.removeValue(forKey: "TOKEN")
            }
            process.environment = environment

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in output.append(data) where line.hasPrefix("READY ") {
                    let rawURL = String(line.dropFirst("READY ".count))
                    if let url = URL(string: rawURL) {
                        gate.finish(.success(url))
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    errors.append(data)
                }
            }

            process.terminationHandler = { process in
                let detail = errors.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail.isEmpty
                    ? "The local server exited with status \(process.terminationStatus)."
                    : detail
                gate.finish(.failure(BackendServiceError.launchFailed(message)))
            }

            self.process = process
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            try process.run()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) { [weak process] in
                guard let process, process.isRunning else { return }
                if gate.finish(.failure(BackendServiceError.startupTimedOut)) {
                    process.terminate()
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func backendResourceDirectory() throws -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Backend"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        var sourceRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            sourceRoot.deleteLastPathComponent()
        }
        guard FileManager.default.fileExists(
            atPath: sourceRoot.appendingPathComponent("web_server.py").path
        ) else {
            throw BackendServiceError.missingResources
        }
        return sourceRoot
    }

    private func applicationDataDirectory() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BackendServiceError.applicationSupportUnavailable
        }
        let directory = base.appendingPathComponent("FTC Event Scout", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func resolveLatestPython() throws -> URL {
        let installed = pythonCandidates().compactMap { url -> PythonRuntime? in
            guard FileManager.default.isExecutableFile(atPath: url.path),
                  let version = pythonVersion(at: url),
                  version.major == 3 else {
                return nil
            }
            return PythonRuntime(url: url, version: version)
        }

        guard let latestVersion = installed.map(\.version).max() else {
            throw BackendServiceError.pythonNotFound
        }

        let latestRuntimes = installed.filter { $0.version == latestVersion }
        var firstIncompleteRuntime: (PythonRuntime, [String])?
        for runtime in latestRuntimes {
            let missing = missingPackages(at: runtime.url)
            if missing.isEmpty {
                return runtime.url
            }
            if firstIncompleteRuntime == nil {
                firstIncompleteRuntime = (runtime, missing)
            }
        }

        guard let incomplete = firstIncompleteRuntime else {
            throw BackendServiceError.pythonNotFound
        }
        throw BackendServiceError.missingPythonPackages(
            pythonPath: incomplete.0.url.path,
            packages: incomplete.1
        )
    }

    private func pythonCandidates() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var paths = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/opt/local/bin/python3",
            "/usr/bin/python3",
            home.appendingPathComponent("miniconda3/bin/python3").path,
            home.appendingPathComponent("anaconda3/bin/python3").path,
            home.appendingPathComponent("miniforge3/bin/python3").path,
            home.appendingPathComponent("mambaforge/bin/python3").path,
        ]

        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let executableDirectories = Set(pathDirectories + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            home.appendingPathComponent(".local/bin").path,
        ])
        for directory in executableDirectories {
            let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else { continue }
            paths.append(contentsOf: entries
                .filter { isPythonExecutableName($0.lastPathComponent) }
                .map(\.path))
        }

        let installationRoots = [
            URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions", isDirectory: true),
            home.appendingPathComponent("Library/Frameworks/Python.framework/Versions", isDirectory: true),
            home.appendingPathComponent(".pyenv/versions", isDirectory: true),
            home.appendingPathComponent(".asdf/installs/python", isDirectory: true),
            home.appendingPathComponent(".local/share/mise/installs/python", isDirectory: true),
        ]
        for root in installationRoots {
            guard let versions = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else { continue }
            paths.append(contentsOf: versions.map {
                $0.appendingPathComponent("bin/python3").path
            })
        }

        for rootPath in ["/opt/homebrew/opt", "/usr/local/opt"] {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            guard let packages = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else { continue }
            paths.append(contentsOf: packages
                .filter {
                    $0.lastPathComponent == "python" ||
                        $0.lastPathComponent.hasPrefix("python@")
                }
                .map { $0.appendingPathComponent("bin/python3").path })
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            let expanded = NSString(string: path).expandingTildeInPath
            let canonical = URL(fileURLWithPath: expanded)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            return seen.insert(canonical.path).inserted ? canonical : nil
        }
    }

    private func isPythonExecutableName(_ name: String) -> Bool {
        guard name != "python3-config" else { return false }
        if name == "python3" { return true }
        guard name.hasPrefix("python3.") else { return false }
        return name.dropFirst("python3.".count)
            .split(separator: ".")
            .allSatisfy { Int($0) != nil }
    }

    private func pythonVersion(at url: URL) -> PythonVersion? {
        let process = Process()
        let output = Pipe()
        process.executableURL = url
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return PythonVersion(output: text)
        } catch {
            return nil
        }
    }

    private func missingPackages(at url: URL) -> [String] {
        let requiredPackages = ["numpy", "requests"]
        let packageList = requiredPackages
            .map { "\"\($0)\"" }
            .joined(separator: ", ")
        let script = """
        import importlib
        missing = []
        for package in (\(packageList),):
            try:
                importlib.import_module(package)
            except Exception:
                missing.append(package)
        print(",".join(missing))
        """

        let process = Process()
        let output = Pipe()
        process.executableURL = url
        process.arguments = ["-B", "-c", script]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return requiredPackages }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ",")
                .map(String.init)
        } catch {
            return requiredPackages
        }
    }
}

private struct PythonRuntime {
    let url: URL
    let version: PythonVersion
}

private struct PythonVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(output: String) {
        let expression = try? NSRegularExpression(pattern: #"Python\s+(\d+)\.(\d+)(?:\.(\d+))?"#)
        let range = NSRange(output.startIndex..., in: output)
        guard let match = expression?.firstMatch(in: output, range: range),
              let majorRange = Range(match.range(at: 1), in: output),
              let minorRange = Range(match.range(at: 2), in: output),
              let major = Int(output[majorRange]),
              let minor = Int(output[minorRange]) else {
            return nil
        }
        let patchRange = Range(match.range(at: 3), in: output)
        self.major = major
        self.minor = minor
        patch = patchRange.flatMap { Int(output[$0]) } ?? 0
    }

    static func < (lhs: PythonVersion, rhs: PythonVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let completion: (Result<URL, Error>) -> Void

    init(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
    }

    @discardableResult
    func finish(_ result: Result<URL, Error>) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        lock.unlock()
        DispatchQueue.main.async {
            self.completion(result)
        }
        return true
    }
}

private final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        guard let text = String(data: buffer, encoding: .utf8) else { return [] }
        var lines = text.components(separatedBy: .newlines)
        let trailing = lines.removeLast()
        buffer = Data(trailing.utf8)
        return lines
    }
}

private final class TextAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: storage, encoding: .utf8) ?? ""
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

enum BackendServiceError: LocalizedError {
    case missingResources
    case applicationSupportUnavailable
    case pythonNotFound
    case missingPythonPackages(pythonPath: String, packages: [String])
    case launchFailed(String)
    case startupTimedOut

    var errorDescription: String? {
        switch self {
        case .missingResources:
            "The app’s bundled dashboard resources are missing. Rebuild the app bundle."
        case .applicationSupportUnavailable:
            "FTC Event Scout could not open its Application Support folder."
        case .pythonNotFound:
            "Python 3 was not found. Install the latest Python 3 for macOS, then try again."
        case .missingPythonPackages(let pythonPath, let packages):
            "The newest Python 3 installation is missing \(packages.joined(separator: ", ")). Install them with \"\(pythonPath)\" -m pip install \(packages.joined(separator: " ")), then try again."
        case .launchFailed(let detail):
            "The local server could not start. \(detail)"
        case .startupTimedOut:
            "The local server did not become ready within 15 seconds."
        }
    }
}
