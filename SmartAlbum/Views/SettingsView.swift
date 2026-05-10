import SwiftUI

// MARK: - 设置页

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showSavedToast = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: AI 配置
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API 地址")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://dashscope.aliyuncs.com/compatible-mode/v1", text: $viewModel.endpoint)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("模型名称")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("qwen-vl-max", text: $viewModel.model)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $viewModel.apiKey)
                    }

                    Button {
                        viewModel.saveSettings()
                        showSavedToast = true
                    } label: {
                        Text("保存配置")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } header: {
                    Text("AI 配置")
                } footer: {
                    Text("当前默认使用通义千问（qwen-vl-max），也可切换为 GPT-4o 等兼容接口")
                }

                // MARK: 使用说明
                Section("使用说明") {
                    Label("在「相册」页点击右上角魔法棒按钮，开始批量分析", systemImage: "wand.and.stars")
                    Label("在照片详情页可对单张照片手动分析", systemImage: "sparkles")
                    Label("在「搜索」页可按标签、描述关键词查找照片", systemImage: "magnifyingglass")
                }

                // MARK: 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("最低系统")
                        Spacer()
                        Text("iOS 17.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .overlay(alignment: .top) {
                if showSavedToast {
                    Text("配置已保存")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Material.ultraThin)
                        .cornerRadius(20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showSavedToast = false }
                            }
                        }
                        .padding(.top, 8)
                }
            }
        }
    }
}
