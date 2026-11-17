import CoreAudio
import XCTest
@testable import MicLid

final class DeciderTests: XCTestCase {
    private func device(
        _ id: AudioDeviceID,
        _ name: String,
        _ transport: UInt32,
        input: Int = 1
    ) -> AudioDeviceInfo {
        AudioDeviceInfo(id: id, uid: "\(name)-uid", name: name, transport: transport, inputChannels: input, outputChannels: 0)
    }

    private var builtIn: AudioDeviceInfo { device(1, "MacBook Pro Microphone", kAudioDeviceTransportTypeBuiltIn) }
    private var iPhone: AudioDeviceInfo { device(2, "iPhone Microphone", kAudioDeviceTransportTypeContinuityCaptureWireless) }
    private var airPods: AudioDeviceInfo { device(3, "AirPods Pro", kAudioDeviceTransportTypeBluetooth) }

    private func conditions(
        display: Bool = true,
        lid: Bool = true,
        headset: AudioDeviceInfo? = nil,
        iPhone: AudioDeviceInfo? = nil,
        current: AudioDeviceInfo?
    ) -> Conditions {
        Conditions(
            externalDisplays: display ? ["BenQ EX2780Q"] : [],
            lidClosed: lid,
            headset: headset,
            iPhone: iPhone,
            currentInput: current
        )
    }

    func testRecommendsInClamshellWithExternalDisplay() {
        let subject = conditions(iPhone: iPhone, current: builtIn)
        XCTAssertTrue(Decider.shouldRecommend(subject))
    }

    func testDoesNotRecommendWithLidOpen() {
        XCTAssertFalse(Decider.shouldRecommend(conditions(lid: false, iPhone: iPhone, current: builtIn)))
    }

    func testDoesNotRecommendWithoutExternalDisplay() {
        XCTAssertFalse(Decider.shouldRecommend(conditions(display: false, iPhone: iPhone, current: builtIn)))
    }

    func testDoesNotRecommendWithHeadsetConnected() {
        XCTAssertFalse(Decider.shouldRecommend(conditions(headset: airPods, iPhone: iPhone, current: builtIn)))
    }

    func testDoesNotRecommendWithoutIPhoneMic() {
        XCTAssertFalse(Decider.shouldRecommend(conditions(current: builtIn)))
    }

    func testDoesNotRecommendWhenAnotherInputIsChosen() {
        let teams = device(4, "Microsoft Teams Audio", kAudioDeviceTransportTypeVirtual)
        XCTAssertFalse(Decider.shouldRecommend(conditions(iPhone: iPhone, current: teams)))
    }

    func testEnvironmentSurvivesInputChange() {
        // Environment is about the setup, not which device is selected.
        XCTAssertTrue(Decider.environmentSatisfied(conditions(iPhone: iPhone, current: iPhone)))
    }

    func testToggleFromIPhoneGoesToAirPods() {
        let result = Decider.toggleDestination(current: iPhone, devices: [builtIn, iPhone, airPods])
        XCTAssertEqual(result, .switchTo(airPods.id))
    }

    func testToggleFromIPhoneFallsBackToBuiltInWithoutAirPods() {
        let result = Decider.toggleDestination(current: iPhone, devices: [builtIn, iPhone])
        XCTAssertEqual(result, .switchTo(builtIn.id))
    }

    func testToggleFromAirPodsGoesToIPhone() {
        let result = Decider.toggleDestination(current: airPods, devices: [builtIn, iPhone, airPods])
        XCTAssertEqual(result, .switchTo(iPhone.id))
    }

    func testToggleFromBuiltInGoesToIPhone() {
        let result = Decider.toggleDestination(current: builtIn, devices: [builtIn, iPhone, airPods])
        XCTAssertEqual(result, .switchTo(iPhone.id))
    }

    func testToggleFromOtherGoesToIPhone() {
        let teams = device(4, "Microsoft Teams Audio", kAudioDeviceTransportTypeVirtual)
        let result = Decider.toggleDestination(current: teams, devices: [builtIn, iPhone, teams])
        XCTAssertEqual(result, .switchTo(iPhone.id))
    }

    func testToggleWithOnlyOneDeviceShowsMenu() {
        let result = Decider.toggleDestination(current: builtIn, devices: [builtIn])
        XCTAssertEqual(result, .showMenu)
    }
}
