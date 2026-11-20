import Foundation
import UIKit
import Vision

/// Reads text and recognises objects in photos, on the device.
nonisolated enum LabelReader {
    /// Reads a nutrition label from a photo.
    static func readLabel(from imageData: Data) async throws -> NutritionFacts {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-GB")]
        let observations = try await request.perform(on: imageData)
        let lines = observations.compactMap { observation -> TextLine? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox.cgRect
            // Vision's origin is bottom-left; TextLine grows downwards.
            return TextLine(text: text, minX: box.minX, minY: 1 - box.maxY, height: box.height)
        }
        return LabelParser.parse(lines)
    }

    /// Likely contents of a photo of food, most confident first.
    static func classify(_ imageData: Data) async throws -> [String] {
        let request = ClassifyImageRequest()
        let observations = try await request.perform(on: imageData)
        return observations
            .filter { $0.confidence > 0.1 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }
}

extension UIImage {
    /// JPEG data with the pixels rotated upright, so Vision needs no
    /// orientation hint. Large photos are scaled down to speed up reading.
    func uprightJPEG(maxDimension: CGFloat = 2400) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}
