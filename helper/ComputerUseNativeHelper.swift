import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class OverlayCursorView: NSView {
  private let drawingInset = CGPoint(x: 6, y: 6)
  private let scaleAnchor = CGPoint(x: 12, y: 27)

  var pulseAlpha: CGFloat = 0 {
    didSet {
      needsDisplay = true
    }
  }

  var cursorScale: CGFloat = 1 {
    didSet {
      needsDisplay = true
    }
  }

  var pressed: Bool = false {
    didSet {
      needsDisplay = true
    }
  }

  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: scaleAnchor.x, yBy: scaleAnchor.y)
    transform.scale(by: cursorScale)
    transform.translateX(by: -scaleAnchor.x, yBy: -scaleAnchor.y)
    transform.concat()

    let pulseRect = NSRect(x: 2 + drawingInset.x, y: 5 + drawingInset.y, width: 28, height: 28)
    if pulseAlpha > 0.01 {
      let pulse = NSBezierPath(ovalIn: pulseRect.insetBy(dx: -3, dy: -3))
      NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: pulseAlpha * 0.18).setFill()
      pulse.fill()

      NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: pulseAlpha * 0.45).setStroke()
      pulse.lineWidth = 1.2
      pulse.stroke()
    }

    let shadowPath = roundedPointerPath(inset: 1.0)

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowBlurRadius = pressed ? 9 : 10
    glow.shadowOffset = NSSize(width: 0, height: 0)
    glow.shadowColor = NSColor(calibratedWhite: 1.0, alpha: pressed ? 0.44 : 0.34)
    glow.set()
    NSColor(calibratedWhite: 1.0, alpha: 0.24).setStroke()
    shadowPath.lineWidth = 4.2
    shadowPath.lineJoinStyle = .round
    shadowPath.lineCapStyle = .round
    shadowPath.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let arrow = roundedPointerPath(inset: 0)

    let fillAlpha: CGFloat = pressed ? 0.34 : 0.28
    NSColor(calibratedWhite: 0.72, alpha: fillAlpha).setFill()
    arrow.fill()

    NSColor(calibratedWhite: 1.0, alpha: pressed ? 0.94 : 0.86).setStroke()
    arrow.lineWidth = pressed ? 2.2 : 2.0
    arrow.lineJoinStyle = .round
    arrow.lineCapStyle = .round
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
  }

  private func roundedPointerPath(inset: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let scale = (22.0 - (inset * 2.0)) / 39.0
    let offsetX = drawingInset.x + inset
    let offsetY = drawingInset.y + inset
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
      NSPoint(x: offsetX + (x * scale), y: offsetY + ((39.0 - y) * scale))
    }

    path.move(to: point(6.5338, 33.7802))
    path.line(to: point(0.617737, 6.56569))
    path.curve(
      to: point(6.53598, 0.611297),
      controlPoint1: point(-0.152622, 3.02196),
      controlPoint2: point(2.98763, -0.137475)
    )
    path.line(to: point(33.93, 6.39198))
    path.curve(
      to: point(35.1843, 15.7308),
      controlPoint1: point(38.5345, 7.36361),
      controlPoint2: point(39.3692, 13.5787)
    )
    path.line(to: point(23.7471, 21.6122))
    path.curve(
      to: point(21.5782, 23.7895),
      controlPoint1: point(22.8135, 22.0923),
      controlPoint2: point(22.0547, 22.854)
    )
    path.line(to: point(15.8751, 34.9872))
    path.curve(
      to: point(6.5338, 33.7802),
      controlPoint1: point(13.7419, 39.1757),
      controlPoint2: point(7.53229, 38.3733)
    )
    path.close()

    return path
  }
}

final class OverlayCursorController {
  static let shared = OverlayCursorController()

  private let size = CGSize(width: 40, height: 38)
  private let hotspot = CGPoint(x: 12, y: 27)
  private let idleHideDelay: TimeInterval = 1.5
  private let overlayQueue = DispatchQueue(label: "computer-use.overlay")
  private var window: NSWindow?
  private var view: OverlayCursorView? {
    window?.contentView as? OverlayCursorView
  }
  private var currentPoint: CGPoint?
  private var hideWorkItem: DispatchWorkItem?
  private var targetWindowID: CGWindowID?
  private var targetWindowLevel: NSWindow.Level = .normal

  private init() {
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  func configure(for entry: WindowEntry?) {
    targetWindowID = entry?.windowID
    targetWindowLevel = .normal
    window?.level = targetWindowLevel
  }

  func animate(to point: CGPoint, duration: TimeInterval = 0.16) {
    cancelHide()
    let start = animationStartPoint(for: point)
    show(at: start)

    let dx = point.x - start.x
    let dy = point.y - start.y
    let distance = sqrt((dx * dx) + (dy * dy))
    let adjustedDuration = max(duration, min(0.42, 0.14 + (distance / 900.0)))
    let steps = max(Int(adjustedDuration / 0.02), 1)
    for step in 1...steps {
      let progress = CGFloat(step) / CGFloat(steps)
      let eased = progress < 0.5
        ? 2 * progress * progress
        : 1 - pow(-2 * progress + 2, 2) / 2
      let next = CGPoint(
        x: start.x + ((point.x - start.x) * eased),
        y: start.y + ((point.y - start.y) * eased)
      )
      move(to: next)
      RunLoop.current.run(until: Date().addingTimeInterval(adjustedDuration / Double(steps)))
    }

    currentPoint = point
  }

  func move(to point: CGPoint) {
    cancelHide()
    let window = ensureWindow()
    window.level = targetWindowLevel
    let appKitPoint = appKitPoint(fromDisplayPoint: point)
    window.setFrameOrigin(NSPoint(x: appKitPoint.x - hotspot.x, y: appKitPoint.y - hotspot.y))
    if let targetWindowID {
      window.order(.above, relativeTo: Int(targetWindowID))
    } else {
      window.orderFront(nil)
    }
    if window.alphaValue < 0.98 {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.12
        window.animator().alphaValue = 1
      }
    } else {
      window.alphaValue = 1
    }
    currentPoint = point
  }

