import CoreText
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "io.upivot.dizi", category: "font")

/// Songti SC (宋体) for Chinese titles. iOS offers it as a downloadable system font, so the app does not bundle it;
/// until it is on the phone, titles fall back to the serif (Chinese in PingFang).
@MainActor @Observable final class SongFont {
    private static let regular = "STSongti-SC-Regular"
    private static let bold = "STSongti-SC-Bold"

    private(set) var isReady =
        UIFont(name: SongFont.regular, size: 12) != nil && UIFont(name: SongFont.bold, size: 12) != nil

    /// A title font: Songti when downloaded, the theme's serif before.
    func font(_ size: CGFloat, bold: Bool = false) -> Font {
        isReady
            ? .custom(bold ? Self.bold : Self.regular, size: size)
            : Theme.serif(size, weight: bold ? .semibold : .medium)
    }

    /// The bold weight for UIKit (navigation bar titles), once downloaded.
    static func uiFont(_ size: CGFloat) -> UIFont? { UIFont(name: bold, size: size) }

    /// Downloads the two weights the first time; later launches only activate them for this process, which is quick.
    func load() async {
        guard !isReady else { return }
        let failure = await download([Self.regular, Self.bold])
        if let failure {
            logger.error("Cannot download Songti SC: \(failure, privacy: .public)")
        }
        isReady = UIFont(name: Self.regular, size: 12) != nil && UIFont(name: Self.bold, size: 12) != nil
    }
}

/// Asks CoreText for the fonts and waits until they are on the phone: nil, or what went wrong.
/// Not main-actor: CoreText calls the handler on its own queue.
private nonisolated func download(_ names: [String]) async -> String? {
    let descriptors = names.map { CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary) }
    return await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors as CFArray, nil) { state, progress in
            switch state {
            case .didFinish:
                done.resume(returning: nil)
                return false
            case .didFailWithError:
                let error = (progress as NSDictionary)[kCTFontDescriptorMatchingError] ?? "unknown"
                done.resume(returning: String(describing: error))
                return false
            default:
                return true
            }
        }
    }
}
