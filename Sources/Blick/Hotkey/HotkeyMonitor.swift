import AppKit
import Carbon.HIToolbox
import BlickCore

/// Four-character tag ("BLCK") identifying our registration with the system.
private let hotKeySignature: OSType = 0x424C_434B

/// Watches for the global shortcut going down and coming back up.
///
/// Ordinary shortcuts go through the system hot-key service, which needs no
/// permission. Shortcuts it cannot express (a modifier on its own, a specific
/// left or right key, fn) are recognised from the raw keyboard event stream,
/// which macOS only hands over once the user allows Input Monitoring.
@MainActor
final class HotkeyMonitor: ObservableObject {
    enum Status: Equatable {
        case inactive
        case active
        /// Waiting for the user to allow Input Monitoring.
        case needsInputMonitoring
        /// Another app already owns this combination.
        case unavailable
    }

    @Published private(set) var status: Status = .inactive
    @Published private(set) var shortcut: Shortcut

    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onCancel: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var tracker: ShortcutTracker
    private var permissionTimer: Timer?
    private var isPaused = false
    private var hasPromptedForAccess = false

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        tracker = ShortcutTracker(shortcut: shortcut)
    }

    func start() {
        install()
    }

    func apply(_ newShortcut: Shortcut) {
        guard newShortcut != shortcut || status == .inactive else { return }
        shortcut = newShortcut
        tracker = ShortcutTracker(shortcut: newShortcut)
        if !isPaused { install() }
    }

    /// Stops listening while a new shortcut is being recorded, so pressing the
    /// current one does not open the overlay.
    func pause() {
        isPaused = true
        uninstall()
        status = .inactive
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        install()
    }

    /// Asks macOS for Input Monitoring. The system shows its prompt only once;
    /// after that the user has to flip the switch in System Settings.
    func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() {
            if hasPromptedForAccess {
                SystemSettings.openInputMonitoring()
            } else {
                hasPromptedForAccess = true
                CGRequestListenEventAccess()
            }
        }
        install()
    }

    // MARK: - Installation

    private func install() {
        uninstall()
        guard shortcut.isValid else {
            status = .inactive
            return
        }
        if shortcut.requiresEventTap {
            installEventTap()
        } else {
            installHotKey()
        }
    }

    private func uninstall() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
            self.tapSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func installHotKey() {
        guard let keyCode = shortcut.keyCode else { return }
        let specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 2, specs, context, &handlerRef)

        let id = EventHotKeyID(signature: hotKeySignature, id: 1)
        let result = RegisterEventHotKey(
            UInt32(keyCode), shortcut.carbonModifiers, id, GetEventDispatcherTarget(), 0, &hotKeyRef
        )
        status = result == noErr ? .active : .unavailable
    }

    private func installEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard CGPreflightListenEventAccess(),
              let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: eventTapHandler,
                userInfo: context
              )
        else {
            status = .needsInputMonitoring
            waitForPermission()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        tapSource = source
        tracker = ShortcutTracker(shortcut: shortcut)
        status = .active
    }

    /// Picks the shortcut up as soon as access is granted, without a relaunch.
    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            onMainActor {
                guard let self, self.status == .needsInputMonitoring else { return }
                if CGPreflightListenEventAccess() { self.install() }
            }
        }
    }

    // MARK: - Events

    fileprivate func hotKeyChanged(pressed: Bool) {
        if pressed {
            onDown?()
        } else {
            onUp?()
        }
    }

    fileprivate func tapEvent(type: CGEventType, keyCode: UInt16, flags: UInt64, isRepeat: Bool) {
        let input: ShortcutTracker.Input
        switch type {
        case .keyDown:
            input = .keyDown(keyCode: keyCode, rawFlags: flags, isRepeat: isRepeat)
        case .keyUp:
            input = .keyUp(keyCode: keyCode, rawFlags: flags)
        case .flagsChanged:
            input = .flagsChanged(rawFlags: flags)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches a tap off if it ever responds slowly.
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        default:
            return
        }
        switch tracker.handle(input) {
        case .pressed: onDown?()
        case .released: onUp?()
        case .cancelled: onCancel?()
        case nil: break
        }
    }
}

private func hotKeyHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr, id.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }

    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
    onMainActor { monitor.hotKeyChanged(pressed: pressed) }
    return noErr
}

private func eventTapHandler(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ context: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let context {
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags.rawValue
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
        onMainActor { monitor.tapEvent(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat) }
    }
    return Unmanaged.passUnretained(event)
}
