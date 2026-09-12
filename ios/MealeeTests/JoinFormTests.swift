import XCTest
@testable import Mealee

// The arena screen never disables its button; it answers a tap by naming what is missing.
final class JoinFormTests: XCTestCase {

    func testNameIsRequiredToEnter() {
        XCTAssertEqual(JoinForm(name: "  ").missingToEnter,
                       "Enter your name first, so rivals know who they are fighting.")
    }

    func testNamedPlayerCanEnter() {
        let form = JoinForm(name: " Viren ")
        XCTAssertNil(form.missingToEnter)
        XCTAssertEqual(form.trimmedName, "Viren")
    }

    func testCustomAvatarAcceptsOneEmojiAndRejectsPlainText() {
        XCTAssertEqual(AvatarChoice.emoji(from: "🫐"), "🫐")
        XCTAssertEqual(AvatarChoice.emoji(from: "  👨‍🍳 extra"), "👨‍🍳")
        XCTAssertNil(AvatarChoice.emoji(from: "V"))
        XCTAssertNil(AvatarChoice.emoji(from: ""))
    }
}
