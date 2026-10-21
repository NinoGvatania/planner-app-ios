import XCTest
@testable import PlannerCore

final class DictationSplitterTests: XCTestCase {
    func testSentencesAndPausesSplit() {
        XCTAssertEqual(
            DictationSplitter.split("Позвонить маме. Купить хлеб и молоко. Завтра в 10 созвон, важно"),
            ["Позвонить маме", "Купить хлеб и молоко", "Завтра в 10 созвон, важно"]
        )
        XCTAssertEqual(
            DictationSplitter.split("записаться к врачу\nоплатить интернет"),
            ["записаться к врачу", "оплатить интернет"]
        )
    }

    func testConjunctionBetweenTwoActionsSplits() {
        XCTAssertEqual(DictationSplitter.split("позвонить маме и купить хлеб"), ["позвонить маме", "купить хлеб"])
        XCTAssertEqual(DictationSplitter.split("купить хлеб и молоко"), ["купить хлеб и молоко"])
        XCTAssertEqual(DictationSplitter.split("позвонить маме, купить хлеб, записаться к врачу"),
                       ["позвонить маме", "купить хлеб", "записаться к врачу"])
        XCTAssertEqual(DictationSplitter.split("созвон в 10, важно и срочно"), ["созвон в 10, важно и срочно"])
    }

    func testConnectors() {
        XCTAssertEqual(DictationSplitter.split("сделать отчёт, а ещё позвонить в банк"), ["сделать отчёт", "позвонить в банк"])
        XCTAssertEqual(DictationSplitter.split("помыть посуду потом вынести мусор"), ["помыть посуду", "вынести мусор"])
        XCTAssertEqual(DictationSplitter.split("ещё раз проверить почту"), ["ещё раз проверить почту"])
        XCTAssertEqual(DictationSplitter.split("Ещё купить батарейки"), ["купить батарейки"])
    }

    func testEmptyAndJunk() {
        XCTAssertEqual(DictationSplitter.split(""), [])
        XCTAssertEqual(DictationSplitter.split(" . , "), [])
    }
}