  func scheduleIdleHide(after delay: TimeInterval? = nil) {
    cancelHide()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, let window = self.window else {
        return
      }
      self.view?.pulseAlpha = 0
      self.view?.pressed = false
      window.alphaValue = 0
      window.orderOut(nil)
    }
    hideWorkItem = workItem
    overlayQueue.asyncAfter(deadline: .now() + (delay ?? idleHideDelay), execute: workItem)
  }

  func pulse() {
    _ = ensureWindow()
    view?.pressed = true
    view?.pulseAlpha = 1
    view?.cursorScale = 0.9

    let steps = 6
    for step in 1...steps {
      let progress = CGFloat(step) / CGFloat(steps)
      let eased = progress < 0.5
        ? 4 * progress * progress * progress
        : 1 - pow(-2 * progress + 2, 3) / 2
      view?.pulseAlpha = 1 - progress
      view?.cursorScale = 0.9 + (0.1 * eased)
      RunLoop.current.run(until: Date().addingTimeInterval(0.018))
    }

    view?.pressed = false
    view?.pulseAlpha = 0
    view?.cursorScale = 1
  }

  private func show(at point: CGPoint) {
    move(to: point)
  }

  private func animationStartPoint(for target: CGPoint) -> CGPoint {
    if let currentPoint {
      return currentPoint
    }

    let mouse = displayPoint(fromAppKitPoint: NSEvent.mouseLocation)
    let dx = target.x - mouse.x
    let dy = target.y - mouse.y
    let distance = sqrt((dx * dx) + (dy * dy))
    if distance >= 18 {
      return mouse
    }

    return CGPoint(x: target.x - 26, y: target.y + 22)
  }

  private func cancelHide() {
    hideWorkItem?.cancel()
    hideWorkItem = nil
  }

  private func ensureWindow() -> NSWindow {
    if let window {
      return window
    }

    let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    let window = NSWindow(
      contentRect: rect,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.level = targetWindowLevel
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.alphaValue = 0
    window.contentView = OverlayCursorView(frame: rect)
    self.window = window
    return window
  }
}

func desktopFrame() -> CGRect {
  NSScreen.screens.map(\.frame).reduce(into: CGRect.null) { result, frame in
    result = result.union(frame)
  }
}

func appKitPoint(fromDisplayPoint point: CGPoint) -> CGPoint {
  let frame = desktopFrame()
  return CGPoint(x: point.x, y: frame.maxY - point.y)
}

func displayPoint(fromAppKitPoint point: CGPoint) -> CGPoint {
  let frame = desktopFrame()
  return CGPoint(x: point.x, y: frame.maxY - point.y)
}

struct WindowEntry {
  let pid: pid_t
  let windowID: CGWindowID
  let ownerName: String
  let title: String?
  let bounds: CGRect
}

struct Request: Decodable {
  let id: String
  let method: String
  let params: [String: JSONValue]
}

struct Response: Encodable {
  let id: String
  let ok: Bool
  let result: ResultPayload?
  let error: String?
}

struct ResultPayload: Encodable {
  let ok: Bool
  let toolName: String
  let app: AppPayload?
  let snapshot: SnapshotPayload?
  let artifacts: ArtifactsPayload?
  let data: [String: JSONValue]?
  let warnings: [String]
  let meta: MetaPayload
  let error: ErrorPayload?
}

struct AppPayload: Encodable {
  let name: String?
  let bundleId: String?
  let pid: Int?
}

struct SnapshotPayload: Encodable {
  let windowTitle: String?
  let treeText: String
  let elements: [ElementPayload]
}

struct ElementPayload: Encodable {
  let index: String
  let id: String?
  let role: String?
  let title: String?
  let description: String?
  let value: JSONValue?
  let help: String?
  let enabled: Bool?
  let focused: Bool?
  let settable: Bool?
  let actions: [String]?
  let bounds: BoundsPayload?
}

struct BoundsPayload: Encodable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

struct ArtifactsPayload: Encodable {
  let screenshotMimeType: String?
  let screenshotBase64: String?
}

struct AXSnapshotData {
  let treeText: String
  let elements: [ElementPayload]
  let warnings: [String]
}

struct MetaPayload: Encodable {
  let observedShape: String
  let rawText: String?
}

struct ErrorPayload: Encodable {
  let code: String
  let message: String
  let retryable: Bool
}

enum JSONValue: Codable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .null
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }
}

let decoder = JSONDecoder()
let encoder = JSONEncoder()

func writeResponse(_ response: Response) {
  guard let data = try? encoder.encode(response), let line = String(data: data, encoding: .utf8) else {
    return
  }
  FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func makeErrorResult(toolName: String, code: String, message: String) -> ResultPayload {
  ResultPayload(
    ok: false,
    toolName: toolName,
    app: nil,
    snapshot: nil,
    artifacts: nil,
    data: nil,
    warnings: [],
    meta: MetaPayload(observedShape: "text_error", rawText: message),
    error: ErrorPayload(code: code, message: message, retryable: false)
  )
}

func windowEntries() -> [WindowEntry] {
  guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]]
  else {
    return []
  }

  return infoList.compactMap { info in
    guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID > 0 else {
      return nil
    }
    guard let ownerName = info[kCGWindowOwnerName as String] as? String, !ownerName.isEmpty else {
      return nil
    }

    let layer = info[kCGWindowLayer as String] as? Int ?? 0
    if layer != 0 {
      return nil
    }

    guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else {
      return nil
    }

    let width = boundsDict["Width"] as? Double ?? 0
    let height = boundsDict["Height"] as? Double ?? 0
      if width < 40 || height < 40 {
        return nil
      }

    let x = boundsDict["X"] as? Double ?? 0
    let y = boundsDict["Y"] as? Double ?? 0
    let bounds = CGRect(x: x, y: y, width: width, height: height)

    let title = info[kCGWindowName as String] as? String
    let windowID = info[kCGWindowNumber as String] as? UInt32 ?? 0
    return WindowEntry(pid: ownerPID, windowID: windowID, ownerName: ownerName, title: title, bounds: bounds)
  }
}

func runningApp(for pid: pid_t) -> NSRunningApplication? {
  NSRunningApplication(processIdentifier: pid)
}

func appDisplayName(_ app: NSRunningApplication) -> String {
  app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
}

func appIdentityKey(_ app: NSRunningApplication) -> String {
  if let bundleId = app.bundleIdentifier, !bundleId.isEmpty {
    return bundleId
  }
  return appDisplayName(app).lowercased()
}

func appScore(_ app: NSRunningApplication, visiblePIDs: Set<pid_t>, frontmostPID: pid_t?) -> Int {
  var score = 0
  if app.processIdentifier == frontmostPID {
    score += 100
  }
  if visiblePIDs.contains(app.processIdentifier) {
    score += 50
  }
  if app.activationPolicy == .regular {
    score += 20
  }
  if app.bundleIdentifier != nil {
    score += 5
  }
  return score
}

func isLikelyUserFacingApp(_ app: NSRunningApplication, visiblePIDs: Set<pid_t>, frontmostPID: pid_t?) -> Bool {
  let bundleId = app.bundleIdentifier?.lowercased() ?? ""
  let name = appDisplayName(app).lowercased()

  let excludedBundleFragments = [
    ".helper",
    ".agent",
    ".uiagent",
    ".xpc",
    ".daemon",
  ]
  if excludedBundleFragments.contains(where: { bundleId.contains($0) }) {
    return false
  }

  let excludedBundleIDs = [
    "com.apple.windowmanager",
    "com.apple.dock",
    "com.apple.systemuiserver",
  ]
  if excludedBundleIDs.contains(bundleId) {
    return false
  }

  if app.processIdentifier == frontmostPID || visiblePIDs.contains(app.processIdentifier) {
    return true
  }

  guard app.activationPolicy == .regular else {
    return false
  }

  let excludedNameFragments = [
    " helper",
    "agent",
    "server",
    "pty-host",
    "filewatcher",
    "shared-process",
    "notification",
    "windowmanager",
    "systemuiserver",
    "control center",
    "centre de contrôle",
    "centre de notifications",
    "dock",
    "spotlight",
    "storeuid",
    "wifi",
    "wi-fi",
  ]
  if excludedNameFragments.contains(where: { name.contains($0) }) {
    return false
  }

  return true
}

