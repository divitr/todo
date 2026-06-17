import SwiftData
import SwiftUI

struct SidebarView: View {
    @Binding var destination: MainDestination
    let projects: [Project]
    let allTasks: [TaskItem]
    var onEditCategory: (Project) -> Void = { _ in }
    var onAddTask: () -> Void
    var onAddCategory: () -> Void

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
    }

    private var userCategories: [Project] {
        projects.filter(\.isUserCategory).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var openTaskCount: Int {
        allTasks.filter { !$0.isComplete }.count
    }

    private var todayOpenCount: Int {
        TaskFilters.today(allTasks).count
    }

    var body: some View {
        List(selection: $destination) {
            Section {
                Button(action: onAddTask) {
                    sidebarLabel(
                        icon: "plus.circle.fill",
                        title: "Add task",
                        isSelected: false,
                        titleWeight: .semibold,
                        iconAccent: true
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(rowInsets)
                .listRowBackground(Color.clear)
            }

            Section {
                navRow(.inbox, trailing: "\(openTaskCount)")
                navRow(.today, trailing: "\(todayOpenCount)")
                navRow(.upcoming)
            }

            Section("Categories") {
                ForEach(userCategories) { project in
                    categoryRow(project)
                }

                Button(action: onAddCategory) {
                    sidebarLabel(icon: "plus", title: "New category", isSelected: false, muted: true)
                }
                .buttonStyle(.plain)
                .listRowInsets(rowInsets)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .listRowSeparator(.hidden)
        .tint(Theme.primary)
        .navigationTitle("todo")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .environment(\.appAccent, Theme.defaultAccent)
        .environment(\.defaultMinListRowHeight, 34)
    }

    @ViewBuilder
    private func navRow(_ item: MainDestination, trailing: String? = nil) -> some View {
        let isSelected = destination == item
        sidebarLabel(
            icon: item.systemImage,
            title: item.title,
            isSelected: isSelected,
            trailing: trailing
        )
        .tag(item)
        .listRowInsets(rowInsets)
        .listRowBackground(
            SidebarRowBackground(isSelected: isSelected, tint: Theme.muted, horizontalInset: 4)
        )
    }

    @ViewBuilder
    private func categoryRow(_ project: Project) -> some View {
        let item = MainDestination.category(project.persistentModelID)
        let isSelected = destination == item

        HStack(spacing: 8) {
            Text(project.hashTag)
                .font(Theme.sans(14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.primary : project.categoryColor)
            Spacer(minLength: 0)
            Text("\(project.openTaskCount)")
                .font(Theme.sans(12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.secondary : Theme.faint)
        }
        .tag(item)
        .listRowInsets(rowInsets)
        .listRowBackground(
            CategoryRowSelectionBackground(isSelected: isSelected, tint: project.categoryColor, horizontalInset: 4)
        )
        .contextMenu {
            Button("Edit category…") { onEditCategory(project) }
        }
    }

    private func sidebarLabel(
        icon: String,
        title: String,
        isSelected: Bool,
        trailing: String? = nil,
        titleWeight: Font.Weight = .regular,
        muted: Bool = false,
        iconAccent: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconForeground(isSelected: isSelected, muted: muted, iconAccent: iconAccent))
                .frame(width: Theme.sidebarIconWidth, alignment: .center)
            Text(title)
                .font(Theme.sans(14, weight: isSelected ? .semibold : titleWeight))
                .foregroundStyle(titleForeground(isSelected: isSelected, muted: muted))
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Theme.sans(12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.secondary : Theme.faint)
            }
        }
        .contentShape(Rectangle())
    }

    private func titleForeground(isSelected: Bool, muted: Bool) -> Color {
        if isSelected { return Theme.primary }
        return muted ? Theme.muted : Theme.primary
    }

    private func iconForeground(isSelected: Bool, muted: Bool, iconAccent: Bool) -> Color {
        if iconAccent { return Theme.primary }
        if muted { return Theme.muted }
        return isSelected ? Theme.primary : Theme.secondary
    }
}
