import Foundation

var failureCount = 0
var testCount = 0
var currentTestName = ""

private func fileName(_ file: StaticString) -> String {
    URL(fileURLWithPath: "\(file)").lastPathComponent
}

func test(_ name: String, _ body: () throws -> Void) {
    testCount += 1
    currentTestName = name
    do {
        try body()
    } catch {
        failureCount += 1
        print("FAIL \(name): threw \(error)")
    }
}

func test(_ name: String, _ body: () async throws -> Void) async {
    testCount += 1
    currentTestName = name
    do {
        try await body()
    } catch {
        failureCount += 1
        print("FAIL \(name): threw \(error)")
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        failureCount += 1
        print("FAIL \(fileName(file)):\(line) \(message) [\(currentTestName)]")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        failureCount += 1
        print("FAIL \(fileName(file)):\(line) expected \(expected), got \(actual) [\(currentTestName)]")
    }
}

func expectThrows(_ body: () throws -> Void, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do {
        try body()
        failureCount += 1
        print("FAIL \(fileName(file)):\(line) expected an error \(message) [\(currentTestName)]")
    } catch {}
}

func expectError<E: Error & Equatable>(_ expected: E, file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void) {
    do {
        try body()
        failureCount += 1
        print("FAIL \(fileName(file)):\(line) expected \(expected), nothing thrown [\(currentTestName)]")
    } catch let error as E {
        expectEqual(error, expected, file: file, line: line)
    } catch {
        failureCount += 1
        print("FAIL \(fileName(file)):\(line) expected \(expected), got \(error) [\(currentTestName)]")
    }
}

func expectError<E: Error & Equatable>(_ expected: E, file: StaticString = #file, line: UInt = #line, _ body: () async throws -> Void) async {
    do {
        try await body()
        failureCount += 1
        print("FAIL \(fileName(file)):\(line) expected \(expected), nothing thrown [\(currentTestName)]")
    } catch let error as E {
        expectEqual(error, expected, file: file, line: line)
    } catch {
        failureCount += 1
        print("FAIL \(fileName(file)):\(line) expected \(expected), got \(error) [\(currentTestName)]")
    }
}

func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0, _ millisecond: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let base = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    let milliseconds = base.timeIntervalSince1970.rounded() * 1000 + Double(millisecond)
    return Date(timeIntervalSince1970: milliseconds / 1000)
}
