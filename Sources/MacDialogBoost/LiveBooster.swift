import AVFoundation
import CoreAudio

/// Runs the dialog chain on the Mac's live audio.
///
/// The aggregate device's IO callback hands us the tapped system audio and the speaker buffers in
/// one call; we render the chain synchronously in between using AVAudioEngine's realtime manual
/// rendering mode, so there is no extra buffering beyond what the effects themselves add.
final class LiveBooster {
    let chain: DialogChain
    private let tap: SystemAudioTap
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let maxFrames: AVAudioFrameCount = 4096
    private let inputLeft: UnsafeMutablePointer<Float>
    private let inputRight: UnsafeMutablePointer<Float>
    private let outputBuffer: AVAudioPCMBuffer
    private var ioProcID: AudioDeviceIOProcID?

    /// Peak levels since the UI last read them (written on the audio thread).
    var inputPeak: Float = 0
    var outputPeak: Float = 0
    var callbackCount = 0
    var inputLayout = ""

    /// Set on the audio thread once any non-silent input arrives. Without the System Audio
    /// Recording permission the tap only ever delivers exact zeros.
    private(set) var heardAudio = false
    /// True once the original sound is muted and we are playing the processed version instead.
    /// Until then the original plays as normal and our output stays silent.
    private(set) var isActive = false

    /// Called from the UI timer: swaps the original sound for ours once we know we can hear it.
    func activateIfReady() throws {
        guard heardAudio, !isActive else { return }
        try tap.setMuted(true)
        isActive = true
    }

    var outputName: String { tap.outputName }

    init(chain: DialogChain) throws {
        self.chain = chain
        tap = try SystemAudioTap()
        format = AVAudioFormat(standardFormatWithSampleRate: tap.sampleRate, channels: 2)!
        inputLeft = .allocate(capacity: Int(maxFrames))
        inputRight = .allocate(capacity: Int(maxFrames))
        outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames)!
    }

    deinit {
        stop()
        inputLeft.deallocate()
        inputRight.deallocate()
    }

    func start() throws {
        try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: maxFrames)

        let left = inputLeft, right = inputRight
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let bytes = Int(frameCount) * MemoryLayout<Float>.size
            for (index, buffer) in buffers.enumerated() {
                memcpy(buffer.mData, index == 0 ? left : right, bytes)
            }
            return noErr
        }
        engine.attach(source)
        chain.attach(to: engine, from: source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()

        let render = engine.manualRenderingBlock
        let output = outputBuffer
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, tap.aggregateID, nil) { [unowned self] _, input, _, devOutput, _ in
            let outBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: devOutput))
            guard let first = outBuffers.first, first.mNumberChannels > 0 else { return }
            let frames = min(Int(first.mDataByteSize) / (MemoryLayout<Float>.size * Int(first.mNumberChannels)), Int(maxFrames))

            let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            callbackCount += 1
            if callbackCount == 1 {
                inputLayout = "in " + inBuffers.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)B" }.joined(separator: ",")
                    + " out " + outBuffers.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)B" }.joined(separator: ",")
            }
            copyChannel(from: inBuffers, channel: 0, frames: frames, to: left)
            copyChannel(from: inBuffers, channel: 1, frames: frames, to: right)
            inputPeak = max(inputPeak, peak(left, frames), peak(right, frames))
            if inputPeak > 0 { heardAudio = true }

            output.frameLength = AVAudioFrameCount(frames)
            var status: OSStatus = noErr
            let result = render(AVAudioFrameCount(frames), output.mutableAudioBufferList, &status)
            guard isActive, result == .success, let channels = output.floatChannelData else {
                for buffer in outBuffers { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
                return
            }
            outputPeak = max(outputPeak, peak(channels[0], frames), peak(channels[1], frames))
            writeStereo(channels[0], channels[1], frames: frames, to: outBuffers)
        }, "Installing the audio callback")
        try check(AudioDeviceStart(tap.aggregateID, ioProcID), "Starting audio")
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(tap.aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(tap.aggregateID, ioProcID)
            self.ioProcID = nil
        }
        engine.stop()
        tap.invalidate()
    }
}

/// Copies one channel (counted across all buffers, which may be interleaved) into `destination`.
/// A mono source fills both channels; a missing source is silence.
private func copyChannel(from buffers: UnsafeMutableAudioBufferListPointer, channel: Int, frames: Int, to destination: UnsafeMutablePointer<Float>) {
    let totalChannels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    guard totalChannels > 0 else {
        destination.update(repeating: 0, count: frames)
        return
    }
    var wanted = min(channel, totalChannels - 1)
    for buffer in buffers {
        let stride = Int(buffer.mNumberChannels)
        if wanted < stride, let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
            let available = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * stride)
            for frame in 0..<frames { destination[frame] = frame < available ? data[frame * stride + wanted] : 0 }
            return
        }
        wanted -= stride
    }
    destination.update(repeating: 0, count: frames)
}

/// Writes left/right into the first two output channels and silences any others.
private func writeStereo(_ left: UnsafePointer<Float>, _ right: UnsafePointer<Float>, frames: Int, to buffers: UnsafeMutableAudioBufferListPointer) {
    var channelBase = 0
    for buffer in buffers {
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let stride = Int(buffer.mNumberChannels)
        let available = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * max(stride, 1)))
        for c in 0..<stride {
            let source: UnsafePointer<Float>? = switch channelBase + c {
            case 0: left
            case 1: right
            default: nil
            }
            for frame in 0..<available { data[frame * stride + c] = source?[frame] ?? 0 }
        }
        channelBase += stride
    }
}

private func peak(_ samples: UnsafePointer<Float>, _ count: Int) -> Float {
    var result: Float = 0
    for i in 0..<count { result = max(result, abs(samples[i])) }
    return result
}
