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

    func testOrdinalsInTheMiddle() {
        XCTAssertEqual(
            DictationSplitter.split("первая задача любить Дашу вторая задача гладить кота"),
            ["первая задача любить Дашу", "вторая задача гладить кота"]
        )
        XCTAssertEqual(
            DictationSplitter.split("так мне нужно будет сделать следующие вещи первое нужно будет почистить зубы второе покормить животных последнее доработать предложение надо отправить им информацию"),
            ["так мне нужно будет сделать следующие вещи", "первое нужно будет почистить зубы", "второе покормить животных",
             "последнее доработать предложение", "отправить им информацию"]
        )
        XCTAssertEqual(DictationSplitter.split("Посмотреть второе видео"), ["Посмотреть второе видео"])
        XCTAssertEqual(DictationSplitter.split("доработать текст надо отправить его"), ["доработать текст", "отправить его"])
        XCTAssertEqual(DictationSplitter.split("купить хлеб надо бы ещё"), ["купить хлеб надо бы ещё"])
    }

    /// Лингвистика платформы: глаголы узнаются по части речи, а не только по «-ть».
    private struct FakeLinguistics: Linguistics {
        let verbs: Set<String>
        func isVerb(_ word: String) -> Bool { verbs.contains(word) }
    }

    func testLinguisticsFindsImperatives() {
        let linguistics = FakeLinguistics(verbs: ["купи", "позвони", "вынеси"])
        XCTAssertEqual(DictationSplitter.split("купи хлеб и позвони маме", linguistics: linguistics), ["купи хлеб", "позвони маме"])
        XCTAssertEqual(DictationSplitter.split("купи хлеб и молоко", linguistics: linguistics), ["купи хлеб и молоко"])
        // Без лингвистики повелительное наклонение не распознаётся — остаётся одной задачей.
        XCTAssertEqual(DictationSplitter.split("купи хлеб и позвони маме"), ["купи хлеб и позвони маме"])
        // Число «пять» лингвистика не превращает в глагол, даже если бы сказала «да».
        let greedy = FakeLinguistics(verbs: ["пять", "купить"])
        XCTAssertEqual(DictationSplitter.split("Купить хлеб и пять яблок", linguistics: greedy), ["Купить хлеб и пять яблок"])
    }

    func testEmptyAndJunk() {
        XCTAssertEqual(DictationSplitter.split(""), [])
        XCTAssertEqual(DictationSplitter.split(" . , "), [])
    }
}
