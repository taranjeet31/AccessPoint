import SwiftUI
import RemoteControllerCore

#if os(iOS)
import UIKit

public struct SoftKeyboardBridge: UIViewRepresentable {
    @Binding public var isKeyboardActive: Bool
    public let onTextInput: (String) -> Void
    public let onSpecialKey: (UInt16) -> Void

    public init(
        isKeyboardActive: Binding<Bool>,
        onTextInput: @escaping (String) -> Void,
        onSpecialKey: @escaping (UInt16) -> Void
    ) {
        self._isKeyboardActive = isKeyboardActive
        self.onTextInput = onTextInput
        self.onSpecialKey = onSpecialKey
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> CustomHiddenTextField {
        let textField = CustomHiddenTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.onDeleteBackward = {
            self.onSpecialKey(MacVirtualKeyCode.delete.code)
        }
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.keyboardAppearance = .dark
        return textField
    }

    public func updateUIView(_ uiView: CustomHiddenTextField, context: Context) {
        if isKeyboardActive && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isKeyboardActive && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    public class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SoftKeyboardBridge

        init(_ parent: SoftKeyboardBridge) {
            self.parent = parent
        }

        public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty {
                // Delete/Backspace
                parent.onSpecialKey(MacVirtualKeyCode.delete.code)
            } else {
                parent.onTextInput(string)
            }
            // Always return false so text field buffer stays empty
            return false
        }

        public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSpecialKey(MacVirtualKeyCode.returnKey.code)
            return false
        }
    }
}

public class CustomHiddenTextField: UITextField {
    public var onDeleteBackward: (() -> Void)?

    public override func deleteBackward() {
        super.deleteBackward()
        onDeleteBackward?()
    }
}

#elseif os(macOS)
import AppKit

public struct SoftKeyboardBridge: View {
    @Binding public var isKeyboardActive: Bool
    public let onTextInput: (String) -> Void
    public let onSpecialKey: (UInt16) -> Void

    public init(
        isKeyboardActive: Binding<Bool>,
        onTextInput: @escaping (String) -> Void,
        onSpecialKey: @escaping (UInt16) -> Void
    ) {
        self._isKeyboardActive = isKeyboardActive
        self.onTextInput = onTextInput
        self.onSpecialKey = onSpecialKey
    }

    public var body: some View {
        EmptyView()
    }
}
#endif
