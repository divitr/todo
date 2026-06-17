import SwiftData
import SwiftUI

struct CategoryEditorSheet: View {
    @Bindable var project: Project
    var onDismiss: () -> Void
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var color: Color = .gray

    var body: some View {
        Group {
            if project.isSystemCategory {
                VStack(alignment: .leading, spacing: 12) {
                    Text("System category")
                        .font(Theme.sans(20, weight: .bold))
                    Text(project.isAllAggregate
                        ? "#all is fixed and always shows every category on the timeline."
                        : "This category can’t be edited.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.muted)
                    HStack {
                        Spacer()
                        Button("OK", action: onDismiss)
                            .buttonStyle(MonoProminentButtonStyle())
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Edit category")
                        .font(Theme.sans(20, weight: .bold))

                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Bar color")
                            .font(Theme.sans(13))
                        Spacer()
                        ColorPicker("", selection: $color, supportsOpacity: false)
                            .labelsHidden()
                    }

                    HStack {
                        Spacer()
                        Button("Cancel", action: onDismiss)
                        Button("Save") {
                            project.name = Project.normalizedCategoryName(name)
                            project.applyColor(color)
                            onSaved()
                        }
                        .buttonStyle(MonoProminentButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            guard project.isUserCategory else { return }
            name = project.displayTitle
            color = project.usesCustomColor
                ? Color(red: project.colorRed, green: project.colorGreen, blue: project.colorBlue)
                : Project.defaultPaletteColor(at: project.sortOrder)
        }
    }
}
