import XCTest
@testable import PlannerCore

final class SpeechCleanupTests: XCTestCase {
    func testFillersAndLeadIns() {
        XCTAssertEqual(SpeechCleanup.clean("ну мне нужно короче позвонить маме"), "Позвонить маме")
        XCTAssertEqual(SpeechCleanup.clean("Мне нужно съездить на Савеловский потом"), "Съездить на Савеловский потом")
        XCTAssertEqual(SpeechCleanup.clean("типа как бы купить хлеб блин"), "Купить хлеб")
        XCTAssertEqual(SpeechCleanup.clean("Первая задача задача задача"), "Первая задача")
    }

    func testKeepsContent() {
        XCTAssertEqual(SpeechCleanup.clean("завтра в 10 созвон, важно"), "Завтра в 10 созвон, важно")
        XCTAssertEqual(SpeechCleanup.clean("записаться к стоматологу"), "Записаться к стоматологу")
    }

    func testMeaningful() {
        XCTAssertFalse(SpeechCleanup.isMeaningful("у"))
        XCTAssertFalse(SpeechCleanup.isMeaningful("в "))
        XCTAssertTrue(SpeechCleanup.isMeaningful("Маме"))
        XCTAssertTrue(SpeechCleanup.isMeaningful("Купить запчасти"))
    }
}
