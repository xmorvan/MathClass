//
//  ClassPickerBar.swift
//  MathClass
//
//  Class selector for screens that show one class at a time (assignments).
//  Selecting a class starts its listeners through TeacherViewModel.selectClass;
//  without it, those screens stayed empty until a class had been opened in
//  the Classes tab.
//

import SwiftUI

struct ClassPickerBar: View {
    @ObservedObject var viewModel: TeacherViewModel

    var body: some View {
        HStack {
            Text("Classe".tr)
                .foregroundColor(.secondary)
            Picker("Classe".tr, selection: Binding(
                get: { viewModel.selectedClassID ?? "" },
                set: { newID in
                    if !newID.isEmpty { viewModel.selectClass(newID) }
                }
            )) {
                ForEach(viewModel.classes) { classRoom in
                    Text(classRoom.name).tag(classRoom.id ?? "")
                }
            }
            .labelsHidden()
            Spacer()
        }
        .onAppear(perform: selectFirstClassIfNeeded)
        .onChange(of: viewModel.classes.count) { _, _ in selectFirstClassIfNeeded() }
    }

    private func selectFirstClassIfNeeded() {
        let known = Set(viewModel.classes.compactMap(\.id))
        if let current = viewModel.selectedClassID, known.contains(current) { return }
        if let first = viewModel.classes.first?.id {
            viewModel.selectClass(first)
        }
    }
}
