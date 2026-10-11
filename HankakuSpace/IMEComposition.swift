import ApplicationServices
import Foundation

/// Whether the focused text field has uncommitted IME text.
///
/// The marked-text Accessibility attributes are not part of the public AX
/// constants and are only available in applications that expose them.
/// Unknown states must not cause us to synthesize Shift+Space, since doing so
/// could navigate the candidate list backwards instead of converting text.
enum IMEComposition {
    enum State {
        case composing
        case idle
        case unknown
    }

    private static let queryTimeout: Float = 0.05

    static func state() -> State {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, queryTimeout)

        var focusedReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedReference
        ) == .success,
        let focusedReference,
        CFGetTypeID(focusedReference) == AXUIElementGetTypeID()
        else {
            return .unknown
        }

        let focusedElement = focusedReference as! AXUIElement
        AXUIElementSetMessagingTimeout(focusedElement, queryTimeout)

        // AppKit text fields typically return an AXValue containing a CFRange.
        var markedReference: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            focusedElement, "AXTextInputMarkedRange" as CFString, &markedReference
        )

        switch status {
        case .success:
            guard let markedReference,
                  CFGetTypeID(markedReference) == AXValueGetTypeID()
            else { return .unknown }

            var markedRange = CFRange()
            guard AXValueGetValue(markedReference as! AXValue, .cfRange, &markedRange)
            else { return .unknown }

            return markedRange.length > 0 ? .composing : .idle

        case .noValue:
            // The field supports this attribute but has no marked text.
            return .idle

        default:
            // Chromium and other clients can expose text marker ranges instead.
            return textMarkerState(for: focusedElement)
        }
    }

    private static func textMarkerState(for element: AXUIElement) -> State {
        var markerReference: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element, "AXTextInputMarkedTextMarkerRange" as CFString, &markerReference
        )

        switch status {
        case .noValue:
            return .idle

        case .success:
            guard let markerReference else { return .unknown }

            var lengthReference: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXLengthForTextMarkerRange" as CFString,
                markerReference,
                &lengthReference
            ) == .success,
            let length = lengthReference as? NSNumber
            else { return .unknown }

            return length.intValue > 0 ? .composing : .idle

        default:
            return .unknown
        }
    }
}