func listAppsResult() -> ResultPayload {
  let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
  let visiblePIDs = Set(windowEntries().map(\.pid))
  var uniqueApps: [String: NSRunningApplication] = [:]

  for app in NSWorkspace.shared.runningApplications {
    guard !app.isTerminated else {
      continue
    }
    guard app.bundleIdentifier != nil || app.localizedName != nil else {
      continue
    }
    guard isLikelyUserFacingApp(app, visiblePIDs: visiblePIDs, frontmostPID: frontmostPID) else {
      continue
    }

    let key = appIdentityKey(app)
    if let existing = uniqueApps[key] {
      if appScore(app, visiblePIDs: visiblePIDs, frontmostPID: frontmostPID) > appScore(existing, visiblePIDs: visiblePIDs, frontmostPID: frontmostPID) {
        uniqueApps[key] = app
      }
    } else {
      uniqueApps[key] = app
    }
  }

  let apps = Array(uniqueApps.values)
    .sorted {
      let leftScore = appScore($0, visiblePIDs: visiblePIDs, frontmostPID: frontmostPID)
      let rightScore = appScore($1, visiblePIDs: visiblePIDs, frontmostPID: frontmostPID)
      if leftScore != rightScore {
        return leftScore > rightScore
      }
      let leftName = appDisplayName($0)
      let rightName = appDisplayName($1)
      return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
    }
    .map { app in
      JSONValue.object([
        "name": .string(appDisplayName(app)),
        "bundleId": app.bundleIdentifier.map(JSONValue.string) ?? .null,
        "pid": .number(Double(app.processIdentifier)),
        "running": .bool(true),
        "frontmost": .bool(app.processIdentifier == frontmostPID),
        "visible": .bool(visiblePIDs.contains(app.processIdentifier)),
      ])
    }

  let rawText = apps.compactMap { value -> String? in
    guard case .object(let object) = value else { return nil }
    guard case .string(let name)? = object["name"] else { return nil }
    let bundleText: String
    if case .string(let bundleId)? = object["bundleId"] {
      bundleText = bundleId
    } else {
      bundleText = "<unknown>"
    }
    return "\(name) — \(bundleText) [running]"
  }.joined(separator: "\n")

  return ResultPayload(
    ok: true,
    toolName: "list_apps",
    app: nil,
    snapshot: nil,
    artifacts: nil,
    data: ["apps": .array(apps)],
    warnings: [
      "Native helper currently returns running applications only; recent app history, last-used dates, and usage counts are not implemented yet."
    ],
    meta: MetaPayload(observedShape: "text", rawText: rawText),
    error: nil
  )
}

func resolveApp(_ ref: String) -> NSRunningApplication? {
  let runningApps = NSWorkspace.shared.runningApplications
  if let exactBundle = NSRunningApplication.runningApplications(withBundleIdentifier: ref).first {
    return exactBundle
  }
  if let exact = runningApps.first(where: { $0.bundleIdentifier == ref || $0.localizedName == ref }) {
    return exact
  }
  let lowered = ref.lowercased()
  return runningApps.first {
    $0.bundleIdentifier?.lowercased() == lowered || $0.localizedName?.lowercased() == lowered
  }
}

func resolveWindowEntry(_ ref: String) -> WindowEntry? {
  let lowered = ref.lowercased()
  return windowEntries().first { entry in
    let ownerMatch = entry.ownerName.lowercased() == lowered
    let titleMatch = entry.title?.lowercased() == lowered
    return ownerMatch || titleMatch
  }
}

func windowInfo(for pid: pid_t) -> WindowEntry? {
  windowEntries()
    .filter { $0.pid == pid }
    .max {
      let leftArea = $0.bounds.width * $0.bounds.height
      let rightArea = $1.bounds.width * $1.bounds.height
      if leftArea == rightArea {
        return $0.windowID < $1.windowID
      }
      return leftArea < rightArea
    }
}

func resolvedWindowInfo(appRef: String) -> WindowEntry? {
  (resolveApp(appRef).flatMap { windowInfo(for: $0.processIdentifier) }) ?? resolveWindowEntry(appRef)
}

func screenPoint(forScreenshotPoint point: CGPoint, appRef: String) -> CGPoint? {
  guard let entry = resolvedWindowInfo(appRef: appRef) else {
    return nil
  }

  return CGPoint(x: entry.bounds.origin.x + point.x, y: entry.bounds.origin.y + point.y)
}

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
  var value: CFTypeRef?
  let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard error == .success else {
    return nil
  }
  return value
}

func axElementValue(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
  guard let value = axValue(element, attribute) else {
    return nil
  }
  return unsafeBitCast(value, to: AXUIElement.self)
}

func axTypedValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
  guard let value = axValue(element, attribute) else {
    return nil
  }
  return unsafeBitCast(value, to: AXValue.self)
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
  axValue(element, attribute) as? String
}

func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
  axValue(element, attribute) as? Bool
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
  (axValue(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func axActions(_ element: AXUIElement) -> [String] {
  var actions: CFArray?
  let error = AXUIElementCopyActionNames(element, &actions)
  guard error == .success, let actions else {
    return []
  }
  return actions as? [String] ?? []
}

func axBounds(_ element: AXUIElement) -> BoundsPayload? {
  guard let positionValue = axTypedValue(element, kAXPositionAttribute as String),
    let sizeValue = axTypedValue(element, kAXSizeAttribute as String)
  else {
    return nil
  }

  var point = CGPoint.zero
  var size = CGSize.zero
  guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &size) else {
    return nil
  }

  return BoundsPayload(x: point.x, y: point.y, width: size.width, height: size.height)
}

func axIsSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
  var settable: DarwinBoolean = false
  let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
  return error == .success && settable.boolValue
}

func axRootElement(for app: NSRunningApplication) -> AXUIElement {
  let appElement = AXUIElementCreateApplication(app.processIdentifier)
  if let focusedWindow = axElementValue(appElement, kAXFocusedWindowAttribute as String) {
    return focusedWindow
  }
  if let mainWindow = axElementValue(appElement, kAXMainWindowAttribute as String) {
    return mainWindow
  }
  return appElement
}

func axFocusedElement(for app: NSRunningApplication) -> AXUIElement? {
  let appElement = AXUIElementCreateApplication(app.processIdentifier)
  if let focusedElement = axElementValue(appElement, kAXFocusedUIElementAttribute as String) {
    return focusedElement
  }
  return nil
}

func displayRoleName(_ role: String?) -> String {
  switch role {
  case kAXWindowRole as String:
    return "standard window"
  case kAXGroupRole as String:
    return "group"
  case kAXSplitGroupRole as String:
    return "split group"
  case kAXSplitterRole as String:
    return "splitter"
  case kAXScrollAreaRole as String:
    return "scroll area"
  case kAXStaticTextRole as String:
    return "text"
  case kAXButtonRole as String:
    return "button"
  case kAXMenuButtonRole as String:
    return "menu button"
  case kAXMenuBarRole as String:
    return "menu bar"
  case kAXTextAreaRole as String:
    return "text area"
  default:
    let raw = role ?? "element"
    return raw.replacingOccurrences(of: "AX", with: "").lowercased()
  }
}

