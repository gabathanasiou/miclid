import CoreAudio
import Foundation

enum DeviceRole: Equatable {
    case iphone
    case airpods
    case headset
    case builtIn
    case other
}

struct AudioDeviceInfo: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    let inputChannels: Int
    let outputChannels: Int

    var hasInput: Bool { inputChannels > 0 }

    var role: DeviceRole {
        if transport == kAudioDeviceTransportTypeContinuityCaptureWireless
            || transport == kAudioDeviceTransportTypeContinuityCaptureWired {
            return .iphone
        }
        if name.localizedCaseInsensitiveContains("AirPods") {
            return .airpods
        }
        if transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE {
            return hasInput ? .headset : .other
        }
        if transport == kAudioDeviceTransportTypeBuiltIn, hasInput {
            return .builtIn
        }
        return .other
    }
}

struct Conditions: Equatable {
    var externalDisplays: [String] = []
    var lidClosed = false
    var headset: AudioDeviceInfo?
    var iPhone: AudioDeviceInfo?
    var currentInput: AudioDeviceInfo?

    var hasExternalDisplay: Bool { !externalDisplays.isEmpty }
}
