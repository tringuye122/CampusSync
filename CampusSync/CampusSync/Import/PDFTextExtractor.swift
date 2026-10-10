//
//  PDFTextExtractor.swift
//  CampusSync
//
//  Reads text from every page of a PDF with PDFKit. If the PDF has no text layer
//  (a scan), falls back to Vision OCR. The text is returned to the caller and is
//  never logged or written anywhere.
//

import Foundation
import PDFKit
import Vision

nonisolated enum PDFTextExtractor {
    /// One string per page, in order. Callers parse the concatenated text, because
    /// a course card can be split across a page break.
    static func pages(from url: URL) throws -> [String] {
        // File-picker URLs are security-scoped.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ImportError.unreadableFile
        }

        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        if pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return pages
        }

        // Empty text layer: the PDF is a scan.
        let ocr = try (0..<document.pageCount).map { try recognizeText(on: document.page(at: $0)) }
        guard ocr.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ImportError.unreadableFile
        }
        return ocr
    }

    /// Vision OCR for one page, lines ordered top to bottom.
    private static func recognizeText(on page: PDFPage?) throws -> String {
        guard let page else { return "" }
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
        guard let cgImage = image.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])

        let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
