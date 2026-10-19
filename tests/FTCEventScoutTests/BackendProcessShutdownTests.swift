import Darwin
import Foundation
import XCTest
@testable import FTCEventScout

final class BackendProcessShutdownTests: XCTestCase {
    func testShutdownWaitsForGracefulProcessExit() async throws {
        let process = try runningShell("trap 'sleep 0.2; exit 0' TERM")
        defer { cleanUp(process) }

        try await BackendProcessShutdown.stop(process)

        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testShutdownKillsProcessThatIgnoresTermination() async throws {
        let process = try runningShell("trap '' TERM")
        defer { cleanUp(process) }
        let started = ContinuousClock.now

        try await BackendProcessShutdown.stop(process)

        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertEqual(process.terminationStatus, SIGKILL)
        XCTAssertLessThan(started.duration(to: .now), .seconds(5))
    }

    func testShutdownCanBeRepeatedAfterProcessExit() async throws {
        let process = try runningShell("trap 'exit 0' TERM")
        defer { cleanUp(process) }

        try await BackendProcessShutdown.stop(process)
        try await BackendProcessShutdown.stop(process)

        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func runningShell(_ signalHandler: String) throws -> Process {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(signalHandler); printf READY; while :; do :; done"]
        process.standardOutput = output
        try process.run()
        let ready = output.fileHandleForReading.readData(ofLength: 5)
        guard ready == Data("READY".utf8) else {
            cleanUp(process)
            throw FixtureError.readySignalMissing
        }
        return process
    }

    private func cleanUp(_ process: Process) {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    private enum FixtureError: Error {
        case readySignalMissing
    }
}
