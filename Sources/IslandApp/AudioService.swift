import Foundation
import CoreAudio

struct AudioSnapshot {
    var volume: Float
    var muted: Bool
    var name: String
    var device: AudioDeviceID
}

enum AudioService {
    static func snapshot() -> AudioSnapshot? {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        var nameRef: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address = .init(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let nameStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &nameRef)
        let name: String
        if nameStatus == noErr, let nameRef { name = nameRef.takeRetainedValue() as String }
        else { name = "Аудиоустройство" }
        var volume: Float32 = 0
        var hasVolume = false
        // Some output devices expose only per-channel volume.
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            address = .init(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr { hasVolume = true; break }
        }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = .init(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return AudioSnapshot(volume: hasVolume ? volume : -1, muted: muted != 0, name: name, device: device)
    }
}
