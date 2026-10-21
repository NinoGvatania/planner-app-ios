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
        XCTAssertEqual(DictationSplitter.split("Созвон в 9.30. Купить хлеб"), ["Созвон в 9.30", "Купить хлеб"])
    }

    func testConjunctionBetweenTwoActionsSplits() {
        XCTAssertEqual(DictationSplitter.split("позвонить маме и купить хлеб"), ["позвонить маме", "купить хлеб"])
        XCTAssertEqual(DictationSplitter.split("купить хлеб и молоко"), ["купить хлеб и молоко"])
        XCTAssertEqual(DictationSplitter.split("Купить хлеб и пять яблок"), ["Купить хлеб и пять яблок"])
        XCTAssertEqual(DictationSplitter.split("позвонить маме, купить хлеб, записаться к врачу"),
                       ["позвонить маме", "купить хлеб", "записаться к врачу"])
        XCTAssertEqual(DictationSplitter.split("созвон в 10, важно и срочно"), ["созвон в 10, важно и срочно"])
    }

    func testConnectors() {
        XCTAssertEqual(DictationSplitter.split("сделать отчёт, а ещё позвонить в банк"), ["сделать отчёт", "позвонить в банк"])
        XCTAssertEqual(DictationSplitter.split("помыть посуду потом вынести мусор"), ["помыть посуду", "вынести мусор"])
        XCTAssertEqual(DictationSplitter.split("ещё раз проверить почту"), ["ещё раз проверить почту"])
        XCTAssertEqual(DictationSplitter.split("Ещё купить батарейки"), ["купить батарейки"])
        XCTAssertEqual(DictationSplitter.split("Купить ещё молока"), ["Купить ещё молока"])
        XCTAssertEqual(DictationSplitter.split("Посмотреть второе видео"), ["Посмотреть второе видео"])
        XCTAssertEqual(DictationSplitter.split("первое позвонить маме, второе купить хлеб"), ["первое позвонить маме", "купить хлеб"])
        XCTAssertEqual(DictationSplitter.split("позвонить маме точка купить хлеб следующая записаться к врачу"),
                       ["позвонить маме", "купить хлеб", "записаться к врачу"])
    }

    func testEmptyAndJunk() {
        XCTAssertEqual(DictationSplitter.split(""), [])
        XCTAssertEqual(DictationSplitter.split(" . , "), [])
    }
}
