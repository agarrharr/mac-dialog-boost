import AVFoundation
import AudioToolbox

/// leveler (compressor) -> voice isolation -> peak limiter
///
/// "Background" is how much of the original mix is blended back in on top of the isolated voices:
/// 0% is voices only, 100% is the untouched original. The leveler runs first so the
/// background that gets blended back in has its loudest moments already squashed.
final class DialogChain {
    let isolation = AVAudioUnitEffect(audioComponentDescription: .apple(kAudioUnitSubType_AUSoundIsolation))
    let leveler = AVAudioUnitEffect(audioComponentDescription: .apple(kAudioUnitSubType_DynamicsProcessor))
    let limiter = AVAudioUnitEffect(audioComponentDescription: .apple(kAudioUnitSubType_PeakLimiter))

    var backgroundPercent: Float = 20 { didSet { backgroundPercent = min(max(backgroundPercent, 0), 100); apply() } }
    var highQuality = false { didSet { apply() } }
    var bypassed = false { didSet { apply() } }

    var nodes: [AVAudioNode] { [leveler, isolation, limiter] }

    func attach(to engine: AVAudioEngine, from source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat) {
        for node in nodes { engine.attach(node) }
        engine.connect(source, to: leveler, format: format)
        engine.connect(leveler, to: isolation, format: format)
        engine.connect(isolation, to: limiter, format: format)
        engine.connect(limiter, to: destination, format: format)
        apply()
    }

    private func apply() {
        set(isolation, kAUSoundIsolationParam_WetDryMixPercent, 100 - backgroundPercent)
        set(isolation, kAUSoundIsolationParam_SoundToIsolate,
            highQuality ? Float(kAUSoundIsolationSoundType_HighQualityVoice) : Float(kAUSoundIsolationSoundType_Voice))

        // Even out the commentators and squash sudden loud moments (starts, crashes, onboards).
        set(leveler, kDynamicsProcessorParam_Threshold, -26)
        set(leveler, kDynamicsProcessorParam_HeadRoom, 8)
        set(leveler, kDynamicsProcessorParam_AttackTime, 0.003)
        set(leveler, kDynamicsProcessorParam_ReleaseTime, 0.15)
        set(leveler, kDynamicsProcessorParam_OverallGain, 6)

        // Makeup gain: removing the background leaves things ~8 dB quieter than the original.
        set(limiter, kLimiterParam_PreGain, bypassed ? 0 : 8)
        set(limiter, kLimiterParam_AttackTime, 0.004)
        set(limiter, kLimiterParam_DecayTime, 0.05)

        isolation.bypass = bypassed
        leveler.bypass = bypassed
    }

    private func set(_ effect: AVAudioUnitEffect, _ parameter: AudioUnitParameterID, _ value: Float) {
        AudioUnitSetParameter(effect.audioUnit, parameter, kAudioUnitScope_Global, 0, value, 0)
    }
}

extension AudioComponentDescription {
    static func apple(_ subType: OSType) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}
