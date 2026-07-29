import Foundation

/// Lightweight undo/redo stack for arrangement edits (trim / move / delete / fades).
struct StudioEditStack {
    private var undoItems: [MXProject] = []
    private var redoItems: [MXProject] = []
    private let limit = 30

    var canUndo: Bool { !undoItems.isEmpty }
    var canRedo: Bool { !redoItems.isEmpty }

    /// Push a snapshot before mutating. Clears the redo branch (BandLab / Logic style).
    mutating func push(_ project: MXProject) {
        undoItems.append(project)
        if undoItems.count > limit {
            undoItems.removeFirst(undoItems.count - limit)
        }
        redoItems.removeAll()
    }

    /// Pop undo; push `current` onto redo so the edit can be reapplied.
    mutating func undo(current: MXProject) -> MXProject? {
        guard let previous = undoItems.popLast() else { return nil }
        redoItems.append(current)
        if redoItems.count > limit {
            redoItems.removeFirst(redoItems.count - limit)
        }
        return previous
    }

    /// Pop redo; push `current` onto undo.
    mutating func redo(current: MXProject) -> MXProject? {
        guard let next = redoItems.popLast() else { return nil }
        undoItems.append(current)
        if undoItems.count > limit {
            undoItems.removeFirst(undoItems.count - limit)
        }
        return next
    }

    mutating func clear() {
        undoItems.removeAll()
        redoItems.removeAll()
    }
}
