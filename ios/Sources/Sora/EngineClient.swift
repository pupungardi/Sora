import AVFoundation
import Foundation
import SwiftUI

/// Turns a magnet link into a playable loopback URL.
///
/// Real implementation lives behind `canImport(NuvioEngine)`, because the
/// framework only exists after `scripts/build-apple.sh` has built
/// `NuvioEngine.xcframework` on a Mac. That keeps the Xcode project compiling
/// (as a direct-URL player) before the engine is wired in.
actor EngineClient {
    private var engine: NuvioEngineHandle?

    /// Resolves user input to a URL that AVPlayer (or MPVKit) can open.
    /// Throws for unsupported input or engine failures.
    func playableURL(for input: String) async throws -> URL {
        if !input.lowercased().hasPrefix("magnet:") {
            guard let url = URL(string: input), url.scheme != nil else {
                throw SoraError.invalidInput
            }
            return url
        }

        let engine: NuvioEngineHandle
        if let existing = self.engine {
            engine = existing
        } else {
            engine = try await start()
            self.engine = engine
        }

        let torrentID = try await engine.addMagnet(input)
        let files = try await engine.files(torrentID)
        guard let file = Self.pickVideoFile(files) else {
            throw SoraError.noPlayableFile
        }
        return try await engine.prepareStream(
            torrentID: torrentID,
            fileIndex: file.index,
            filenameHint: file.path
        )
    }

    func shutdown() async {
        await engine?.shutdown()
        engine = nil
    }

    private func start() async throws -> NuvioEngineHandle {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let caches = try fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let data = support.appending(path: "nuvio-engine", directoryHint: .isDirectory)
        let cache = caches.appending(path: "nuvio-engine", directoryHint: .isDirectory)
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)

        return try await NuvioEngineHandle.create(dataDirectory: data, cacheDirectory: cache)
    }

    private static func pickVideoFile(_ files: [NuvioTorrentFile]) -> NuvioTorrentFile? {
        let candidates = files.filter { $0.size > 0 }
        guard !candidates.isEmpty else { return nil }
        let videos = candidates.filter { file in
            let name = file.path.lowercased()
            return videoExtensions.contains { name.hasSuffix($0) }
        }
        return (videos.isEmpty ? candidates : videos).max { $0.size < $1.size }
    }

    private static let videoExtensions = [
        ".mp4", ".mkv", ".webm", ".m4v", ".mov", ".avi", ".ts",
    ]
}

enum SoraError: LocalizedError {
    case invalidInput
    case noPlayableFile
    case engineUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            "Itu bukan magnet atau URL yang valid."
        case .noPlayableFile:
            "Torrent tidak berisi file video yang bisa diputar."
        case .engineUnavailable:
            "Engine belum dibangun. Jalankan scripts/build-apple.sh lebih dulu."
        }
    }
}

// MARK: - Player model

@MainActor
final class PlayerModel: ObservableObject {
    @Published var input = ""
    @Published var status = "Tempel magnet atau URL file video."
    @Published var busy = false

    let player = AVPlayer()
    private let engine = EngineClient()

    func play() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status = "Isi magnet atau URL dulu."
            return
        }

        busy = true
        status = text.lowercased().hasPrefix("magnet:")
            ? "Mengambil metadata torrent…"
            : "Membuka URL…"

        Task {
            do {
                let url = try await engine.playableURL(for: text)
                status = "Memutar \(url.lastPathComponent)"
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
            } catch {
                status = "Gagal: \(error.localizedDescription)"
            }
            busy = false
        }
    }

    func shutdown() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        Task { await engine.shutdown() }
    }
}

// MARK: - Engine bridge

#if canImport(NuvioEngine)
import NuvioEngine

/// Erases the difference between the real engine and the placeholder below so
/// the rest of the app compiles either way.
struct NuvioEngineHandle {
    private let engine: NuvioEngine

    static func create(dataDirectory: URL, cacheDirectory: URL) async throws -> NuvioEngineHandle {
        let configuration = NuvioEngineConfiguration(
            dataDirectory: dataDirectory,
            cacheDirectory: cacheDirectory
        )
        return NuvioEngineHandle(engine: try await NuvioEngine.create(configuration: configuration))
    }

    func addMagnet(_ magnet: String) async throws -> String {
        try await engine.addMagnet(magnet)
    }

    func files(_ torrentID: String) throws -> [NuvioTorrentFile] {
        try engine.files(for: torrentID)
    }

    /// Passes out `stream.url` from nuvio-engine, validated by the caller.
    func prepareStream(torrentID: String, fileIndex: UInt32, filenameHint: String) async throws -> URL {
        let stream = try await engine.prepareStream(
            torrentID: torrentID,
            fileIndex: fileIndex,
            filenameHint: filenameHint
        )
        return stream.url
    }

    func shutdown() async {
        await engine.shutdown()
    }
}

#else

/// Placeholder so the project still builds before the xcframework exists.
struct NuvioEngineHandle {
    static func create(dataDirectory: URL, cacheDirectory: URL) async throws -> NuvioEngineHandle {
        throw SoraError.engineUnavailable
    }

    func addMagnet(_ magnet: String) async throws -> String {
        throw SoraError.engineUnavailable
    }

    func files(_ torrentID: String) throws -> [NuvioTorrentFile] {
        throw SoraError.engineUnavailable
    }

    func prepareStream(torrentID: String, fileIndex: UInt32, filenameHint: String) async throws -> URL {
        throw SoraError.engineUnavailable
    }

    func shutdown() async {}
}

/// Mirrors the shape of `NuvioEngine.NuvioTorrentFile`.
struct NuvioTorrentFile {
    let index: UInt32
    let path: String
    let size: UInt64
}

#endif
