//
//  TelemetryStore.swift
//  Calisthenics Vision
//
//  Per-frame landmark logging.
//
//  Why a flat file rather than a database table: pose runs at 30–60 FPS and
//  emits 33 landmarks per frame, so a row-per-frame table would mean thousands
//  of inserts per second while the CPU is already busy with inference. Fixed-
//  size records in a flat file make writes a straight append, and let the
//  review scrubber jump to a timestamp with a seek instead of a query
//  (SPEC.md §3, "frame-accurate scrubbing").
//
//  Layout:  [ 8-byte header ][ frame ][ frame ]…
//  Header:  magic "CVT1" (4) · landmarkCount UInt16 (2) · reserved (2)
//  Frame:   timestampMs Int32 (4) · landmarkCount × (x, y, z) Float32
//

import Foundation

enum Telemetry {
    static let magic: [UInt8] = Array("CVT1".utf8)
    static let headerSize = 8
    static let landmarkCount = 33
    /// 4-byte timestamp + 33 landmarks × 3 axes × 4 bytes = 400 bytes.
    static var frameSize: Int { 4 + landmarkCount * 3 * 4 }
}

/// One frame of pose telemetry.
struct TelemetryFrame {
    let timestampMs: Int32
    /// Flattened `[x, y, z]` per landmark, normalized to the image.
    let values: [Float]
}

// MARK: - Writing

/// Appends frames during a session. Called from the capture queue.
nonisolated final class TelemetryWriter {

    let fileName: String
    private let handle: FileHandle
    private var buffer = Data()
    /// Flush every ~2 seconds of capture rather than per frame.
    private let flushThreshold = Telemetry.frameSize * 60

    init(sessionID: UUID) throws {
        fileName = "\(sessionID.uuidString).cvt"
        let url = MediaLibrary.telemetryDirectory.appending(path: fileName)

        var header = Data(Telemetry.magic)
        withUnsafeBytes(of: UInt16(Telemetry.landmarkCount).littleEndian) {
            header.append(contentsOf: $0)
        }
        header.append(contentsOf: [0, 0])   // reserved

        try header.write(to: url, options: .atomic)
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    /// - Parameter values: flattened x/y/z, `landmarkCount * 3` long.
    func append(timestampMs: Int, values: [Float]) {
        guard values.count == Telemetry.landmarkCount * 3 else { return }

        withUnsafeBytes(of: Int32(timestampMs).littleEndian) {
            buffer.append(contentsOf: $0)
        }
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) {
                buffer.append(contentsOf: $0)
            }
        }

        if buffer.count >= flushThreshold { flush() }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        try? handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    func finish() {
        flush()
        try? handle.close()
    }
}

// MARK: - Reading

/// Random access over a recorded telemetry file.
struct TelemetryReader {

    private let data: Data
    let frameCount: Int

    init?(url: URL) {
        // Mapped rather than loaded: a long session's telemetry shouldn't have
        // to sit in memory just to scrub through it.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= Telemetry.headerSize,
              Array(data.prefix(4)) == Telemetry.magic
        else { return nil }

        self.data = data
        self.frameCount = (data.count - Telemetry.headerSize) / Telemetry.frameSize
    }

    func frame(at index: Int) -> TelemetryFrame? {
        guard index >= 0, index < frameCount else { return nil }

        let start = Telemetry.headerSize + index * Telemetry.frameSize
        let timestamp = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: start, as: Int32.self).littleEndian
        }

        var values = [Float]()
        values.reserveCapacity(Telemetry.landmarkCount * 3)
        for i in 0..<(Telemetry.landmarkCount * 3) {
            let offset = start + 4 + i * 4
            let bits = data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
            values.append(Float(bitPattern: bits))
        }

        return TelemetryFrame(timestampMs: timestamp, values: values)
    }

    /// Nearest frame at or before `timestampMs`. Binary search, since frames
    /// are written in capture order.
    func frame(nearest timestampMs: Int32) -> TelemetryFrame? {
        guard frameCount > 0 else { return nil }

        var low = 0
        var high = frameCount - 1
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            guard let candidate = frame(at: mid) else { break }

            if candidate.timestampMs <= timestampMs {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return frame(at: best)
    }
}
