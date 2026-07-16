import SwiftUI
import UIKit

/// Installs one non-blocking window tap recognizer so tapping outside an input ends editing.
struct KeyboardDismissalView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> KeyboardDismissalViewController {
        KeyboardDismissalViewController()
    }

    func updateUIViewController(_ uiViewController: KeyboardDismissalViewController, context: Context) {}
}

final class KeyboardDismissalViewController: UIViewController, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var dismissalTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installRecognizerIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeRecognizer()
    }

    private func installRecognizerIfNeeded() {
        guard installedWindow == nil, let window = view.window else { return }
        dismissalTap.cancelsTouchesInView = false
        dismissalTap.delegate = self
        window.addGestureRecognizer(dismissalTap)
        installedWindow = window
    }

    private func removeRecognizer() {
        installedWindow?.removeGestureRecognizer(dismissalTap)
        installedWindow = nil
    }

    @objc private func dismissKeyboard() {
        installedWindow?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView: UIView? = touch.view
        while let view = touchedView {
            if view is UITextField || view is UITextView {
                return false
            }
            touchedView = view.superview
        }
        return true
    }
}
