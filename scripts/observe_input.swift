import AppKit
import CoreGraphics
import Foundation

final class InputObserver {
  private var lastFrontmostApp: String?
  private var lastMouseLocation: CGPoint?
  private let mouseThreshold: CGFloat = 1

  func start() {
    emit([
      "kind": "observer_started",
      "pid": ProcessInfo.processInfo.processIdentifier,
      "message": "Watching frontmost app, cursor movement, and global input events.",
    ])

    logFrontmostIfNeeded(force: true)
    logMouseIfNeeded(force: true)

    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
      self?.logFrontmostIfNeeded(force: false)
      self?.logMouseIfNeeded(force: false)
    }
    RunLoop.main.add(timer, forMode: .common)

    let mask = eventMask([
      .mouseMoved,
      .leftMouseDown,
      .leftMouseUp,
      .rightMouseDown,
      .rightMouseUp,
      .otherMouseDown,
      .otherMouseUp,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
      .scrollWheel,
      .keyDown,
      .keyUp,
      .flagsChanged,
    ])

    guard let tap = CGEvent.tapCreate(
      tap: .cghidEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: mask,
      callback: { _, type, event, userInfo in
        guard let userInfo else {
          return Unmanaged.passUnretained(event)
        }
        let observer = Unmanaged<InputObserver>.fromOpaque(userInfo).takeUnretainedValue()
        observer.handle(eventType: type, event: event)
        return Unmanaged.passUnretained(event)
      },
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      emit([
        "kind": "error",
        "message": "Failed to create event tap. Check Input Monitoring / Accessibility permissions.",
      ])
      RunLoop.main.run()
      return
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    RunLoop.main.run()
  }

  private func handle(eventType: CGEventType, event: CGEvent) {
    var payload: [String: Any] = [
      "kind": "event",
      "event": eventName(for: eventType),
      "x": round(event.location.x),
      "y": round(event.location.y),
    ]

    if eventType == .leftMouseDown || eventType == .leftMouseUp ||
      eventType == .rightMouseDown || eventType == .rightMouseUp ||
      eventType == .otherMouseDown || eventType == .otherMouseUp
    {
      payload["clickState"] = event.getIntegerValueField(.mouseEventClickState)
      payload["buttonNumber"] = event.getIntegerValueField(.mouseEventButtonNumber)
    }

    if eventType == .scrollWheel {
      payload["deltaY"] = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
      payload["deltaX"] = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    }

    if eventType == .keyDown || eventType == .keyUp || eventType == .flagsChanged {
      payload["keyCode"] = event.getIntegerValueField(.keyboardEventKeycode)
    }

    emit(payload)
  }

  private func logFrontmostIfNeeded(force: Bool) {
    let frontmost = NSWorkspace.shared.frontmostApplication
    let name = frontmost?.localizedName ?? frontmost?.bundleIdentifier ?? "<unknown>"
    guard force || name != lastFrontmostApp else {
      return
    }
    lastFrontmostApp = name
    emit([
      "kind": "frontmost_app",
      "name": name,
      "bundleId": frontmost?.bundleIdentifier ?? "",
      "pid": frontmost?.processIdentifier ?? -1,
    ])
  }

  private func logMouseIfNeeded(force: Bool) {
    let point = NSEvent.mouseLocation
    guard force || shouldLogMouseMove(to: point) else {
      return
    }
    lastMouseLocation = point
    emit([
      "kind": "cursor",
      "x": round(point.x),
      "y": round(point.y),
    ])
  }

  private func shouldLogMouseMove(to point: CGPoint) -> Bool {
    guard let lastMouseLocation else {
      return true
    }
    let dx = abs(point.x - lastMouseLocation.x)
    let dy = abs(point.y - lastMouseLocation.y)
    return dx >= mouseThreshold || dy >= mouseThreshold
  }

  private func eventMask(_ eventTypes: [CGEventType]) -> CGEventMask {
    eventTypes.reduce(0) { partialResult, type in
      partialResult | (1 << type.rawValue)
    }
  }

  private func eventName(for type: CGEventType) -> String {
    switch type {
    case .mouseMoved: return "mouseMoved"
    case .leftMouseDown: return "leftMouseDown"
    case .leftMouseUp: return "leftMouseUp"
    case .rightMouseDown: return "rightMouseDown"
    case .rightMouseUp: return "rightMouseUp"
    case .otherMouseDown: return "otherMouseDown"
    case .otherMouseUp: return "otherMouseUp"
    case .leftMouseDragged: return "leftMouseDragged"
    case .rightMouseDragged: return "rightMouseDragged"
    case .otherMouseDragged: return "otherMouseDragged"
    case .scrollWheel: return "scrollWheel"
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    case .flagsChanged: return "flagsChanged"
    default: return "type_\(type.rawValue)"
    }
  }

  private func emit(_ payload: [String: Any]) {
    var line = payload
    line["ts"] = ISO8601DateFormatter().string(from: Date())
    guard JSONSerialization.isValidJSONObject(line),
      let data = try? JSONSerialization.data(withJSONObject: line, options: []),
      let text = String(data: data, encoding: .utf8)
    else {
      return
    }
    print(text)
    fflush(stdout)
  }
}

InputObserver().start()
