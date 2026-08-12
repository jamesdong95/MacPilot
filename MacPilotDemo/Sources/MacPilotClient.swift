import Foundation


enum MacPilotClientError: LocalizedError, Equatable {
    case executableNotFound
    case commandFailed(command: String, message: String, status: Int32)
    case invalidOutput(command: String, message: String)
    case timedOut(command: String, timeout: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The local MacPilot Python core was not found. Install it or set MACPILOT_PROJECT_ROOT."
        case let .commandFailed(command, message, status):
            let detail = message.isEmpty ? "The core exited with status \(status)." : message
            return "MacPilot \(command) failed: \(detail)"
        case let .invalidOutput(command, message):
            return "MacPilot \(command) returned invalid JSON: \(message)"
        case let .timedOut(command, timeout):
            return "MacPilot \(command) timed out after \(String(format: "%.1f", timeout)) seconds."
        }
    }
}


struct MacPilotCommandConfiguration {
    let executableURL: URL
    let leadingArguments: [String]
    let workingDirectoryURL: URL?
    let environment: [String: String]
    let displayName: String
}


struct CoreIndexSummary: Decodable {
    let root: String
    let indexedFiles: Int
    let skippedFiles: Int
    let removedFiles: Int
    let contentFiles: Int
    let skippedSymlinks: Int
    let ignoredDirectories: Int
}


struct CoreSearchResult: Decodable {
    let fileId: Int
    let path: String
    let filename: String
    let `extension`: String
    let size: Int
    let modifiedAt: String
    let snippet: String
    let score: Double
}


struct CoreSuggestion: Decodable {
    let category: String
    let destination: String
    let files: [String]
    let reason: String
}


struct CoreAction: Decodable {
    let id: Int
    let suggestionId: Int
    let sourcePath: String
    let destinationPath: String
    let fingerprint: String
    let appliedAt: String
    let undoneAt: String?
}


struct CoreStatus: Decodable {
    let files: Int
    let pendingSuggestions: Int
    let activeActions: Int
    let undoneActions: Int
}


struct CoreMovePreview: Decodable {
    let actionId: Int
    let source: String
    let destination: String
    let mode: String
}


struct CoreMoveOutcome: Decodable {
    let applied: Bool
    let actionId: Int?
    let sourcePath: String
    let destinationPath: String
    let mode: String
}


struct MacPilotClient {
    private static let defaultTimeout: TimeInterval = 30
    private static let maximumTimeout: TimeInterval = 300

    let configuration: MacPilotCommandConfiguration
    let databaseURL: URL
    let timeout: TimeInterval

    init(
        configuration: MacPilotCommandConfiguration,
        databaseURL: URL,
        timeout: TimeInterval = MacPilotClient.defaultTimeout
    ) {
        self.configuration = configuration
        self.databaseURL = databaseURL
        if timeout.isFinite, timeout > 0 {
            self.timeout = min(timeout, Self.maximumTimeout)
        } else {
            self.timeout = Self.defaultTimeout
        }
    }

    var displayName: String {
        configuration.displayName
    }

    static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MacPilotClient? {
        let databaseURL = databaseURL(environment: environment, fileManager: fileManager)

        if let configuredCLI = environment["MACPILOT_CLI"],
           let executable = executableURL(
               for: configuredCLI,
               environment: environment,
               fileManager: fileManager
           ) {
            return MacPilotClient(
                configuration: MacPilotCommandConfiguration(
                    executableURL: executable,
                    leadingArguments: [],
                    workingDirectoryURL: nil,
                    environment: childEnvironment(from: environment),
                    displayName: executable.path
                ),
                databaseURL: databaseURL
            )
        }

        if let projectRoot = environment["MACPILOT_PROJECT_ROOT"],
           let python = executableURL(
               for: "python3",
               environment: environment,
               fileManager: fileManager
           ) {
            let rootURL = URL(fileURLWithPath: projectRoot).standardizedFileURL
            var childEnv = childEnvironment(from: environment)
            let existingPythonPath = childEnv["PYTHONPATH"]
            childEnv["PYTHONPATH"] = [rootURL.path, existingPythonPath]
                .compactMap { $0 }
                .joined(separator: ":")
            return MacPilotClient(
                configuration: MacPilotCommandConfiguration(
                    executableURL: python,
                    leadingArguments: ["-m", "macpilot"],
                    workingDirectoryURL: rootURL,
                    environment: childEnv,
                    displayName: "Python core at \(rootURL.path)"
                ),
                databaseURL: databaseURL
            )
        }

        let configuredPath = UserDefaults.standard.string(forKey: "macpilot.cliPath")
        let candidateNames = [configuredPath, "macpilot"].compactMap { $0 }
        for candidate in candidateNames {
            if let executable = executableURL(
                for: candidate,
                environment: environment,
                fileManager: fileManager
            ) {
                return MacPilotClient(
                    configuration: MacPilotCommandConfiguration(
                        executableURL: executable,
                        leadingArguments: [],
                        workingDirectoryURL: nil,
                        environment: childEnvironment(from: environment),
                        displayName: executable.path
                    ),
                    databaseURL: databaseURL
                )
            }
        }

        return nil
    }

