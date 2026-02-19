import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCaptureService: NSObject, AudioCaptureSource {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screen recording permission is required for system audio capture."
            case .noDisplay:
                return "No display is available for ScreenCaptureKit audio capture."
            }
        }
    }

    var onPcm: (([Int16]) -> Void)?

    private let queue = DispatchQueue(label: "meeting-assistant.system-audio", qos: .userInitiated)
    private var stream: SCStream?
}

extension SystemAudioCaptureService {
    static func hasScreenPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func start() async throws {
        guard Self.hasScreenPermission() || Self.requestScreenPermission() else {
            throw CaptureError.permissionDenied
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }
}

extension SystemAudioCaptureService: SCStreamOutput {
    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else {
            return
        }

        guard let pcm = Self.convertToInt16(sampleBuffer), !pcm.isEmpty else {
            return
        }

        onPcm?(pcm)
    }
}

private extension SystemAudioCaptureService {
    static func convertToInt16(_ sampleBuffer: CMSampleBuffer) -> [Int16]? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        let asbd = asbdPointer.pointee
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = max(Int(asbd.mChannelsPerFrame), 1)

        var blockBuffer: CMBlockBuffer?
        var bufferListSizeNeeded = 0

        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            return nil
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        let audioBufferListPointer = raw.assumingMemoryBound(to: AudioBufferList.self)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPointer,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            return nil
        }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(audioBufferListPointer)
        guard let first = audioBuffers.first, first.mDataByteSize > 0 else {
            return nil
        }

        if isFloat {
            if isNonInterleaved {
                return convertFloatNonInterleaved(audioBuffers: audioBuffers)
            }
            return convertFloatInterleaved(audioBuffers: audioBuffers, channels: channels)
        }

        if isNonInterleaved {
            return convertInt16NonInterleaved(audioBuffers: audioBuffers)
        }
        return convertInt16Interleaved(audioBuffers: audioBuffers, channels: channels)
    }

    static func convertFloatNonInterleaved(audioBuffers: UnsafeMutableAudioBufferListPointer) -> [Int16]? {
        let channels = audioBuffers.count
        guard channels > 0 else { return nil }

        guard let first = audioBuffers.first,
              first.mData != nil
        else {
            return nil
        }

        let frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard frameCount > 0 else { return nil }

        var output = [Int16](repeating: 0, count: frameCount)
        for frame in 0 ..< frameCount {
            var mixed: Float = 0
            for channel in 0 ..< channels {
                guard let data = audioBuffers[channel].mData else { continue }
                let ptr = data.bindMemory(to: Float.self, capacity: frameCount)
                mixed += ptr[frame]
            }
            mixed /= Float(channels)
            let clamped = max(-1.0, min(1.0, mixed))
            output[frame] = Int16(clamped * Float(Int16.max))
        }

        return output
    }

    static func convertFloatInterleaved(
        audioBuffers: UnsafeMutableAudioBufferListPointer,
        channels: Int
    ) -> [Int16]? {
        guard let first = audioBuffers.first,
              let data = first.mData
        else {
            return nil
        }

        let sampleCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return nil }

        let frameCount = max(sampleCount / channels, 0)
        let ptr = data.bindMemory(to: Float.self, capacity: sampleCount)
        var output = [Int16](repeating: 0, count: frameCount)

        for frame in 0 ..< frameCount {
            var mixed: Float = 0
            for channel in 0 ..< channels {
                mixed += ptr[frame * channels + channel]
            }
            mixed /= Float(channels)
            let clamped = max(-1.0, min(1.0, mixed))
            output[frame] = Int16(clamped * Float(Int16.max))
        }

        return output
    }

    static func convertInt16NonInterleaved(audioBuffers: UnsafeMutableAudioBufferListPointer) -> [Int16]? {
        let channels = audioBuffers.count
        guard channels > 0 else { return nil }

        guard let first = audioBuffers.first,
              first.mData != nil
        else {
            return nil
        }

        let frameCount = Int(first.mDataByteSize) / MemoryLayout<Int16>.size
        guard frameCount > 0 else { return nil }

        var output = [Int16](repeating: 0, count: frameCount)
        for frame in 0 ..< frameCount {
            var mixed: Int32 = 0
            for channel in 0 ..< channels {
                guard let data = audioBuffers[channel].mData else { continue }
                let ptr = data.bindMemory(to: Int16.self, capacity: frameCount)
                mixed += Int32(ptr[frame])
            }
            mixed /= Int32(channels)
            output[frame] = Int16(clamping: mixed)
        }

        return output
    }

    static func convertInt16Interleaved(
        audioBuffers: UnsafeMutableAudioBufferListPointer,
        channels: Int
    ) -> [Int16]? {
        guard let first = audioBuffers.first,
              let data = first.mData
        else {
            return nil
        }

        let sampleCount = Int(first.mDataByteSize) / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return nil }

        let frameCount = max(sampleCount / channels, 0)
        let ptr = data.bindMemory(to: Int16.self, capacity: sampleCount)
        var output = [Int16](repeating: 0, count: frameCount)

        for frame in 0 ..< frameCount {
            var mixed: Int32 = 0
            for channel in 0 ..< channels {
                mixed += Int32(ptr[frame * channels + channel])
            }
            mixed /= Int32(channels)
            output[frame] = Int16(clamping: mixed)
        }

        return output
    }
}
