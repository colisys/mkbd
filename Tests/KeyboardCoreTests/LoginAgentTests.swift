import XCTest
@testable import KeyboardCore

final class LoginAgentTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkbd-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPlistRunsAppAtLoadWithoutKeepAlive() throws {
        let executable = "/Applications/MKbd.app/Contents/MacOS/MKbd"
        let data = try LoginAgent.plist(executable: executable)
        let dictionary = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(dictionary["Label"] as? String, LoginAgent.label)
        XCTAssertEqual(dictionary["ProgramArguments"] as? [String], [executable])
        XCTAssertEqual(dictionary["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(dictionary["ProcessType"] as? String, "Interactive")
        XCTAssertNil(dictionary["KeepAlive"])
    }

    func testEnableAndDisableWriteTheExpectedPlist() throws {
        let executable = "/Applications/MKbd.app/Contents/MacOS/MKbd"
        try LoginAgent.setEnabled(true, executable: executable, directory: directory)
        XCTAssertTrue(LoginAgent.isEnabled(executable: executable, directory: directory))
        XCTAssertEqual(LoginAgent.plistURL(directory: directory).lastPathComponent,
                       "\(LoginAgent.label).plist")

        try LoginAgent.setEnabled(false, executable: executable, directory: directory)
        XCTAssertFalse(LoginAgent.isEnabled(executable: executable, directory: directory))
    }

    func testEnabledRequiresMatchingExecutable() throws {
        try LoginAgent.setEnabled(true, executable: "/A/MKbd", directory: directory)
        XCTAssertFalse(LoginAgent.isEnabled(executable: "/B/MKbd", directory: directory))
        XCTAssertFalse(LoginAgent.isEnabled(executable: nil, directory: directory))
    }

    func testEnablingWithoutAbsolutePathFails() {
        XCTAssertThrowsError(try LoginAgent.setEnabled(true, executable: "MKbd", directory: directory))
    }
}
