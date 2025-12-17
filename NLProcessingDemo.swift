//
//  ContentView.swift
//  TextTaggingDemo
//
//  Created by Itsuki on 2025/12/16.
//

import SwiftUI
import NaturalLanguage


struct LanguageIdentificationResult {
    var dominantLanguage: NLLanguage?
    var languageHypotheses: [NLLanguage : Double]
}

struct Part: Identifiable {
    var id: String.Index
    
    var substring: String
    var tags: [NLTag: Double]
    
    init(text: String, range: Range<String.Index>, tags: [String: Double]) {
        self.substring = String(text[range])
        self.tags = tags.reduce(into: [NLTag: Double]()) { result, element in
            let key = NLTag(element.key)
            result[key] = element.value
        }
        self.id = range.lowerBound
    }
}

extension Double {
    var twoDecimal: String {
        return self.formatted(.number.precision(.fractionLength(2)))
    }
}

class TextPropertyService {}

// MARK: - Language Identification
extension TextPropertyService {
    static private let languageRecognizer = NLLanguageRecognizer()
    static private let maxLanguageHypothesis: Int = 3
    
    static private func setupLanguageRecognizer() {
        // calling reset will return the language recognizer back to its initial state,
        // removing any input strings, language constraints, and hints that you previously provided
        self.languageRecognizer.reset()
        
        // A list of known probabilities for some or all languages
        // ex: recognizer.languageHints = [.french: 0.5]
        self.languageRecognizer.languageHints = [.english: 0.9, .japanese: 0.5]
        
        // A list of languages the predictions are constrained against
        // ex: recognizer.languageConstraints = [.french, .english, .german, .italian, .spanish, .portuguese]
        self.languageRecognizer.languageConstraints = []
        
    }
    
    // Detect the dominant language as well as the possible languages.
    //
    // we can also use NLTagger here.
    // let tagger = NLTagger(tagSchemes: [.language], options: 0)
    // tagger.string = text
    // let dominantLanguage = tagger.dominantLanguage
    static func identifyLanguage(_ text: String) -> LanguageIdentificationResult {
        self.setupLanguageRecognizer()
        self.languageRecognizer.processString(text)
        // Get the most likely language
        let dominantLanguage = self.languageRecognizer.dominantLanguage
        // Get the possible languages
        let hypothesis = self.languageRecognizer.languageHypotheses(withMaximum: self.maxLanguageHypothesis)

        return LanguageIdentificationResult(dominantLanguage: dominantLanguage, languageHypotheses: hypothesis)
    }


}

// MARK: - Tag Identification
extension TextPropertyService {
    
    static private let maxTagHypothesis: Int = 3
    
    // Classify nouns, verbs, adjectives, and other parts of speech in a string.
    static func identifyLexical(_ text: String) async throws -> [Part] {
        let tagScheme: NLTagScheme = .lexicalClass
        let tagger = NLTagger(tagSchemes: [tagScheme])
        let taggerOptions: NLTagger.Options = []
        let taggerUnit: NLTokenUnit = .word

        return try await self.processTags(text: text, tagger: tagger, tagScheme: tagScheme, unit: taggerUnit, options: taggerOptions, maxHypothesis: self.maxTagHypothesis)
    }
    
    // identify named entities
    static func identifyEntities(_ text: String) async throws -> [Part] {
        let tagScheme: NLTagScheme = .nameType
        let tagger = NLTagger(tagSchemes: [tagScheme])
        let taggerOptions: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let taggerUnit: NLTokenUnit = .word

        return try await self.processTags(text: text, tagger: tagger, tagScheme: tagScheme, unit: taggerUnit, options: taggerOptions, maxHypothesis: self.maxTagHypothesis)
    }
   
    // evaluate sentiment score
    static func evaluateSentimentScore(_ text: String) async throws -> [Part] {
        let tagScheme: NLTagScheme = .sentimentScore
        let tagger = NLTagger(tagSchemes: [.tokenType, tagScheme])
        let taggerOptions: NLTagger.Options = []
        let taggerUnit: NLTokenUnit = .sentence // or paragraph

        return try await self.processTags(text: text, tagger: tagger, tagScheme: tagScheme, unit: taggerUnit, options: taggerOptions, maxHypothesis: self.maxTagHypothesis)
    }
    
    private static func processTags(text: String, tagger: NLTagger, tagScheme: NLTagScheme, unit: NLTokenUnit, options: NLTagger.Options, maxHypothesis: Int) async throws -> [Part] {
        
        tagger.string = text

        try await self.checkTaggerAvailability(tagScheme: tagScheme, unit: unit, text: text)

        let tags = tagger.tags(
            in: text.startIndex..<text.endIndex,
            unit: unit,
            scheme: tagScheme,
            options: options
        )
        
        
        let processedParts: [Part] = tags.map({
            var hypothesis = tagger.tagHypotheses(at: $0.1.lowerBound, unit: unit, scheme: tagScheme, maximumCount: maxHypothesis)
            if let key = $0.0, hypothesis.0[key.rawValue] == nil {
                hypothesis.0[key.rawValue] = 1.0
            }
            return Part(text: text, range: $0.1, tags: hypothesis.0)
        })
        
        return processedParts
    }
    
    
    