    func index(root: URL) async throws -> CoreIndexSummary {
        try await runAndDecode(
            CoreIndexSummary.self,
            command: ["index", root.path],
            label: "index"
        )
    }

    func list(root: URL? = nil) async throws -> [CoreSearchResult] {
        var command = ["list"]
        if let root {
            command += ["--root", root.path]
        }
        return try await runAndDecode(
            [CoreSearchResult].self,
            command: command,
            label: "list"
        )
    }

    func search(query: String, limit: Int = 50) async throws -> [CoreSearchResult] {
        try await runAndDecode(
            [CoreSearchResult].self,
            command: ["search", query, "--limit", String(limit)],
            label: "search"
        )
    }

    func suggestions(root: URL) async throws -> [CoreSuggestion] {
        try await runAndDecode(
            [CoreSuggestion].self,
            command: ["suggest", root.path],
            label: "suggest"
        )
    }

    func status() async throws -> CoreStatus {
        try await runAndDecode(CoreStatus.self, command: ["status"], label: "status")
    }

    func actions() async throws -> [CoreAction] {
        try await runAndDecode(
            [CoreAction].self,
            command: ["actions"],
            label: "actions"
        )
    }

    func previewMove(source: String, destination: String) async throws -> CoreMovePreview {
        try await runAndDecode(
            CoreMovePreview.self,
            command: ["move", source, destination],
            label: "move preview"
        )
    }

    func applyMove(source: String, destination: String) async throws -> CoreMoveOutcome {
        try await runAndDecode(
            CoreMoveOutcome.self,
            command: ["move", source, destination, "--apply"],
            label: "move apply"
        )
    }

    func undo(actionID: Int) async throws -> CoreMoveOutcome {
        try await runAndDecode(
            CoreMoveOutcome.self,
            command: ["undo", String(actionID), "--apply"],
            label: "undo apply"
        )
    }