func displayActionName(_ action: String) -> String? {
  switch action {
  case kAXRaiseAction as String:
    return "Raise"
  case kAXPressAction as String:
    return nil
  case kAXConfirmAction as String:
    return "Confirm"
  case kAXCancelAction as String:
    return "Cancel"
  case kAXShowMenuAction as String:
    return "ShowMenu"
  case kAXPickAction as String:
    return "Pick"
  default:
    if action.hasPrefix("AXScroll") {
      return nil
    }
    if action.hasPrefix("AX") {
      return String(action.dropFirst(2))
    }
    return action
  }
}

func formattedAXValue(_ value: CFTypeRef?) -> String? {
  if let stringValue = value as? String, !stringValue.isEmpty {
    return stringValue
  }
  if let numberValue = value as? NSNumber {
    return numberValue.stringValue
  }
  if let boolValue = value as? Bool {
    return boolValue ? "true" : "false"
  }
  return nil
}

func axElementSummary(_ element: AXUIElement, semanticID: String) -> String {
  let role = axString(element, kAXRoleAttribute as String) ?? "element"
  let title = axString(element, kAXTitleAttribute as String)
  let description = axString(element, kAXDescriptionAttribute as String)
  let value = axValue(element, kAXValueAttribute as String)
  let focused = axBool(element, kAXFocusedAttribute as String) == true
  let enabled = axBool(element, kAXEnabledAttribute as String)
  let settable = axIsSettable(element, kAXValueAttribute as String)
  let actions = axActions(element).compactMap(displayActionName(_:))

  var line = displayRoleName(role)
  if let title, !title.isEmpty, role == kAXWindowRole as String {
    line += " \(title)"
  } else if role == kAXStaticTextRole as String, let renderedValue = formattedAXValue(value) {
    line += " \(renderedValue)"
  }

  var details: [String] = []
  if let description, !description.isEmpty, description != title {
    details.append("Description: \(description)")
  }
  if role != kAXStaticTextRole as String, let renderedValue = formattedAXValue(value) {
    details.append(renderedValue)
  }

  var flags: [String] = []
  if enabled == false {
    flags.append("disabled")
  }
  if settable {
    flags.append("settable")
  }
  if focused && role != kAXTextAreaRole as String {
    flags.append("focused")
  }
  if !flags.isEmpty {
    details.append("(\(flags.joined(separator: ", ")))")
  }

  details.append("ID: \(semanticID)")
  if !actions.isEmpty {
    details.append("Secondary Actions: \(actions.joined(separator: ", "))")
  }

  if !details.isEmpty {
    line += ", " + details.joined(separator: ", ")
  }

  return line
}

func semanticIDComponent(from rawValue: String?) -> String? {
  guard let rawValue else {
    return nil
  }

  let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    return nil
  }

  if trimmed.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil {
    return trimmed
  }

  let words = trimmed
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }

  guard !words.isEmpty else {
    return nil
  }

  let component = words
    .map { word in
      let lowered = word.lowercased()
      return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }
    .joined()

  return component.isEmpty ? nil : component
}

func baseSemanticID(for element: AXUIElement) -> String {
  let role = axString(element, kAXRoleAttribute as String) ?? "AXElement"
  if role == kAXWindowRole as String {
    return "main"
  }

  if let component = semanticIDComponent(from: axString(element, kAXIdentifierAttribute as String)) {
    return component
  }
  if let component = semanticIDComponent(from: axString(element, kAXDescriptionAttribute as String)) {
    return component
  }
  if let component = semanticIDComponent(from: axString(element, kAXTitleAttribute as String)) {
    return component
  }
  if let component = semanticIDComponent(from: axString(element, kAXHelpAttribute as String)) {
    return component
  }
  if let value = axValue(element, kAXValueAttribute as String) as? String,
    let component = semanticIDComponent(from: value),
    !component.isEmpty
  {
    return component
  }

  return semanticIDComponent(from: role.replacingOccurrences(of: "AX", with: "")) ?? "Element"
}

func nextSemanticID(for element: AXUIElement, usedIDs: inout [String: Int]) -> String {
  let base = baseSemanticID(for: element)
  let key = base.lowercased()
  let nextCount = (usedIDs[key] ?? 0) + 1
  usedIDs[key] = nextCount
  return nextCount == 1 ? base : "\(base)\(nextCount)"
}

func buildAXSnapshot(for app: NSRunningApplication) -> AXSnapshotData {
  let root = axRootElement(for: app)
  var nextIndex = 0
  var usedIDs: [String: Int] = [:]
  var elements: [ElementPayload] = []
  var lines: [String] = []
  var warnings: [String] = []

  func walk(_ element: AXUIElement, depth: Int) {
    if nextIndex > 120 || depth > 8 {
      return
    }

    let index = "\(nextIndex)"
    nextIndex += 1
    let semanticID = nextSemanticID(for: element, usedIDs: &usedIDs)
    let value = axValue(element, kAXValueAttribute as String)
    let normalizedValue: JSONValue?
    if let stringValue = value as? String {
      normalizedValue = .string(stringValue)
    } else if let boolValue = value as? Bool {
      normalizedValue = .bool(boolValue)
    } else if let numberValue = value as? NSNumber {
      normalizedValue = .number(numberValue.doubleValue)
    } else {
      normalizedValue = nil
    }

    let actions = axActions(element)
    elements.append(
      ElementPayload(
        index: index,
        id: semanticID,
        role: axString(element, kAXRoleAttribute as String),
        title: axString(element, kAXTitleAttribute as String),
        description: axString(element, kAXDescriptionAttribute as String),
        value: normalizedValue,
        help: axString(element, kAXHelpAttribute as String),
        enabled: axBool(element, kAXEnabledAttribute as String),
        focused: axBool(element, kAXFocusedAttribute as String),
        settable: axIsSettable(element, kAXValueAttribute as String),
        actions: actions.isEmpty ? nil : actions,
        bounds: axBounds(element)
      )
    )
    lines.append("\(String(repeating: "\t", count: max(depth, 0)))\(index) \(axElementSummary(element, semanticID: semanticID))")

    let children = axChildren(element)
    if children.count > 40 {
      warnings.append("Accessibility tree truncated for large child lists.")
    }

    for child in children.prefix(40) {
      walk(child, depth: depth + 1)
    }
  }

  walk(root, depth: 0)

  if lines.isEmpty {
    warnings.append("Accessibility tree extraction returned no visible elements.")
  }

  return AXSnapshotData(treeText: lines.joined(separator: "\n"), elements: elements, warnings: warnings)
}

