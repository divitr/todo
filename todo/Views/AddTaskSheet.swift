import SwiftData
import SwiftUI

struct AddTaskSheet: View {
    let projects: [Project]
    var defaultDueDate: Date?
    var defaultProject: Project?
    var peerTasks: [TaskItem] = []
    var onDismiss: () -> Void

    var body: some View {
        AddTaskComposerView(
            projects: projects,
            defaultProject: defaultProject,
            defaultDueDate: defaultDueDate,
            peerTasks: peerTasks,
            onCancel: onDismiss,
            onSaved: onDismiss
        )
        .padding(24)
        .frame(width: 600)
        .frame(maxHeight: 640)
        .appBackground()
    }
}
