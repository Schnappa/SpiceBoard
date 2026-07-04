import SwiftUI
import AppKit

class NativeWindowManager: NSObject, NSWindowDelegate {
    static let shared = NativeWindowManager()
    
    private var windows: [String: NSWindow] = [:]
    
    // Keep track of closure callbacks to update SwiftUI states if needed
    private var closeCallbacks: [String: () -> Void] = [:]
    
    func openWindow<Content: View>(
        id: String,
        title: String,
        width: CGFloat,
        height: CGFloat,
        isResizable: Bool = true,
        store: UsenetStore,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        // If window already exists, bring it to front
        if let existingWindow = windows[id] {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Define style mask
        let styleMask: NSWindow.StyleMask = isResizable
            ? [.titled, .closable, .miniaturizable, .resizable, .utilityWindow]
            : [.titled, .closable, .miniaturizable, .utilityWindow]
        
        // Create an NSPanel (which is a subclass of NSWindow that floats beautifully)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.level = .floating // True floating utility window
        panel.center()
        
        // Store close callback
        if let onClose = onClose {
            closeCallbacks[id] = onClose
        }
        
        // Inject store environment and wrap in a clean container with padding/styling
        let viewWithStore = content()
            .environment(store)
        
        let hostingView = NSHostingView(rootView: viewWithStore)
        panel.contentView = hostingView
        panel.delegate = self
        
        // Assign identifier
        panel.identifier = NSUserInterfaceItemIdentifier(id)
        
        windows[id] = panel
        panel.makeKeyAndOrderFront(nil)
    }
    
    func closeWindow(id: String) {
        if let window = windows[id] {
            window.close()
            windows.removeValue(forKey: id)
            closeCallbacks[id]?()
            closeCallbacks.removeValue(forKey: id)
        }
    }
    
    // NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           let id = window.identifier?.rawValue {
            windows.removeValue(forKey: id)
            closeCallbacks[id]?()
            closeCallbacks.removeValue(forKey: id)
        }
    }
}