func axElementByIndex(for app: NSRunningApplication, index targetIndex: String) -> AXUIElement? {
  let root = axRootElement(for: app)
  var nextIndex = 0
  var usedIDs: [String: Int] = [:]
  var found: AXUIElement?

  func walk(_ element: AXUIElement, depth: Int) {
    if found != nil || nextIndex > 120 || depth > 8 {
      return
    }

    let index = "\(nextIndex)"
    nextIndex += 1
    let semanticID = nextSemanticID(for: element, usedIDs: &usedIDs)
    if index == targetIndex || semanticID.lowercased() == targetIndex.lowercased() {
      found = element
      return
    }

    for child in axChildren(element).prefix(40) {
      walk(child, depth: depth + 1)
      if found != nil {
        return
      }
    }
  }

  walk(root, depth: 0)
  return found
}

func boundsContainPoint(_ bounds: BoundsPayload, point: CGPoint) -> Bool {
  point.x >= bounds.x &&
    point.x <= (bounds.x + bounds.width) &&
    point.y >= bounds.y &&
    point.y <= (bounds.y + bounds.height)
}

func axClickableElement(at point: CGPoint, for app: NSRunningApplication) -> AXUIElement? {
  let root = axRootElement(for: app)
  var bestMatch: (element: AXUIElement, area: CGFloat)?

  func score(_ element: AXUIElement, bounds: BoundsPayload) -> CGFloat {
    let actions = axActions(element)
    guard actions.contains(kAXPressAction as String) || actions.contains(kAXPickAction as String) else {
      return .greatestFiniteMagnitude
    }
    guard boundsContainPoint(bounds, point: point) else {
      return .greatestFiniteMagnitude
    }
    return bounds.width * bounds.height
  }

  func walk(_ element: AXUIElement, depth: Int) {
    if depth > 10 {
      return
    }

    if let bounds = axBounds(element) {
      let area = score(element, bounds: bounds)
      if area.isFinite {
        if let currentBest = bestMatch {
          if area < currentBest.area {
            bestMatch = (element, area)
          }
        } else {
          bestMatch = (element, area)
        }
      }
    }

    for child in axChildren(element).prefix(60) {
      walk(child, depth: depth + 1)
    }
  }

  walk(root, depth: 0)
  return bestMatch?.element
}

func performSemanticClick(at point: CGPoint, appRef: String) -> Bool {
  guard let app = resolveApp(appRef),
    let element = axClickableElement(at: point, for: app)
  else {
    return false
  }

  let actions = axActions(element)
  let actionName: String?
  if actions.contains(kAXPressAction as String) {
    actionName = kAXPressAction as String
  } else if actions.contains(kAXPickAction as String) {
    actionName = kAXPickAction as String
  } else {
    actionName = nil
  }

  guard let actionName else {
    return false
  }

  return AXUIElementPerformAction(element, actionName as CFString) == .success
}

func preferredKeyboardFocusElement(for app: NSRunningApplication) -> AXUIElement? {
  if let focused = axFocusedElement(for: app), axBounds(focused) != nil {
    return focused
  }

  let root = axRootElement(for: app)
  var candidate: AXUIElement?

  func score(_ element: AXUIElement) -> Int {
    let role = axString(element, kAXRoleAttribute as String) ?? ""
    let settable = axIsSettable(element, kAXValueAttribute as String)
    var score = 0

    if settable {
      score += 5
    }
    if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String {
      score += 5
    }
    if role == kAXComboBoxRole as String || role == "AXSearchField" {
      score += 4
    }

    return score
  }

  func walk(_ element: AXUIElement, depth: Int) {
    if candidate != nil || depth > 8 {
      return
    }

    if score(element) >= 5, axBounds(element) != nil {
      candidate = element
      return
    }

    for child in axChildren(element).prefix(40) {
      walk(child, depth: depth + 1)
      if candidate != nil {
        return
      }
    }
  }

  walk(root, depth: 0)
  return candidate
}

func focusPoint(for appRef: String) -> CGPoint? {
  if let app = resolveApp(appRef) {
    if let focusedElement = preferredKeyboardFocusElement(for: app), let bounds = axBounds(focusedElement) {
      return CGPoint(x: bounds.x + (bounds.width / 2), y: bounds.y + (bounds.height / 2))
    }
  }

  if let entry = resolvedWindowInfo(appRef: appRef) {
    return CGPoint(x: entry.bounds.midX, y: entry.bounds.midY)
  }

  return nil
}

func revealInteractionPoint(_ point: CGPoint, clickToFocus: Bool) -> Bool {
  OverlayCursorController.shared.animate(to: point, duration: 0.14)
  if clickToFocus {
    guard postClick(at: point) else {
      return false
    }
  }
  OverlayCursorController.shared.pulse()
  usleep(70_000)
  return true
}

func getAppStateResult(appRef: String) -> ResultPayload {
  let resolvedApp = resolveApp(appRef)
  let resolvedEntry = resolvedApp.map { windowInfo(for: $0.processIdentifier) } ?? resolveWindowEntry(appRef)

  guard let entry = resolvedEntry ?? resolvedApp.flatMap({ windowInfo(for: $0.processIdentifier) }) else {
    return makeErrorResult(toolName: "get_app_state", code: "app_not_found", message: "appNotFound(\"\(appRef)\")")
  }

  let app = resolvedApp ?? runningApp(for: entry.pid)
  let title = entry.title
  let bundleId = app?.bundleIdentifier ?? appRef
  let appName = app?.localizedName ?? entry.ownerName
  let screenshot = captureWindowScreenshot(entry)
  let axSnapshot = app.map(buildAXSnapshot)
  let bodyText = axSnapshot?.treeText ?? ""
  let treeText = bodyText.isEmpty
    ? "App=\(bundleId)\nWindow: \"\(title ?? "<unknown>")\", App: \(appName)."
    : "App=\(bundleId)\nWindow: \"\(title ?? "<unknown>")\", App: \(appName).\n\(bodyText)"

  return ResultPayload(
    ok: true,
    toolName: "get_app_state",
    app: AppPayload(name: appName, bundleId: app?.bundleIdentifier, pid: Int(entry.pid)),
    snapshot: SnapshotPayload(windowTitle: title, treeText: treeText, elements: axSnapshot?.elements ?? []),
    artifacts: screenshot,
    data: nil,
    warnings: [
      axSnapshot == nil ? "Accessibility tree extraction is unavailable for this app instance." : nil,
      axSnapshot?.warnings.first,
      screenshot == nil ? "Native helper screenshot capture is not implemented yet." : nil
    ].compactMap { $0 },
    meta: MetaPayload(observedShape: "state+image", rawText: treeText),
    error: nil
  )
}

func captureWindowScreenshot(_ entry: WindowEntry) -> ArtifactsPayload? {
  let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("computer-use-\(UUID().uuidString).png")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  process.arguments = ["-x", "-R\(Int(entry.bounds.origin.x)),\(Int(entry.bounds.origin.y)),\(Int(entry.bounds.width)),\(Int(entry.bounds.height))", fileURL.path]

  do {
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      try? FileManager.default.removeItem(at: fileURL)
      return nil
    }

    let data = try Data(contentsOf: fileURL)
    try? FileManager.default.removeItem(at: fileURL)
    return ArtifactsPayload(screenshotMimeType: "image/png", screenshotBase64: data.base64EncodedString())
  } catch {
    try? FileManager.default.removeItem(at: fileURL)
    return nil
  }
}

