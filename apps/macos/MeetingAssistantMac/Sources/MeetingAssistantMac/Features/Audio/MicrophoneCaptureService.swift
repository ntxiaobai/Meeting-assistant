import AVFoundation
import Foundation

final class MicrophoneCaptureService: AudioCaptureSource {
    enum CaptureError: LocalizedError {
        case unsupportedTargetFormat
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedTargetFormat:
                return "Microphone capture target format is not supported."
            case .converterCreationFailed:
                return "Failed to create audio converter for microphone capture."
            }
        }
    }

    var onPcm: (([Int16]) -> Void)?

    private let engine = AVAudioEngine()
    private var started = false
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    func start() async throws {
        guard !started else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.unsupportedTargetFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.converterCreationFailed
        }
        self.targetFormat = targetFormat
        self.converter = converter

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndEmit(buffer)
        }

        engine.prepare()
        try engine.start()
        started = true
    }

    func stop() async {
        guard started else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        targetFormat = nil
        started = false
    }

    private func convertAndEmit(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        guard buffer.frameLength > 0 else { return }

        let ratio = targetFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let estimatedFrameCount = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        let frameCapacity = max(estimatedFrameCount, 1)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var sourceBuffer: AVAudioPCMBuffer? = buffer
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if let source = sourceBuffer {
                outStatus.pointee = .haveData
                sourceBuffer = nil
                return source
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        switch status {
        case .haveData, .inputRanDry:
            emit(converted)
        case .error, .endOfStream:
            return
        @unknown default:
            return
        }
    }

    private func emit(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return }

        var output = [Int16]()
        output.reserveCapacity(frames)

        if let data = buffer.floatChannelData {
            for frameIndex in 0 ..< frames {
                var mix: Float = 0
                for channelIndex in 0 ..< channels {
                    mix += data[channelIndex][frameIndex]
                }
                mix /= Float(channels)
                let clamped = max(-1.0, min(1.0, mix))
                output.append(Int16(clamped * Float(Int16.max)))
            }
            onPcm?(output)
            return
        }

        if let data = buffer.int16ChannelData {
            for frameIndex in 0 ..< frames {
                var mix: Int32 = 0
                for channelIndex in 0 ..< channels {
                    mix += Int32(data[channelIndex][frameIndex])
                }
                mix /= Int32(channels)
                output.append(Int16(clamping: mix))
            }
            onPcm?(output)
        }
    }
}
