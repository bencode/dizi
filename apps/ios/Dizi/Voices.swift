import AVFoundation
import Foundation
import ScoreKit

/// The demo melody's voice, read from `Samples/piano` in the app bundle (see its README for the source).
func bundledVoices() throws -> [Voice] {
    guard let folder = Bundle.main.url(forResource: "piano", withExtension: nil, subdirectory: "Samples") else {
        throw VoicesError.missing
    }
    let manifest = try JSONDecoder().decode(
        Manifest.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
    return try manifest.voices.map { entry in
        Voice(
            samples: try samples(of: folder.appending(path: "\(entry.midi).caf")), sampleRate: entry.sampleRate,
            midi: entry.midi)
    }
}

enum VoicesError: Error {
    case missing
    case unreadable(URL)
}

private struct Manifest: Decodable {
    struct Entry: Decodable {
        let midi: Int
        let sampleRate: Double
    }

    let voices: [Entry]
}

private func samples(of url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
    else { throw VoicesError.unreadable(url) }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else { throw VoicesError.unreadable(url) }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}