func targetWindowElement(for app: NSRunningApplication) -> AXUIElement? {
  let appElement = AXUIElementCreateApplication(app.processIdentifier)
  if let focusedWindow = axElementValue(appElement, kAXFocusedWindowAttribute as String) {
    return focusedWindow
  }
  if let mainWindow = axElementValue(appElement, kAXMainWindowAttribute as String) {
    return mainWindow
  }
  return nil
}

@discardableResult
func raiseTargetWindow(for app: NSRunningApplication) -> Bool {
  guard let window = targetWindowElement(for: app) else {
    return false
  }
  return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
}

func mouseButton(from rawValue: String?) -> CGMouseButton {
  switch rawValue {
  case "right":
    return .right
  case "middle":
    return .center
  default:
    return .left
  }
}

func withActivatedApp<T>(
  appRef: String,
  activate: Bool = true,
  restorePreviousFocus: Bool = true,
  stackTargetBehindPrevious: Bool = false,
  action: () -> T
) -> T {
  let previousFrontmost = NSWorkspace.shared.frontmostApplication
  let targetApp = resolveApp(appRef)
  let targetEntry = resolvedWindowInfo(appRef: appRef)

  if activate, let targetApp {
    let previousIsTarget = previousFrontmost?.processIdentifier == targetApp.processIdentifier
    if stackTargetBehindPrevious, !previousIsTarget {
      _ = raiseTargetWindow(for: targetApp)
      usleep(120_000)
    } else {
      targetApp.activate()
      usleep(120_000)
    }
  }

  OverlayCursorController.shared.configure(for: targetEntry)
  let result = action()

  if restorePreviousFocus, let previousFrontmost, previousFrontmost.processIdentifier != targetApp?.processIdentifier {
    previousFrontmost.activate()
    usleep(120_000)
  }

  return result
}

func mouseEventTypes(for button: CGMouseButton) -> (down: CGEventType, up: CGEventType) {
  switch button {
  case .right:
    return (.rightMouseDown, .rightMouseUp)
  case .center:
    return (.otherMouseDown, .otherMouseUp)
  default:
    return (.leftMouseDown, .leftMouseUp)
  }
}

func postClick(at location: CGPoint, button: CGMouseButton = .left, clickCount: Int = 1) -> Bool {
  let eventTypes = mouseEventTypes(for: button)
  for _ in 0..<clickCount {
    guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: eventTypes.down, mouseCursorPosition: location, mouseButton: button),
      let upEvent = CGEvent(mouseEventSource: nil, mouseType: eventTypes.up, mouseCursorPosition: location, mouseButton: button)
    else {
      return false
    }

    downEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
    upEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
    downEvent.post(tap: .cghidEventTap)
    upEvent.post(tap: .cghidEventTap)
    usleep(40_000)
  }
  return true
}

func clickResult(params: [String: JSONValue]) -> ResultPayload {
  guard case .string(let appRef)? = params["app"] else {
    return makeErrorResult(toolName: "click", code: "internal_error", message: "Missing app parameter")
  }
  guard case .number(let xValue)? = params["x"], case .number(let yValue)? = params["y"] else {
    return makeErrorResult(toolName: "click", code: "unsupported_action", message: "Native helper currently supports coordinate clicks only.")
  }

  let clickCount: Int
  if case .number(let rawCount)? = params["click_count"] {
    clickCount = max(Int(rawCount), 1)
  } else {
    clickCount = 1
  }

  let buttonName: String?
  if case .string(let rawButton)? = params["mouse_button"] {
    buttonName = rawButton
  } else {
    buttonName = nil
  }

  let button = mouseButton(from: buttonName)
  guard let location = screenPoint(forScreenshotPoint: CGPoint(x: xValue, y: yValue), appRef: appRef) else {
    return makeErrorResult(toolName: "click", code: "app_not_found", message: "appNotFound(\"\(appRef)\")")
  }

  let canUseSemanticClick = button == .left && clickCount == 1
  var success = false

  if canUseSemanticClick {
    success = withActivatedApp(
      appRef: appRef,
      activate: true,
      restorePreviousFocus: true,
      stackTargetBehindPrevious: true
    ) {
      OverlayCursorController.shared.animate(to: location)
      let pressed = performSemanticClick(at: location, appRef: appRef)
      if pressed {
        OverlayCursorController.shared.pulse()
        OverlayCursorController.shared.scheduleIdleHide()
      }
      return pressed
    }
  }

  if !success {
    success = withActivatedApp(
      appRef: appRef,
      activate: true,
      restorePreviousFocus: true,
      stackTargetBehindPrevious: true
    ) {
      OverlayCursorController.shared.animate(to: location)
      let clickSucceeded = postClick(at: location, button: button, clickCount: clickCount)
      OverlayCursorController.shared.pulse()
      OverlayCursorController.shared.scheduleIdleHide()
      return clickSucceeded
    }
  }

  guard success else {
    return makeErrorResult(toolName: "click", code: "internal_error", message: "Unable to create native click events.")
  }

  usleep(250_000)
  return getAppStateResult(appRef: appRef)
}

func dragResult(params: [String: JSONValue]) -> ResultPayload {
  guard case .string(let appRef)? = params["app"] else {
    return makeErrorResult(toolName: "drag", code: "internal_error", message: "Missing app parameter")
  }
  guard case .number(let fromX)? = params["from_x"],
    case .number(let fromY)? = params["from_y"],
    case .number(let toX)? = params["to_x"],
    case .number(let toY)? = params["to_y"]
  else {
    return makeErrorResult(toolName: "drag", code: "internal_error", message: "Missing drag coordinates")
  }

  let from = CGPoint(x: fromX, y: fromY)
  let to = CGPoint(x: toX, y: toY)
  guard let fromScreen = screenPoint(forScreenshotPoint: from, appRef: appRef),
    let toScreen = screenPoint(forScreenshotPoint: to, appRef: appRef)
  else {
    return makeErrorResult(toolName: "drag", code: "app_not_found", message: "appNotFound(\"\(appRef)\")")
  }
  let steps = 12

  let success = withActivatedApp(appRef: appRef, restorePreviousFocus: true, stackTargetBehindPrevious: true) {
    OverlayCursorController.shared.animate(to: fromScreen, duration: 0.14)

    guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: fromScreen, mouseButton: .left),
      let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: fromScreen, mouseButton: .left)
    else {
      return false
    }

    moveEvent.post(tap: .cghidEventTap)
    usleep(40_000)
    downEvent.post(tap: .cghidEventTap)
    usleep(40_000)

    for index in 1...steps {
      let progress = Double(index) / Double(steps)
      let point = CGPoint(
        x: fromScreen.x + ((toScreen.x - fromScreen.x) * progress),
        y: fromScreen.y + ((toScreen.y - fromScreen.y) * progress)
      )
      OverlayCursorController.shared.move(to: point)
      guard let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) else {
        return false
      }
      dragEvent.post(tap: .cghidEventTap)
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    guard let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: toScreen, mouseButton: .left) else {
      return false
    }
    upEvent.post(tap: .cghidEventTap)
    OverlayCursorController.shared.pulse()
    OverlayCursorController.shared.scheduleIdleHide()
    return true
  }

  if !success {
    return makeErrorResult(toolName: "drag", code: "internal_error", message: "Unable to post native drag events.")
  }

  usleep(120_000)
  return getAppStateResult(appRef: appRef)
}