    private static func checkTaggerAvailability(tagScheme: NLTagScheme, unit: NLTokenUnit, text: String) async throws {
        guard let dominantLanguage = self.identifyLanguage(text).dominantLanguage else {
            return
        }
        
        let availableTagSchemes = NLTagger.availableTagSchemes(for: unit, language: dominantLanguage)
        if availableTagSchemes.contains(tagScheme) {
            return
        }
        
        // tag scheme is unavailable for the given language,
        // Try loading the asset
        let result = try await NLTagger.requestAssets(for: dominantLanguage, tagScheme: tagScheme)
        switch result {
        case .available:
            return
        case .notAvailable:
            throw NSError(domain: "tagScheme.unavailable", code: 400)
        case .error:
            // the error case should already be thrown by the try await, but just in case.
            throw NSError(domain: "tagScheme.unknownError", code: 400)
        @unknown default:
            return
        }
        
    }
}

struct ContentView: View {
    struct AnalyzeResult {
        var language: LanguageIdentificationResult
        var sentimentScore: [Part]
        var lexical: [Part]
        var entities: [Part]
    }
    
    @State private var text: String = "Hello World! Tokyo is awesome!"
    @State private var error: Error?

    @State private var result: AnalyzeResult?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(text: $text, prompt: Text("Enter Something!"), axis: .vertical, label: {})
                        .lineLimit(3...)
            
                    
                }
                
                Section {
                    Button(action: {
                        guard !self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return
                        }
                        self.error = nil
                        self.result = nil
                        Task {
                            do {
                                let language = TextPropertyService.identifyLanguage(self.text)
                                let sentiment = try await TextPropertyService.evaluateSentimentScore(self.text)
                                let lexical = try await TextPropertyService.identifyLexical(self.text)
                                let entities = try await TextPropertyService.identifyEntities(self.text)
                                self.result = .init(language: language, sentimentScore: sentiment, lexical: lexical, entities: entities)
                            } catch(let error) {
                                self.error = error
                            }
                        }
                    }, label: {
                        Text("Analyze")
                            .font(.headline)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    })
                    .disabled(self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.glassProminent)
                    .listRowInsets(.all, 0)
                    .listRowBackground(Color.clear)
                    
                    if let error {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .listRowBackground(Color.clear)
                    }
                }
                
                if let result {
                    Section("Language") {
                        let language = result.language
                        VStack(alignment: .leading, spacing: 16, content: {
                            row("Dominant Language", "\(language.dominantLanguage?.rawValue, default: "(Unknown)")")
                            row("Hypothesis", "Probability")
                            Group {
                                if language.languageHypotheses.isEmpty {
                                    Text("No hypotheses available.")
                                        .foregroundStyle(.secondary)
                                }
                                let hypothesesLanguages = Array(language.languageHypotheses.keys)
                                ForEach(hypothesesLanguages, id: \.self) { lang in
                                    if let possibility = language.languageHypotheses[lang] {
                                        row("- \(lang.rawValue)", possibility.twoDecimal)
                                    }
                                }
                            }
                            .padding(.leading, 16)
                            .foregroundStyle(.secondary)
                                
                        })
                    }
                    
                    Section("Sentiment Score") {
                        partsView(result.sentimentScore)
                    }
                    
                    Section("Lexical") {
                        partsView(result.lexical)
                    }
                    
                    Section("Entities") {
                        partsView(result.entities)
                    }

                }
                
            }
            .contentMargins(.top, 16)
            .navigationTitle("NL Processing")
        }
        
    }
    
    @ViewBuilder
    private func row(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left)
                .font(.headline)
            
            Spacer()
            
            Text(right)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func partsView(_ parts: [Part]) -> some View {
        VStack(alignment: .leading, spacing: 16, content: {
            ForEach(parts) { part in
                row(part.substring, "Probability")

                Group {
                    if part.tags.isEmpty {
                        Text("No tags available.")
                            .foregroundStyle(.secondary)
                    }
                    let tags = Array(part.tags.keys)
                    ForEach(tags, id: \.self) { tag in
                        if let possibility = part.tags[tag] {
                            row("- \(tag.rawValue)", possibility.twoDecimal)
                        }
                    }
                }
                .padding(.leading, 16)
                .foregroundStyle(.secondary)
            }
            
        })
    }
}

#Preview {
    ContentView()
}
