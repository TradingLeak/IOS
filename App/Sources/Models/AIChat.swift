import Foundation

/// Một bong bóng trong cửa sổ trợ lý AI.
struct AIChatBubble: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var isError: Bool = false
}
