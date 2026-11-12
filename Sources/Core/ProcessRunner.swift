import Foundation

struct ProcessResult: Equatable {
    let status: Int32
    let stdout: Data
    let stderr: String
}

protocol ProcessRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

enum ProcessError: Error, Equatable {
    case notFound(String)
    case timedOut
}

struct ProcessRunner: ProcessRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessError.notFound(executable)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
        let output = CapturedOutput()

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                output.stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                output.stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            process.terminationHandler = { _ in group.leave() }
            do {
                try process.run()
            } catch {
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                once.resume(.failure(error))
                return
            }
            group.notify(queue: .global()) {
                once.resume(.success(ProcessResult(
                    status: process.terminationStatus,
                    stdout: output.stdout,
                    stderr: String(decoding: output.stderr, as: UTF8.self)
                )))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(.failure(ProcessError.timedOut))
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }
}

private final class CapturedOutput: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessResult, Error>?

    init(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<ProcessResult, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
