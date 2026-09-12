import XCTest
@testable import Mealee

// The join screen never disables its buttons; it answers a tap by naming the one thing
// still missing. These pin that a tap can always be answered, and answered in order.
final class JoinFormTests: XCTestCase {

    func testNameIsAskedForBeforeAnythingElse() {
        let form = JoinForm(name: "  ", code: "", leagueName: "")
        XCTAssertEqual(form.missingForJoin, "Enter your name first, so rivals know who they are fighting.")
        XCTAssertEqual(form.missingForCreate, "Enter your name first, so rivals know who they are fighting.")
    }

    func testCodeIsAskedForOnceNamed() {
        let form = JoinForm(name: "Viren", code: "", leagueName: "")
        XCTAssertEqual(form.missingForJoin, "Enter the league's 4-letter code to join it.")
    }

    func testShortCodeSaysHowLongItShouldBe() {
        let form = JoinForm(name: "Viren", code: "DEM", leagueName: "")
        XCTAssertEqual(form.missingForJoin, "A league code is exactly 4 letters, like DEMO.")
    }

    func testCompleteJoinHasNothingMissing() {
        let form = JoinForm(name: " Viren ", code: " DEMO ", leagueName: "")
        XCTAssertNil(form.missingForJoin)
        XCTAssertEqual(form.trimmedName, "Viren")
        XCTAssertEqual(form.trimmedCode, "DEMO")
    }

    func testLeagueNameIsAskedForWhenCreating() {
        let form = JoinForm(name: "Viren", code: "", leagueName: "   ")
        XCTAssertEqual(form.missingForCreate, "Give your league a name, like Hall 3 Lunch.")
    }

    func testCompleteCreateHasNothingMissing() {
        let form = JoinForm(name: "Viren", code: "", leagueName: "Hall 3 Lunch")
        XCTAssertNil(form.missingForCreate)
    }

    func testCustomAvatarAcceptsOneEmojiAndRejectsPlainText() {
        XCTAssertEqual(AvatarChoice.emoji(from: "🫐"), "🫐")
        XCTAssertEqual(AvatarChoice.emoji(from: "  👨‍🍳 extra"), "👨‍🍳")
        XCTAssertNil(AvatarChoice.emoji(from: "V"))
        XCTAssertNil(AvatarChoice.emoji(from: "1"))
        XCTAssertNil(AvatarChoice.emoji(from: ""))
    }
}
