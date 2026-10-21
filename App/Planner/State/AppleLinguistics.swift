import Foundation
import NaturalLanguage
import PlannerCore

/// Части речи по-русски от NaturalLanguage: считается на устройстве, без сети.
struct AppleLinguistics: Linguistics {
    static let shared = AppleLinguistics()

    /// Не глаголы, которые теггер иногда принимает за глаголы в изоляции.
    private static let exceptions: Set<String> = ["важно", "срочно", "завтра", "сегодня", "потом", "утром", "вечером"]

    func isVerb(_ word: String) -> Bool {
        let low = word.lowercased()
        guard low.count >= 3, !Self.exceptions.contains(low) else { return false }
        return tag(of: low) == .verb
    }

    func isNoun(_ word: String) -> Bool {
        tag(of: word.lowercased()) == .noun
    }

    private func tag(of word: String) -> NLTag? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        tagger.setLanguage(.russian, range: word.startIndex..<word.endIndex)
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass)
        return tag
    }
}
