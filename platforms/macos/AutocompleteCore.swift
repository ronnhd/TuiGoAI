//
//  AutocompleteCore.swift
//  TuiGoAI
//
//  Adapted from KeyType (MIT License, Copyright (c) 2026 Xi Nai Lai).
//  Core algorithms for inline autocomplete: caret boundary alignment,
//  suffix overlap protection, and word boundary splitting.
//

import Foundation

// MARK: - CaretBoundary

/// Reconciles a model-produced completion with the text already to the left of the caret.
///
/// The generator is fed a *trailing-whitespace-trimmed* prefix (e.g. `"The capital of France is"`
/// rather than `"…is "`), because base models continue a clean word boundary far better
/// than one ending in a dangling space — they then emit a leading separator space (`" Paris."`).
/// If the real text already ended in whitespace, we drop the redundant leading space so
/// the editor never receives a double space.
public enum CaretBoundary {
    /// Drops trailing whitespace (spaces, tabs, newlines) so the prompt ends cleanly at a word boundary.
    public static func trimmingTrailingWhitespace(_ text: String) -> String {
        var view = Substring(text)
        while let last = view.last, last.isWhitespace {
            view = view.dropLast()
        }
        return String(view)
    }

    /// Returns `candidate` adjusted so it inserts cleanly at the caret given `beforeCursor`
    /// (the original, untrimmed text immediately left of the cursor).
    public static func reconcile(_ candidate: String, beforeCursor: String) -> String {
        var result = Substring(candidate)

        // Strip leading newlines/carriage returns
        while let first = result.first, first == "\n" || first == "\r" {
            result = result.dropFirst()
        }

        guard !result.isEmpty else { return "" }

        if let last = beforeCursor.last, last.isWhitespace {
            // Already has whitespace: drop any leading whitespace so we don't double space
            while let first = result.first, first.isWhitespace {
                result = result.dropFirst()
            }
        } else if let last = beforeCursor.last, !last.isWhitespace {
            // Caret is touching a word without trailing space (e.g. "xuất" in "bản đề xuất"):
            // Ensure there is exactly ONE leading space so the continuation doesn't merge with the word!
            while let first = result.first, first.isWhitespace {
                result = result.dropFirst()
            }
            return " " + String(result)
        }

        return String(result)
    }
}

// MARK: - Display & Length Configuration

public enum GhostTextDisplayMode: String, CaseIterable, Identifiable, Codable {
    case inline = "inline"
    case pill = "pill"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .inline: return "Chữ mờ trong dòng (Inline)"
        case .pill: return "Thẻ nổi cạnh con trỏ (Pill)"
        }
    }
}

public enum GhostTextCompletionLength: String, CaseIterable, Identifiable, Codable {
    case short = "short"
    case medium = "medium"
    case long = "long"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .short: return "Ngắn (1–3 từ)"
        case .medium: return "Vừa (4–6 từ)"
        case .long: return "Dài (7–10 từ)"
        }
    }
    public var maxWords: Int {
        switch self {
        case .short: return 3
        case .medium: return 6
        case .long: return 10
        }
    }
    public var numPredict: Int {
        switch self {
        case .short: return 16
        case .medium: return 24
        case .long: return 36
        }
    }
}

// MARK: - SuffixOverlapGuard

/// Detects and truncates completions that reproduce text already present after the caret.
public enum SuffixOverlapGuard {
    /// Returns true when inserting `completion` at the caret would duplicate text in `afterCursor`.
    public static func duplicatesSuffix(
        completion: String,
        beforeCursor: String,
        afterCursor: String,
        minimumOverlap: Int = 3,
        minimumContainedOverlap: Int = 8
    ) -> Bool {
        duplicationStart(
            completion: completion,
            beforeCursor: beforeCursor,
            afterCursor: afterCursor,
            minimumOverlap: minimumOverlap,
            minimumContainedOverlap: minimumContainedOverlap
        ) != nil
    }

