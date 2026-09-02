//
//  FrameSink.swift
//  Calisthenics Vision
//
//  Thread-safe handoff between the capture queue and the rest of the app.
//
//  Capture callbacks arrive on a background queue while the main actor is
//  free to swap the handler at any moment (attaching or detaching pose
//  detection). Reading an unsynchronized closure reference there is a data
//  race, and a released closure invoked mid-swap crashes with SIGSEGV — this
//  box exists so that can't happen.
//

import CoreMedia
import Foundation

nonisolated final class FrameSink: @unchecked Sendable {

    private let lock = NSLock()
    private var handler: (@Sendable (CMSampleBuffer, Int) -> Void)?

    func setHandler(_ handler: (@Sendable (CMSampleBuffer, Int) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    /// Delivers a frame to the current handler.
    ///
    /// The handler is copied under the lock and invoked outside it: holding a
    /// lock across pose inference would serialize the capture queue against
    /// the main actor and stall capture.
    func deliver(_ sampleBuffer: CMSampleBuffer, timestampMs: Int) {
        lock.lock()
        let handler = self.handler
        lock.unlock()

        handler?(sampleBuffer, timestampMs)
    }
}
