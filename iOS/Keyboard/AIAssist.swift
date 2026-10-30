import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence in the keyboard (on-device; nothing leaves the phone): proofread a selection, other words
/// for one selected word, and next-word ideas. Only on iPhones with Apple Intelligence (iOS 26+, enabled, model
/// ready); everywhere else `available` is false and the keyboard never shows these features.
enum AIAssist {
    #if DEBUG
    /// Tests stand in for the model (the simulator's may not be there).
    struct Stub { var proofread: (String) -> String? = { _ in nil }; var alternatives: (String) -> [String] = { _ in [] }; var next: (String) -> [String] = { _ in [] } }
    static var stub: Stub?
    #endif

    static var available: Bool {
        #if DEBUG
        if stub != nil { return true }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Starts the model early so the first answer is quicker (called when the keyboard appears).
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable { Impl.prewarm() }
        #endif
    }

    /// The selection with spelling, grammar and punctuation fixed, in its own language(s). nil if it failed.
    static func proofread(_ text: String) async -> String? {
        #if DEBUG
        if let stub { return stub.proofread(text) }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), available { return await Impl.proofread(text) }
        #endif
        return nil
    }

    /// Up to 5 words that could replace `word` in its sentence (`before` + word + `after`).
    static func alternatives(for word: String, before: String, after: String) async -> [String] {
        #if DEBUG
        if let stub { return stub.alternatives(word) }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), available { return await Impl.alternatives(word, before, after) }
        #endif
        return []
    }

    /// Up to 3 likely next words after `context` (the text before the cursor).
    static func nextWords(after context: String) async -> [String] {
        #if DEBUG
        if let stub { return stub.next(context) }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), available { return await Impl.nextWords(context) }
        #endif
        return []
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable struct AIWordOptions {
    @Guide(description: "Words or short phrases, best first. Same language as the sentence. Never the original word.", .count(5))
    var options: [String]
}

@available(iOS 26.0, *)
@Generable struct AINextWords {
    @Guide(description: "The three single words the user is most likely to type next, most likely first. Never repeat the typed text.", .count(3))
    var words: [String]
}

@available(iOS 26.0, *)
private enum Impl {
    static let proofreadRules = """
    You proofread text typed on a phone. Fix spelling, accents (Vietnamese diacritics), grammar and punctuation. \
    Keep the meaning, the tone and the language: Vietnamese stays Vietnamese, English stays English, a mix stays a mix. \
    Do not rephrase sentences that are already correct. Reply with only the corrected text.
    """
    static let alternativeRules = "The user selected one word in a sentence and wants other words that fit in its place, keeping the sentence's meaning and language."
    static let nextRules = """
    You are a phone keyboard's next-word predictor. Given the text typed so far, give the 3 words most likely to come next. \
    Text can be Vietnamese, English or both; continue in the language the sentence is in. Each item is a single word.
    """

    static func prewarm() { LanguageModelSession(instructions: proofreadRules).prewarm() }

    static func proofread(_ text: String) async -> String? {
        let s = LanguageModelSession(instructions: proofreadRules)
        let r: LanguageModelSession.Response<String>
        do { r = try await s.respond(to: text, options: GenerationOptions(sampling: .greedy)) }
        catch { NSLog("VikeyAI proofread failed: %@", String(describing: error)); return nil }
        let out = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    static func alternatives(_ word: String, _ before: String, _ after: String) async -> [String] {
        let s = LanguageModelSession(instructions: alternativeRules)
        let prompt = "Sentence: \"\(before)[\(word)]\(after)\". The selected word is in brackets: \"\(word)\"."
        guard let r = try? await s.respond(to: prompt, generating: AIWordOptions.self, options: GenerationOptions(sampling: .greedy)) else { return [] }
        var seen = Set<String>([word.lowercased()]), out: [String] = []
        for o in r.content.options {
            let t = o.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, seen.insert(t.lowercased()).inserted { out.append(t) }
        }
        return out
    }

    static func nextWords(_ context: String) async -> [String] {
        let s = LanguageModelSession(instructions: nextRules)
        guard let r = try? await s.respond(to: String(context.suffix(200)), generating: AINextWords.self, options: GenerationOptions(sampling: .greedy)) else { return [] }
        return r.content.words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.contains(" ") }
    }
}
#endif
