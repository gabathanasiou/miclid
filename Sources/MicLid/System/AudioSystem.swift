import CoreAudio
import Foundation

final class AudioSystem {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue.main

    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?

    var onDevicesChanged: (() -> Void)?
    var onDefaultInputChanged: (() -> Void)?

    // MARK: - Queries

    func devices() -> [AudioDeviceInfo] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var identifiers = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &identifiers) == noErr else {
            return []
        }

        return identifiers.compactMap(info(for:))
    }

    func defaultInputID() -> AudioDeviceID? {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var identifier = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &identifier)
        return status == noErr ? identifier : nil
    }

    func currentInput() -> AudioDeviceInfo? {
        guard let identifier = defaultInputID() else { return nil }
        return info(for: identifier)
    }

    func setDefaultInput(_ identifier: AudioDeviceID) -> Bool {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var value = identifier
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(systemObject, &address, 0, nil, size, &value)
        if status != noErr {
            Log.error("Setting the default input device failed with status \(status)")
        }
        return status == noErr
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard devicesListener == nil else { return }

        var devicesAddress = Self.address(kAudioHardwarePropertyDevices)
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onDevicesChanged?()
        }
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, listenerQueue, devicesBlock)
        devicesListener = devicesBlock

        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onDefaultInputChanged?()
        }
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultAddress, listenerQueue, defaultBlock)
        defaultInputListener = defaultBlock
    }

    func stopMonitoring() {
        if let devicesListener {
            var address = Self.address(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, listenerQueue, devicesListener)
            self.devicesListener = nil
        }
        if let defaultInputListener {
            var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, listenerQueue, defaultInputListener)
            self.defaultInputListener = nil
        }
    }

    // MARK: - Device properties

    private func info(for identifier: AudioDeviceID) -> AudioDeviceInfo? {
        guard let uid = stringProperty(identifier, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = stringProperty(identifier, kAudioObjectPropertyName) ?? uid
        return AudioDeviceInfo(
            id: identifier,
            uid: uid,
            name: name,
            transport: transport(identifier),
            inputChannels: channelCount(identifier, scope: kAudioObjectPropertyScopeInput),
            outputChannels: channelCount(identifier, scope: kAudioObjectPropertyScopeOutput)
        )
    }

    private func stringProperty(_ identifier: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(identifier, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func transport(_ identifier: AudioDeviceID) -> UInt32 {
        var address = Self.address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(identifier, &address, 0, nil, &size, &value)
        return status == noErr ? value : 0
    }

    private func channelCount(_ identifier: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(identifier, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let buffers = AudioBufferList.allocate(
            maximumBuffers: max(1, Int(size) / MemoryLayout<AudioBuffer>.size)
        )
        defer { free(buffers.unsafeMutablePointer) }

        var dataSize = size
        guard AudioObjectGetPropertyData(identifier, &address, 0, nil, &dataSize, buffers.unsafeMutablePointer) == noErr else {
            return 0
        }

        return (0..<Int(buffers.count)).reduce(0) { total, index in
            total + Int(buffers[index].mNumberChannels)
        }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
}
