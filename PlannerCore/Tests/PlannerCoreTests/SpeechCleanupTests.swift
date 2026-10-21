import XCTest
@testable import PlannerCore

final class SpeechCleanupTests: XCTestCase {
    func testFillersAndLeadIns() {
        XCTAssertEqual(SpeechCleanup.clean("ну мне нужно короче позвонить маме"), "Позвонить маме")
        XCTAssertEqual(SpeechCleanup.clean("Мне нужно съездить на Савеловский потом"), "Съездить на Савеловский потом")
        XCTAssertEqual(SpeechCleanup.clean("типа как бы купить хлеб блин"), "Купить хлеб")
        XCTAssertEqual(SpeechCleanup.clean("Первая задача позвонить маме маме"), "Позвонить маме")
        XCTAssertEqual(SpeechCleanup.clean("Первая задача задача задача"), "")
    }

    func testKeepsContent() {
        XCTAssertEqual(SpeechCleanup.clean("завтра в 10 созвон, важно"), "Завтра в 10 созвон, важно")
        XCTAssertEqual(SpeechCleanup.clean("позвонить в банк, так как карта не работает"), "Позвонить в банк, так как карта не работает")
        XCTAssertEqual(SpeechCleanup.clean("сделать так, чтобы уведомления приходили"), "Сделать так, чтобы уведомления приходили")
        XCTAssertEqual(SpeechCleanup.clean("записаться к стоматологу"), "Записаться к стоматологу")
    }

    func testOrdinalsAndAnnouncements() {
        XCTAssertEqual(SpeechCleanup.clean("первое нужно будет почистить зубы"), "Почистить зубы")
        XCTAssertEqual(SpeechCleanup.clean("вторая задача гладить кота"), "Гладить кота")
        XCTAssertEqual(SpeechCleanup.clean("так мне нужно будет сделать следующие вещи"), "")
        XCTAssertEqual(SpeechCleanup.clean("покормить там животных"), "Покормить животных")
        XCTAssertEqual(SpeechCleanup.clean("сука ёбаный в рот блядь"), "")
    }

    func testJunkIsNotMeaningful() {
        XCTAssertFalse(SpeechCleanup.isMeaningful("как дела"))
        XCTAssertFalse(SpeechCleanup.isMeaningful("Привет"))
        XCTAssertFalse(SpeechCleanup.isMeaningful(""))
        XCTAssertFalse(SpeechCleanup.isMeaningful("ну это"))
        XCTAssertTrue(SpeechCleanup.isMeaningful("Позвонить маме"))
        XCTAssertTrue(SpeechCleanup.isMeaningful("Резюме"))
    }

    func testTidyTitle() {
        XCTAssertEqual(SpeechCleanup.tidyTitle("позвонить маме и"), "Позвонить маме")
        XCTAssertEqual(SpeechCleanup.tidyTitle("купить хлеб потом."), "Купить хлеб")
        XCTAssertEqual(SpeechCleanup.tidyTitle("и"), "И")
    }

    func testMeaningful() {
        XCTAssertFalse(SpeechCleanup.isMeaningful("у"))
        XCTAssertFalse(SpeechCleanup.isMeaningful("в "))
        XCTAssertTrue(SpeechCleanup.isMeaningful("Маме"))
        XCTAssertTrue(SpeechCleanup.isMeaningful("Купить запчасти"))
    }
}