    private func runAndDecode<T: Decodable>(
        _ type: T.Type,
        command: [String],
        label: String
    ) async throws -> T {
        let data = try await run(command: command, label: label)
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(type, from: data)
        } catch {
            throw MacPilotClientError.invalidOutput(
                command: label,
                message: error.localizedDescription
            )
        }
    }

    private func run(command: [String], label: String) async throws -> Data {
        let configuration = configuration
        let databasePath = databaseURL.path
        let arguments = configuration.leadingArguments + ["--db", databasePath] + command
        let runner = ProcessRunner()
        let processTask = Task.detached(priority: .userInitiated) {
            try await Self.execute(
                configuration: configuration,
                arguments: arguments,
                label: label,
                timeout: timeout,
                runner: runner
            )
        }

        do {
            return try await withTaskCancellationHandler(operation: {
                do {
                    return try await withThrowingTaskGroup(of: Data.self) { group in
                        group.addTask {
                            try await processTask.value
                        }
                        group.addTask {
                            try await Task.sleep(
                                nanoseconds: Self.timeoutNanoseconds(timeout)
                            )
                            runner.stop(reason: .timedOut)
                            processTask.cancel()
                            throw MacPilotClientError.timedOut(
                                command: label,
                                timeout: timeout
                            )
                        }
                        defer { group.cancelAll() }
                        return try await group.next()!
                    }
                } catch {
                    if Task.isCancelled {
                        runner.stop(reason: .cancelled)
                        processTask.cancel()
                        throw CancellationError()
                    }
                    throw error
                }
            }, onCancel: {
                runner.stop(reason: .cancelled)
                processTask.cancel()
            })
        } catch {
            if Task.isCancelled {
                runner.stop(reason: .cancelled)
                processTask.cancel()
                throw CancellationError()
            }
            throw error
        }
    }

    private static func execute(
        configuration: MacPilotCommandConfiguration,
        arguments: [String],
        label: String,
        timeout: TimeInterval,
        runner: ProcessRunner
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = configuration.executableURL
                process.arguments = arguments
                process.currentDirectoryURL = configuration.workingDirectoryURL
                process.environment = configuration.environment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                runner.install(process)

                guard !runner.shouldStop else {
                    runner.finish()
                    continuation.resume(throwing: runner.stopError(label: label, timeout: timeout))
                    return
                }

                do {
                    try process.run()
                } catch {
                    runner.finish()
                    continuation.resume(
                        throwing: MacPilotClientError.commandFailed(
                            command: label,
                            message: error.localizedDescription,
                            status: -1
                        )
                    )
                    return
                }

                let stdoutCapture = PipeCapture()
                let stderrCapture = PipeCapture()
                let readGroup = DispatchGroup()

                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stdoutCapture.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    readGroup.leave()
                }

                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderrCapture.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    readGroup.leave()
                }

                process.waitUntilExit()
                readGroup.wait()
                let stdoutData = stdoutCapture.value
                let stderrData = stderrCapture.value
                let stopError = runner.stopErrorIfRequested(
                    label: label,
                    timeout: timeout
                )
                runner.finish()

                if let stopError {
                    continuation.resume(throwing: stopError)
                    return
                }

                guard process.terminationStatus == 0 else {
                    let message = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(
                        throwing: MacPilotClientError.commandFailed(
                            command: label,
                            message: message,
                            status: process.terminationStatus
                        )
                    )
                    return
                }

                continuation.resume(returning: stdoutData)
            }
        }
    }

    private static func timeoutNanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64((seconds * 1_000_000_000).rounded(.up))
    }

    private static func databaseURL(
        environment: [String: String],
        fileManager: FileManager
    ) -> URL {
        if let configured = environment["MACPILOT_DB"], !configured.isEmpty {
            return URL(fileURLWithPath: configured).standardizedFileURL
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".macpilot", isDirectory: true)
            .appendingPathComponent("index.sqlite3")
    }

    private static func childEnvironment(from environment: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        if let path = environment["PATH"] {
            result["PATH"] = path
        }
        return result
    }

    private static func executableURL(
        for value: String,
        environment: [String: String],
        fileManager: FileManager
    ) -> URL? {
        let expandedValue = (value as NSString).expandingTildeInPath
        if expandedValue.contains("/") {
            let url = URL(fileURLWithPath: expandedValue).standardizedFileURL
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbackDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin")
                .path,
        ]

        for directory in pathDirectories + fallbackDirectories {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(expandedValue)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}


private enum ProcessStopReason: Equatable, Sendable {
    case cancelled
    case timedOut
}


private final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopReason: ProcessStopReason?

    var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopReason != nil
    }

    func install(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = stopReason != nil
        lock.unlock()

        if shouldTerminate {
            process.terminate()
        }
    }

    func stop(reason: ProcessStopReason) {
        lock.lock()
        if stopReason == nil {
            stopReason = reason
        }
        let process = self.process
        lock.unlock()

        process?.terminate()
    }

    func stopError(label: String, timeout: TimeInterval) -> Error {
        lock.lock()
        let reason = stopReason
        lock.unlock()
        return error(for: reason, label: label, timeout: timeout)
    }

    func stopErrorIfRequested(label: String, timeout: TimeInterval) -> Error? {
        lock.lock()
        let reason = stopReason
        lock.unlock()
        guard let reason else { return nil }
        return error(for: reason, label: label, timeout: timeout)
    }

    func finish() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    private func error(
        for reason: ProcessStopReason?,
        label: String,
        timeout: TimeInterval
    ) -> Error {
        switch reason {
        case .cancelled, nil:
            return CancellationError()
        case .timedOut:
            return MacPilotClientError.timedOut(command: label, timeout: timeout)
        }
    }
}


private final class PipeCapture {
    private let lock = NSLock()
    private var captured = Data()

    func set(_ data: Data) {
        lock.lock()
        captured = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}