    /// Number of leading characters of `completion` to keep before it starts duplicating `afterCursor`.
    /// - `nil`: no overlap (keep all)
    /// - `0`: starts with duplicate immediately (discard)
    /// - `n > 0`: keep first n characters, drop duplicating suffix
    public static func nonDuplicatingPrefixLength(
        completion: String,
        beforeCursor: String,
        afterCursor: String,
        minimumOverlap: Int = 3,
        minimumContainedOverlap: Int = 8
    ) -> Int? {
        guard let normalizedStart = duplicationStart(
            completion: completion,
            beforeCursor: beforeCursor,
            afterCursor: afterCursor,
            minimumOverlap: minimumOverlap,
            minimumContainedOverlap: minimumContainedOverlap
        ) else { return nil }
        return originalPrefixCharacterCount(of: completion, keepingFirstAlphanumerics: normalizedStart)
    }

    static func duplicationStart(
        completion: String,
        beforeCursor: String,
        afterCursor: String,
        minimumOverlap: Int,
        minimumContainedOverlap: Int
    ) -> Int? {
        let normalizedCompletion = normalizedAlphanumerics(completion)
        let normalizedSuffix = normalizedAlphanumerics(afterCursor)
        guard normalizedCompletion.count >= minimumOverlap, !normalizedSuffix.isEmpty else {
            return nil
        }

        // 1. Boundary-aligned: completion copies the head of the suffix
        if normalizedSuffix.hasPrefix(normalizedCompletion) { return 0 }

        // 2. Suffix-contained: completion contains the upcoming suffix
        if normalizedSuffix.count >= minimumContainedOverlap,
           let range = normalizedCompletion.range(of: normalizedSuffix) {
            let offset = normalizedCompletion.distance(from: normalizedCompletion.startIndex, to: range.lowerBound)
            return offset
        }

        // 3. Mid-word partial overlap
        let overlap = longestPrefixOverlap(normalizedCompletion, in: normalizedSuffix)
        if overlap >= minimumOverlap {
            return normalizedCompletion.count - overlap
        }

        return nil
    }

    private static func normalizedAlphanumerics(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func longestPrefixOverlap(_ a: String, in b: String) -> Int {
        var len = min(a.count, b.count)
        while len > 0 {
            let aSuffix = String(a.suffix(len))
            let bPrefix = String(b.prefix(len))
            if aSuffix == bPrefix { return len }
            len -= 1
        }
        return 0
    }

    private static func originalPrefixCharacterCount(
        of text: String,
        keepingFirstAlphanumerics count: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        var seenAlphanumerics = 0
        var charIndex = 0
        for char in text {
            if char.isLetter || char.isNumber {
                seenAlphanumerics += 1
                if seenAlphanumerics == count {
                    return charIndex + 1
                }
            }
            charIndex += 1
        }
        return text.count
    }
}

// MARK: - NextWordSplitter

/// Splits a completion into the "next word" to accept and the remainder,
/// using ICU word boundaries so it works across Vietnamese and other languages.
public enum NextWordSplitter {
    private static let separablePunctuation: Set<Character> = [
        ".", ",", ";", ":", "!", "?",
        "。", "，", "、", "；", "：", "！", "？",
    ]

    /// `head` is the slice to insert on a single accept; `rest` is what remains for subsequent accepts.
    public static func split(_ text: String) -> (head: String, rest: String) {
        guard !text.isEmpty else { return ("", "") }

        // Leading punctuation unit
        if let firstNonSpace = text.firstIndex(where: { !$0.isWhitespace }),
           separablePunctuation.contains(text[firstNonSpace]) {
            var index = firstNonSpace
            while index < text.endIndex, separablePunctuation.contains(text[index]) {
                index = text.index(after: index)
            }
            return (String(text[..<index]), String(text[index...]))
        }

        // Word unit via ICU
        var firstWordEnd: String.Index?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords]) { _, range, _, stop in
            firstWordEnd = range.upperBound
            stop = true
        }

        guard let firstWordEnd else { return (text, "") }
        return (String(text[..<firstWordEnd]), String(text[firstWordEnd...]))
    }
}
