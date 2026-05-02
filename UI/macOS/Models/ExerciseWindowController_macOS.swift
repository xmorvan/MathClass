//
//  ExerciseWindowController_macOS.swift
//  MathClass
//
//  Created by Xavier Morvan on 25.02.2025.
//


import SwiftUI
import AppKit

class ExerciseWindowController: NSWindowController, NSWindowDelegate {
    private var hostingController: NSHostingController<AnyView>?
    private let onClose: () -> Void
    
    static func create(
        title: String,
        width: CGFloat = 1024,
        height: CGFloat = 768,
        content: some View,
        onClose: @escaping () -> Void
    ) -> ExerciseWindowController {
        // Créer le contenu SwiftUI
        let hostingController = NSHostingController(rootView: AnyView(content))
        
        // Créer la fenêtre
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = hostingController
        window.setFrameAutosaveName("ExerciseEditor")
        window.center()
        
        // Créer et retourner le contrôleur
        let controller = ExerciseWindowController(window: window, onClose: onClose)
        controller.hostingController = hostingController
        window.delegate = controller
        
        return controller
    }
    
    private init(window: NSWindow?, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
