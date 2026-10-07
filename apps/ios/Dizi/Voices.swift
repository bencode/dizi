import AVFoundation
import Foundation
import ScoreKit

/// The demo melody's voice, read from `Samples/dizi-c` in the app bundle (see its README for the source).
func bundledVoices() throws -> [Voice] {
    guard let folder = Bundle.main.url(forResource: "dizi-c", withExtension: nil, subdirectory: "Samples") else {
        throw VoicesError.missing
    }
    let manifest = try JSONDecoder().decode(
        Manifest.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
    return try manifest.voices.map { entry in
        Voice(
            samples: try samples(of: folder.appending(path: "\(entry.midi).caf")), sampleRate: entry.sampleRate,
            midi: entry.midi, tuneCents: entry.tuneCents, loop: entry.loopStart..<entry.loopEnd)
    }
}

enum VoicesError: Error {
    case missing
    case unreadable(URL)
}

private struct Manifest: Decodable {
    struct Entry: Decodable {
        let midi: Int
        let tuneCents: Double
        let loopStart: Int
        let loopEnd: Int
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
