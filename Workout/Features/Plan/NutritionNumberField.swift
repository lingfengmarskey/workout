import SwiftUI

/// A Form row for a nutrition number. A bare `TextField` only shows its
/// placeholder while empty, so once the user types you can no longer tell which
/// value a field holds; this keeps the label visible on the leading edge at all
/// times. Input is also clamped to at most two decimal places.
struct NutritionNumberField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        LabeledContent(label) {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, newValue in
                    let clamped = NutritionDecimalInput.clamp(newValue)
                    if clamped != newValue { text = clamped }
                }
        }
    }
}

/// Keeps a decimal-pad string to digits plus a single separator with at most
/// `places` fraction digits. Accepts both "." and "," as the separator and
/// leaves the user's choice in place (parsing normalizes it later).
enum NutritionDecimalInput {
    /// Initial field text for a value coming from a data source (barcode lookup,
    /// OCR, a stored entry): rounded to at most `places` decimals, no grouping
    /// separators, trailing zeros dropped.
    static func text(from value: Double, places: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)).grouping(.never))
    }

    static func text(from value: Double?, places: Int = 2) -> String {
        value.map { text(from: $0, places: places) } ?? ""
    }

    static func clamp(_ input: String, places: Int = 2) -> String {
        var result = ""
        var seenSeparator = false
        var fractionCount = 0
        for character in input {
            if character.isNumber {
                if seenSeparator {
                    guard fractionCount < places else { continue }
                    fractionCount += 1
                }
                result.append(character)
            } else if character == "." || character == "," {
                guard !seenSeparator, places > 0 else { continue }
                seenSeparator = true
                result.append(character)
            }
        }
        return result
    }
}
