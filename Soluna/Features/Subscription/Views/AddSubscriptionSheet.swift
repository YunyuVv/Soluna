//
//  AddSubscriptionSheet.swift
//  Soluna
//

import SwiftUI

/// `AddSubscriptionSheet` 的作用：添加订阅弹窗，支持频道 ID / 链接 / @handle。
struct AddSubscriptionSheet: View {
    @Bindable var viewModel: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var isResolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加订阅")
                .font(.title3.weight(.semibold))

            Text("支持 YouTube 频道 ID（UC 开头）、频道链接或 @handle。无需登录，仅通过公开 RSS 检测更新。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("粘贴频道 ID / 链接 / @handle", text: $inputText)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    Task {
                        isResolving = true
                        await viewModel.addSubscription(input: inputText)
                        isResolving = false
                        if viewModel.errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    if isResolving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("订阅")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isResolving)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { viewModel.clearErrorMessage() }
    }
}
