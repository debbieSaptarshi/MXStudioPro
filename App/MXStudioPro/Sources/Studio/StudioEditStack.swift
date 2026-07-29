import Foundation

/// Lightweight undo stack for Week 5 arrangement edits (trim / move / delete).
struct StudioEditStack {
    private var undoItems: [MXProject] = []
    private let limit = 30

    var canUndo: Bool { !undoItems.isEmpty }

    mutating func push(_ project: MXProject) {
        undoItems.append(project)
        if undoItems.count > limit {
            undoItems.removeFirst(undoItems.count - limit)
        }
    }

    mutating func pop() -> MXProject? {
        undoItems.popLast()
    }

    mutating func clear() {
        undoItems.removeAll()
    }
}
