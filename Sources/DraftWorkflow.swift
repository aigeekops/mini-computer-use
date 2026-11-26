import Foundation

struct Draft: Codable, Equatable {
    let title: String
    let reviewed: Bool
}

struct FormState {
    let title: String
    let reviewed: Bool
    let canSave: Bool
    let receipt: String
}

enum FormAction: CustomStringConvertible {
    case enterTitle(String)
    case markReviewed
    case saveDraft

    var description: String {
        switch self {
        case .enterTitle(let title): "Enter title: \(title)"
        case .markReviewed: "Mark reviewed"
        case .saveDraft: "Save draft"
        }
    }

    func tookEffect(in state: FormState, goal: Draft) -> Bool {
        switch self {
        case .enterTitle(let title): state.title == title
        case .markReviewed: state.reviewed && state.canSave
        case .saveDraft: state.receipt == DraftWorkflow.receipt(for: goal)
        }
    }
}

enum DraftWorkflow {
    static let goal = Draft(title: "Monthly report", reviewed: true)

    static func receipt(for draft: Draft) -> String { "Saved: \(draft.title)" }

    static func nextAction(from state: FormState) throws -> FormAction? {
        if state.receipt == receipt(for: goal) { return nil }
        if state.title != goal.title { return .enterTitle(goal.title) }
        if !state.reviewed { return .markReviewed }
        guard state.canSave else { throw DemoError("Save Draft is disabled.") }
        return .saveDraft
    }

    static func verifyDraft(at url: URL) throws {
        let draft = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: url))
        guard draft == goal else { throw DemoError("The saved draft differs from the task goal.") }
    }
}

struct DemoError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}
