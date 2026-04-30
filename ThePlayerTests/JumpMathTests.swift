// ThePlayerTests/JumpMathTests.swift
import XCTest
@testable import ThePlayer

final class JumpMathTests: XCTestCase {

    // MARK: - nextSecondTime

    func testNextSecondForward() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 10, direction: .forward, seconds: 5, duration: 100), 15, accuracy: 0.0001)
    }

    func testNextSecondBackward() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 10, direction: .backward, seconds: 5, duration: 100), 5, accuracy: 0.0001)
    }

    func testNextSecondClampStart() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 3, direction: .backward, seconds: 5, duration: 100), 0, accuracy: 0.0001)
    }

    func testNextSecondClampEnd() {
        XCTAssertEqual(JumpMath.nextSecondTime(from: 98, direction: .forward, seconds: 5, duration: 100), 100, accuracy: 0.0001)
    }

    func testNextSecondAllShortcutValues() {
        let t: Float = 50
        let dur: Float = 100
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 1, duration: dur), 51, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 2, duration: dur), 52, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 5, duration: dur), 55, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 15, duration: dur), 65, accuracy: 0.0001)
        XCTAssertEqual(JumpMath.nextSecondTime(from: t, direction: .forward, seconds: 30, duration: dur), 80, accuracy: 0.0001)
    }
}
