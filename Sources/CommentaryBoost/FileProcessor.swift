import AVFoundation

/// Runs the commentary chain over an audio file, faster than realtime. Handy for trying settings
/// on a recorded clip.
func processFile(input: URL, output: URL, chain: CommentaryChain) throws {
    let file = try AVAudioFile(forReading: input)
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)

    let player = AVAudioPlayerNode()
    let converter = AVAudioMixerNode()  // resamples and up-mixes the file to the chain's format
    engine.attach(player)
    engine.attach(converter)
    engine.connect(player, to: converter, format: file.processingFormat)
    chain.attach(to: engine, from: converter, to: engine.mainMixerNode, format: format)

    try engine.start()
    player.scheduleFile(file, at: nil)
    player.play()

    let out = try AVAudioFile(forWriting: output, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)!
    let duration = Double(file.length) / file.processingFormat.sampleRate
    let totalFrames = AVAudioFramePosition((duration + 0.5) * format.sampleRate)  // + tail for effect latency

    while engine.manualRenderingSampleTime < totalFrames {
        let remaining = AVAudioFrameCount(totalFrames - engine.manualRenderingSampleTime)
        let status = try engine.renderOffline(min(buffer.frameCapacity, remaining), to: buffer)
        if status == .success { try out.write(from: buffer) }
    }
    player.stop()
    engine.stop()
}
