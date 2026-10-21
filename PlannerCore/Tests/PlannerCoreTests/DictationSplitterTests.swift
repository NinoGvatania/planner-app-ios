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
        XCTAssertEqual(DictationSplitter.split("почистить зубы потом свозить Дашу в зоопарк"), ["почистить зубы", "свозить Дашу в зоопарк"])
        XCTAssertEqual(DictationSplitter.split("дать ответ индусам и отправить список в банк"), ["дать ответ индусам", "отправить список в банк"])
        XCTAssertEqual(DictationSplitter.split("ещё раз проверить почту"), ["ещё раз проверить почту"])
        XCTAssertEqual(DictationSplitter.split("Ещё купить батарейки"), ["купить батарейки"])
        XCTAssertEqual(DictationSplitter.split("Купить ещё молока"), ["Купить ещё молока"])
        XCTAssertEqual(DictationSplitter.split("Посмотреть второе видео"), ["Посмотреть второе видео"])
        XCTAssertEqual(DictationSplitter.split("первое позвонить маме, второе купить хлеб"), ["позвонить маме", "купить хлеб"])
        XCTAssertEqual(DictationSplitter.split("позвонить маме точка купить хлеб следующая записаться к врачу"),
                       ["позвонить маме", "купить хлеб", "записаться к врачу"])
    }

    func testOrdinalsInTheMiddle() {
        // «первая» в начале снимает жёсткая связка, «вторая» посреди фразы делит, потому что дальше глагол.
        XCTAssertEqual(
            DictationSplitter.split("первая задача любить Дашу вторая задача гладить кота"),
            ["задача любить Дашу", "вторая задача гладить кота"]
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

    func testSubordinateClausesStayTogether() {
        XCTAssertEqual(DictationSplitter.split("Узнать, что нужно принести на собрание"), ["Узнать, что нужно принести на собрание"])
        XCTAssertEqual(DictationSplitter.split("Позвонить маме, сказать, что приеду в субботу"),
                       ["Позвонить маме", "сказать, что приеду в субботу"])
        XCTAssertEqual(DictationSplitter.split("Купить хлеб и запчасти для машины"), ["Купить хлеб и запчасти для машины"])
        XCTAssertEqual(DictationSplitter.split("Купить фрукты и сладости"), ["Купить фрукты и сладости"])
        XCTAssertEqual(DictationSplitter.split("сходить в магазин и уйти домой"), ["сходить в магазин", "уйти домой"])
        XCTAssertEqual(DictationSplitter.split("спросить, когда будет готово"), ["спросить, когда будет готово"])
        // Платформа говорит «существительное» — окончание на «-ть» не делает слово действием.
        let nouns = NounAwareLinguistics(verbs: ["купить"], nouns: ["кисть"])
        XCTAssertEqual(DictationSplitter.split("купить краску и кисть", linguistics: nouns), ["купить краску и кисть"])
    }

    private struct NounAwareLinguistics: Linguistics {
        let verbs: Set<String>
        let nouns: Set<String>
        func isVerb(_ word: String) -> Bool { verbs.contains(word) }
        func isNoun(_ word: String) -> Bool { nouns.contains(word) }
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