func unicodeKeyPair(text: String, flags: CGEventFlags = []) -> Bool {
  guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
  else {
    return false
  }

  keyDown.flags = flags
  keyUp.flags = flags
  keyDown.keyboardSetUnicodeString(stringLength: text.utf16.count, unicodeString: Array(text.utf16))
  keyUp.keyboardSetUnicodeString(stringLength: text.utf16.count, unicodeString: Array(text.utf16))
  keyDown.post(tap: .cghidEventTap)
  keyUp.post(tap: .cghidEventTap)
  return true
}

func typeCharacter(_ character: Character) -> Bool {
  let text = String(character)
  if let code = keyCode(for: text) {
    return postKeyCode(code, flags: [])
  }
  return unicodeKeyPair(text: text)
}

func modifierFlags(from parts: ArraySlice<String>) -> CGEventFlags {
  var flags: CGEventFlags = []
  for part in parts {
    switch part {
    case "cmd", "command", "super":
      flags.insert(.maskCommand)
    case "ctrl", "control":
      flags.insert(.maskControl)
    case "alt", "option":
      flags.insert(.maskAlternate)
    case "shift":
      flags.insert(.maskShift)
    default:
      break
    }
  }
  return flags
}

func keyCode(for rawKey: String) -> CGKeyCode? {
  switch rawKey.lowercased() {
  case "a": return 0
  case "s": return 1
  case "d": return 2
  case "f": return 3
  case "h": return 4
  case "g": return 5
  case "z": return 6
  case "x": return 7
  case "c": return 8
  case "v": return 9
  case "b": return 11
  case "q": return 12
  case "w": return 13
  case "e": return 14
  case "r": return 15
  case "y": return 16
  case "t": return 17
  case "1": return 18
  case "2": return 19
  case "3": return 20
  case "4": return 21
  case "6": return 22
  case "5": return 23
  case "=": return 24
  case "9": return 25
  case "7": return 26
  case "-": return 27
  case "8": return 28
  case "0": return 29
  case "]": return 30
  case "o": return 31
  case "u": return 32
  case "[": return 33
  case "i": return 34
  case "p": return 35
  case "l": return 37
  case "j": return 38
  case "'": return 39
  case "k": return 40
  case ";": return 41
  case "\\": return 42
  case ",": return 43
  case "/": return 44
  case "n": return 45
  case "m": return 46
  case ".": return 47
  case "`": return 50
  case "return", "enter": return 36
  case "tab": return 48
  case "space": return 49
  case "delete", "backspace": return 51
  case "escape", "esc": return 53
  case "left": return 123
  case "right": return 124
  case "down": return 125
  case "up": return 126
  default: return nil
  }
}

func postKeyCode(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
  guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
  else {
    return false
  }

  keyDown.flags = flags
  keyUp.flags = flags
  keyDown.post(tap: .cghidEventTap)
  keyUp.post(tap: .cghidEventTap)
  return true
}

func typeTextResult(params: [String: JSONValue]) -> ResultPayload {
  guard case .string(let appRef)? = params["app"] else {
    return makeErrorResult(toolName: "type_text", code: "internal_error", message: "Missing app parameter")
  }
  guard case .string(let text)? = params["text"] else {
    return makeErrorResult(toolName: "type_text", code: "internal_error", message: "Missing text parameter")
  }

  let success = withActivatedApp(appRef: appRef, restorePreviousFocus: true) {
    if let point = focusPoint(for: appRef), !revealInteractionPoint(point, clickToFocus: true) {
      return false
    }

    for character in text {
      if !typeCharacter(character) {
        return false
      }
      usleep(30_000)
    }
    OverlayCursorController.shared.scheduleIdleHide()
    return true
  }

  if !success {
    return makeErrorResult(toolName: "type_text", code: "internal_error", message: "Unable to post native text events.")
  }

  usleep(120_000)
  return getAppStateResult(appRef: appRef)
}

func pressKeyResult(params: [String: JSONValue]) -> ResultPayload {
  guard case .string(let appRef)? = params["app"] else {
    return makeErrorResult(toolName: "press_key", code: "internal_error", message: "Missing app parameter")
  }
  guard case .string(let keySpec)? = params["key"] else {
    return makeErrorResult(toolName: "press_key", code: "internal_error", message: "Missing key parameter")
  }

  let parts = keySpec.split(separator: "+").map(String.init)
  guard let rawKey = parts.last, !rawKey.isEmpty else {
    return makeErrorResult(toolName: "press_key", code: "internal_error", message: "Invalid key parameter")
  }

  let flags = modifierFlags(from: parts.dropLast()[...])
  let success = withActivatedApp(appRef: appRef, stackTargetBehindPrevious: true) {
    if let point = focusPoint(for: appRef) {
      let shouldClickToFocus = flags.isEmpty && (rawKey.count == 1 || rawKey.lowercased() == "space")
      if !revealInteractionPoint(point, clickToFocus: shouldClickToFocus) {
        return false
      }
    }

    if let code = keyCode(for: rawKey) {
      let posted = postKeyCode(code, flags: flags)
      OverlayCursorController.shared.scheduleIdleHide()
      return posted
    }
    if rawKey.count == 1 {
      let posted = unicodeKeyPair(text: rawKey, flags: flags)
      OverlayCursorController.shared.scheduleIdleHide()
      return posted
    }
    return false
  }

  if !success {
    return makeErrorResult(
      toolName: "press_key",
      code: "unsupported_action",
      message: "Native helper does not support key specification: \(keySpec)"
    )
  }

  usleep(120_000)
  return getAppStateResult(appRef: appRef)
}

func setValueResult(params: [String: JSONValue]) -> ResultPayload {
  guard case .string(let appRef)? = params["app"] else {
    return makeErrorResult(toolName: "set_value", code: "internal_error", message: "Missing app parameter")
  }
  guard case .string(let elementIndex)? = params["element_index"] else {
    return makeErrorResult(toolName: "set_value", code: "internal_error", message: "Missing element_index parameter")
  }
  guard case .string(let value)? = params["value"] else {
    return makeErrorResult(toolName: "set_value", code: "internal_error", message: "Missing value parameter")
  }

  guard let app = resolveApp(appRef) else {
    return makeErrorResult(toolName: "set_value", code: "app_not_found", message: "appNotFound(\"\(appRef)\")")
  }
  guard let element = axElementByIndex(for: app, index: elementIndex) else {
    return makeErrorResult(toolName: "set_value", code: "invalid_element", message: "\(elementIndex) is an invalid element ID")
  }

  let targetPoint = axBounds(element).map { CGPoint(x: $0.x + ($0.width / 2), y: $0.y + ($0.height / 2)) }

  if let targetPoint {
    _ = revealInteractionPoint(targetPoint, clickToFocus: false)
  }

  var success = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString) == .success
  if !success {
    success = withActivatedApp(appRef: appRef) {
      AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString) == .success
    }
  }

  if !success {
    return makeErrorResult(toolName: "set_value", code: "accessibility_error", message: "Accessibility error: Unable to set element value")
  }

  OverlayCursorController.shared.scheduleIdleHide()
  usleep(120_000)
  return getAppStateResult(appRef: appRef)
}

