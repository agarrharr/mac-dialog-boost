import AVFoundation
import AudioToolbox

/// leveler (compressor) -> voice isolation -> peak limiter
///
/// "Cars" is how much of the original mix is blended back in on top of the isolated voices:
/// 0% is commentary only, 100% is the untouched broadcast. The leveler runs first so the
/// car sound that gets blended back in has its loudest moments already squashed.
final class CommentaryChain {
    let isolation = AVAudioUnitEffect(audioComponentDescription: .apple(kAudioUnitSubType_AUSoundIsolation))
    let leveler = AVAudioUnitEffect(audioComponentDescription: .apple(kAudioUnitSubType_DynamicsProcessor))
    let limiter = AVAudioUnitEffect(audioComponentDescription: .apple(kAudioUnitSubType_PeakLimiter))

    var carsPercent: Float = 20 { didSet { carsPercent = min(max(carsPercent, 0), 100); apply() } }
    var highQuality = false { didSet { apply() } }
    var bypassed = false { didSet { apply() } }

    func attach(to engine: AVAudioEngine, from source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat) {
        for node in [isolation, leveler, limiter] { engine.attach(node) }
        engine.connect(source, to: leveler, format: format)
        engine.connect(leveler, to: isolation, format: format)
        engine.connect(isolation, to: limiter, format: format)
        engine.connect(limiter, to: destination, format: format)
        apply()
    }

    private func apply() {
        set(isolation, kAUSoundIsolationParam_WetDryMixPercent, 100 - carsPercent)
        set(isolation, kAUSoundIsolationParam_SoundToIsolate,
            highQuality ? Float(kAUSoundIsolationSoundType_HighQualityVoice) : Float(kAUSoundIsolationSoundType_Voice))

        // Even out the commentators and squash sudden loud moments (starts, crashes, onboards).
        set(leveler, kDynamicsProcessorParam_Threshold, -26)
        set(leveler, kDynamicsProcessorParam_HeadRoom, 8)
        set(leveler, kDynamicsProcessorParam_AttackTime, 0.003)
        set(leveler, kDynamicsProcessorParam_ReleaseTime, 0.15)
        set(leveler, kDynamicsProcessorParam_OverallGain, 6)

        // Makeup gain: removing the cars leaves things ~8 dB quieter than the original broadcast.
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
