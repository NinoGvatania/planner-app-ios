import Foundation

/// Знания о языке, которые даёт платформа (на iPhone — NaturalLanguage, на устройстве, без сети).
/// Пакет сам обходится эвристиками; с лингвистикой деление на задачи точнее:
/// глаголы узнаются по части речи, а не только по окончанию «-ть».
public protocol Linguistics {
    /// Слово — глагол (любая форма: «позвонить», «позвони», «купил»)?
    func isVerb(_ word: String) -> Bool
    /// Слово — существительное («запчасти», «сладости»: похожи на инфинитив, но не действие)?
    func isNoun(_ word: String) -> Bool
}

public extension Linguistics {
    func isNoun(_ word: String) -> Bool { false }
}

extension DictationSplitter {
    /// Слова текста: только буквенные, от двух букв.
    static func words(in text: String) -> [String] {
        text.split { !$0.isLetter && $0 != "-" }.map(String.init).filter { $0.count >= 2 }
    }
}