func axActionName(for action: String) -> String {
  switch action.lowercased() {
  case "raise":
    return kAXRaiseAction as String
  case "press":
    return kAXPressAction as String
  case "confirm":
    return kAXConfirmAction as String
  case "cancel":
    return kAXCancelAction as String
  case "showmenu":
    return kAXShowMenuAction as String
  case "pick":
    return kAXPickAction as String
  default:
    if action.hasPrefix("AX") {
      return action
    }
    return action
  }
}

func performSecondaryActionResult(params: [String: JSONValue]) -> ResultPayload {
  guard case .string(let appRef)? = params["app"] else {
    return makeErrorResult(toolName: "perform_secondary_action", code: "internal_error", message: "Missing app parameter")
  }
  guard case .string(let elementIndex)? = params["element_index"] else {
    return makeErrorResult(toolName: "perform_secondary_action", code: "internal_error", message: "Missing element_index parameter")
  }
  guard case .string(let action)? = params["action"] else {
    return makeErrorResult(toolName: "perform_secondary_action", code: "internal_error", message: "Missing action parameter")
  }

  guard let app = resolveApp(appRef) else {
    return makeErrorResult(toolName: "perform_secondary_action", code: "app_not_found", message: "appNotFound(\"\(appRef)\")")
  }
  guard let element = axElementByIndex(for: app, index: elementIndex) else {
    return makeErrorResult(toolName: "perform_secondary_action", code: "invalid_element", message: "\(elementIndex) is an invalid element ID")
  }

  let resolvedAction = axActionName(for: action)
  var success = false

  if resolvedAction != kAXRaiseAction as String {
    success = AXUIElementPerformAction(element, resolvedAction as CFString) == .success
  }

  if !success {
    success = withActivatedApp(
      appRef: appRef,
      activate: resolvedAction == kAXRaiseAction as String || resolvedAction == kAXPressAction as String,
      restorePreviousFocus: resolvedAction != kAXRaiseAction as String
    ) {
      if AXUIElementPerformAction(element, resolvedAction as CFString) == .success {
        return true
      }

      if resolvedAction == kAXPressAction as String, let bounds = axBounds(element) {
        let center = CGPoint(x: bounds.x + (bounds.width / 2), y: bounds.y + (bounds.height / 2))
        OverlayCursorController.shared.animate(to: center)
        let clicked = postClick(at: center)
        OverlayCursorController.shared.pulse()
        OverlayCursorController.shared.scheduleIdleHide()
        return clicked
      }

      if resolvedAction == kAXRaiseAction as String {
        if let app = resolveApp(appRef) {
          app.activate()
          return true
        }
      }

      return false
    }
  }

  if !success {
    return makeErrorResult(
      toolName: "perform_secondary_action",
      code: "accessibility_error",
      message: "Accessibility error: Unable to perform action \(action)"
    )
  }

  usleep(120_000)
  return getAppStateResult(appRef: appRef)
}

func scrollResult(params: [String: JSONValue]) -> ResultPayload {
  guard case .string(let appRef)? = params["app"] else {
    return makeErrorResult(toolName: "scroll", code: "internal_error", message: "Missing app parameter")
  }
  guard case .string(let direction)? = params["direction"] else {
    return makeErrorResult(toolName: "scroll", code: "internal_error", message: "Missing direction parameter")
  }

  let pages: Int
  if case .number(let rawPages)? = params["pages"] {
    pages = max(Int(rawPages), 1)
  } else {
    pages = 1
  }

  guard let entry = (resolveApp(appRef).flatMap { windowInfo(for: $0.processIdentifier) }) ?? resolveWindowEntry(appRef) else {
    return makeErrorResult(toolName: "scroll", code: "app_not_found", message: "appNotFound(\"\(appRef)\")")
  }

  let delta = 480 * pages
  let success = withActivatedApp(appRef: appRef) {
    let center = CGPoint(x: entry.bounds.midX, y: entry.bounds.midY)
    OverlayCursorController.shared.animate(to: center, duration: 0.14)
    guard let mouseMove = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left) else {
      return false
    }
    mouseMove.post(tap: .cghidEventTap)
    usleep(60_000)

    guard let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 2,
      wheel1: 0,
      wheel2: 0,
      wheel3: 0
    ) else {
      return false
    }

    event.location = center
    switch direction.lowercased() {
    case "up":
      event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(delta))
      event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(delta))
      event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64(delta * 65536))
    case "down":
      event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(-delta))
      event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(-delta))
      event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64(-delta * 65536))
    case "left":
      event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(delta))
      event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(delta))
      event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Int64(delta * 65536))
    case "right":
      event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(-delta))
      event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(-delta))
      event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Int64(-delta * 65536))
    default:
      return false
    }

    event.post(tap: .cghidEventTap)
    OverlayCursorController.shared.pulse()
    OverlayCursorController.shared.scheduleIdleHide(after: 1.0)
    return true
  }

  if !success {
    return makeErrorResult(
      toolName: "scroll",
      code: "unsupported_action",
      message: "Native helper does not support scroll direction: \(direction)"
    )
  }

  usleep(120_000)
  return getAppStateResult(appRef: appRef)
}

while let line = readLine() {
  if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    continue
  }

  do {
    let request = try decoder.decode(Request.self, from: Data(line.utf8))
    let result: ResultPayload

    switch request.method {
    case "list_apps":
      result = listAppsResult()
    case "get_app_state":
      guard case .string(let appRef)? = request.params["app"] else {
        result = makeErrorResult(toolName: "get_app_state", code: "internal_error", message: "Missing app parameter")
        writeResponse(Response(id: request.id, ok: result.ok, result: result, error: nil))
        continue
      }
      result = getAppStateResult(appRef: appRef)
    case "click":
      result = clickResult(params: request.params)
    case "drag":
      result = dragResult(params: request.params)
    case "type_text":
      result = typeTextResult(params: request.params)
    case "press_key":
      result = pressKeyResult(params: request.params)
    case "perform_secondary_action":
      result = performSecondaryActionResult(params: request.params)
    case "set_value":
      result = setValueResult(params: request.params)
    case "scroll":
      result = scrollResult(params: request.params)
    default:
      result = makeErrorResult(toolName: request.method, code: "unsupported_action", message: "Unsupported helper method: \(request.method)")
    }

    writeResponse(Response(id: request.id, ok: true, result: result, error: nil))
  } catch {
    writeResponse(Response(id: "unknown", ok: false, result: nil, error: String(describing: error)))
  }
}
