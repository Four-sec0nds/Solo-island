import XCTest
import AppKit
import IslandCore
@testable import IslandPlatform

@MainActor
final class ClipboardServiceTests: XCTestCase {
    func testFinderFileURLAndInitialClipboardAreCaptured() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("example.txt")
        try Data("file".utf8).write(to: file)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
        let service = ClipboardService(folder: folder)
        let entries = try service.capture(pasteboard)
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries.first?.path, file.path)
        XCTAssertEqual(entries.first?.kind, .file)
        XCTAssertTrue(try service.capture(pasteboard).isEmpty)
        XCTAssertEqual(try service.capture(pasteboard, force: true).count, 1)
    }
    func testLegacyFinderFilenamesRepresentation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("legacy.txt"); try Data().write(to: file)
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        pasteboard.setPropertyList([file.path], forType: .init("NSFilenamesPboardType"))
        XCTAssertEqual(try ClipboardService(folder: folder).capture(pasteboard).first?.path, file.path)
    }
    func testTextCapturedAndPrivatePasswordClipboardIgnored() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        let service = ClipboardService(folder: folder)
        pasteboard.setString("Текст из буфера 🌌", forType: .string)
        let entries = try service.capture(pasteboard)
        XCTAssertEqual(entries.first?.kind, .text); XCTAssertEqual(entries.first?.text, "Текст из буфера 🌌")
        pasteboard.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setString("fixture private value", forType: .string)
        XCTAssertTrue(try service.capture(pasteboard).isEmpty)
    }
    func testScreenshotStoredAsPinnedCopyAndSurvivesClipboardChange() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        let service = ClipboardService(folder: folder)
        let image = try makeImage()
        XCTAssertTrue(pasteboard.writeObjects([image]))
        let entry = try XCTUnwrap(try service.capture(pasteboard).first)
        XCTAssertEqual(entry.kind, .image); XCTAssertTrue(entry.isPinned)
        let bytes = try Data(contentsOf: entry.url)
        pasteboard.clearContents(); pasteboard.setString("next clipboard", forType: .string)
        _ = try service.capture(pasteboard)
        XCTAssertEqual(try Data(contentsOf: entry.url), bytes)
        service.removeOwnedImage(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.path))
    }
    func testImageFileIsCopiedBeforeTemporaryOriginalIsDeleted() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try makeImage()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let original = folder.appendingPathComponent("temporary-screenshot.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: original)
        let service = ClipboardService(folder: folder)
        let entry = try service.importFile(original)
        try FileManager.default.removeItem(at: original)
        XCTAssertNotEqual(entry.path, original.path)
        XCTAssertNotNil(NSImage(contentsOf: entry.url))
        // Never remove a user-owned file even if its extension is png.
        let outside = folder.appendingPathComponent("keep.png"); try Data().write(to: outside)
        service.removeOwnedImage(ShelfEntry(path: outside.path, kind: .image))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    private func makeImage() throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.systemPurple, atX: x, y: y) } }
        let image = NSImage(size: NSSize(width: 2, height: 2)); image.addRepresentation(bitmap); return image
    }
}
