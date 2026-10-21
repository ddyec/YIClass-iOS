import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import YIClassCore

struct AssistantView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("ai.mode") private var modeName = AssistantMode.onDevice.rawValue
    @AppStorage("ai.endpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("ai.model") private var model = ""
    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var modelHistory: [ChatMessage] = []
    @State private var reply: AssistantReply?
    @State private var snapshot: PlanSnapshot?
    @State private var selections: [String: String] = [:]
    @State private var busy = false
    @State private var requestTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var selectedPlan: PlanSelection?
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    private var mode: AssistantMode { AssistantMode(rawValue: modeName) ?? .onDevice }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            Text(message.content).font(.subheadline).textSelection(.enabled)
                                .padding(14).frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                                .background(message.role == "user" ? Color.indigo.opacity(0.1) : Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 18))
                        }
                        if let reply {
                            questionChoices(reply)
                            ForEach(reply.plans) { plan in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(plan.title).font(.headline)
                                    Text(plan.explanation).font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(plan.courses.count) 门课程 · \(ScheduleEngine.conflictCount(courses: plan.courses.map { $0.materialize() })) 组冲突")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button("查看变更并选择") {
                                        if let snapshot { selectedPlan = PlanSelection(plan: plan, snapshot: snapshot) }
                                    }.buttonStyle(.glassProminent)
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                            }
                        }
                        if busy { HStack { ProgressView(); Text("正在整理…").foregroundStyle(.secondary); Spacer(); Button("取消") { cancel() } } }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(18)
                }
                .background { AppBackdrop() }
                .onChange(of: messages.count) { _, _ in reader.scrollTo("end", anchor: .bottom) }
                .safeAreaInset(edge: .bottom) { composer }
                .navigationTitle("课表助手")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("新对话", systemImage: "square.and.pencil") { reset() } }
                }
            }
            .sheet(item: $selectedPlan) { PlanReviewView(plan: $0.plan, snapshot: $0.snapshot) {
                reset()
                messages = [ChatMessage(role: "assistant", content: "方案已应用到当前课表。可以切换到课表查看，也可以在这里撤销。")]
            } }
            .onChange(of: store.table.id) { _, _ in reset() }
            .onChange(of: store.table) { _, _ in invalidatePlans() }
            .onChange(of: store.profile) { _, _ in invalidatePlans() }
            .onChange(of: modeName) { _, _ in reset() }
            .onChange(of: photo) { _, value in
                guard let value else { return }
                Task {
                    do {
                        guard let data = try await value.loadTransferable(type: Data.self) else { throw AppFailure("图片读取失败。") }
                        input = String(try await ImageTextRecognition.recognize(data).prefix(20_000))
                    } catch { store.error = error.localizedDescription }
                    photo = nil
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .commaSeparatedText]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 200_000 else { throw AppFailure("文本文件不能超过 200 KB。") }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    guard text.count <= 20_000 else { throw AppFailure("请将文本缩减至 20,000 字以内。") }
                    input = text
                } catch { store.error = error.localizedDescription }
            }
        }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.indigo.gradient)
            Text("一起找到合适的安排").font(.title2.bold())
            Text("描述想新增或调整的课程。不够明确时，我会先给你几个选项；方案会先预览，再由你应用。")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(mode == .onDevice ? AIService.availability : "发送时，当前课表与本次对话将交给你配置的 AI 服务。")
                .font(.caption).foregroundStyle(.secondary)
            NavigationLink("\(mode.rawValue) · 配置", destination: AISettingsView()).font(.caption)
            if store.undoData != nil {
                Button("撤销最近一次更改", systemImage: "arrow.uturn.backward") {
                    store.perform { try store.undo() }
                }.font(.subheadline)
            }
            if messages.isEmpty {
                Button("试试：我想每周安排两次自习，怎么选时间？") {
                    input = "我想每周安排两次自习，怎么选时间？"
                }.font(.subheadline)
            }
        }
    }
    private func questionChoices(_ reply: AssistantReply) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(reply.questions) { question in
                Text(question.title).font(.headline)
                ForEach(question.options, id: \.self) { option in
                    Button { selections[question.title] = option } label: {
                        HStack {
                            Image(systemName: selections[question.title] == option ? "checkmark.circle.fill" : "circle")
                            Text(option).multilineTextAlignment(.leading)
                            Spacer()
                        }.padding(12).background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(busy)
                }
            }
            if !reply.questions.isEmpty {
                Button("按所选继续生成") {
                    let answer = reply.questions.map { "\($0.title)：\(selections[$0.title] ?? "")" }.joined(separator: "\n")
                    send(answer)
                }.buttonStyle(.glassProminent)
                    .disabled(busy || reply.questions.contains { selections[$0.title] == nil })
            }
        }
    }
    private var composer: some View {
        GlassPanel {
            VStack(spacing: 8) {
                TextField("描述课程，或补充你的偏好…", text: $input, axis: .vertical).lineLimit(1...5)
                    .padding(.horizontal, 4).disabled(busy)
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) { Label("截图识字", systemImage: "photo") }.disabled(busy)
                    Button("文本 / CSV", systemImage: "doc") { importing = true }.disabled(busy)
                    Spacer()
                    Button("发送", systemImage: "arrow.up") { send(input) }
                        .labelStyle(.iconOnly).buttonStyle(.glassProminent)
                        .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.font(.caption)
            }
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }
    private func send(_ text: String) {
        guard !busy else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 20_000 else { store.error = "请输入 1–20,000 字的说明。"; return }
        guard messages.reduce(0, { $0 + $1.content.count }) + text.count <= 40_000 else {
            store.error = "这段对话过长，请开始新对话，并简要说明需求。"; return
        }
        input = ""; busy = true; reply = nil; selections = [:]
        messages.append(ChatMessage(role: "user", content: text))
        modelHistory.append(ChatMessage(role: "user", content: text))
        let captured = PlanSnapshot(table: store.table, profile: store.profile)
        snapshot = captured
        let history = modelHistory
        let token = UUID(); requestID = token
        requestTask = Task {
            do {
                let result = try await AIService.reply(mode: mode, messages: history, table: captured.table,
                    profile: captured.profile, endpoint: endpoint, model: model)
                try Task.checkCancellation()
                guard token == requestID else { return }
                try captured.check(current: store.table, profile: store.profile)
                // Keep the full structured answer in model history, but display human-readable text only.
                reply = result
                messages.append(ChatMessage(role: "assistant", content: result.message))
                let structured = try JSONEncoder().encode(result)
                modelHistory.append(ChatMessage(role: "assistant", content: String(decoding: structured, as: UTF8.self)))
            } catch is CancellationError { }
            catch {
                if token == requestID {
                    store.error = error.localizedDescription; input = text
                    modelHistory = Array(history.dropLast())
                    if messages.last?.role == "user", messages.last?.content == text { messages.removeLast() }
                }
            }
            if token == requestID { busy = false; requestTask = nil }
        }
    }
    private func cancel() { requestID = UUID(); requestTask?.cancel(); requestTask = nil; busy = false }
    private func invalidatePlans() { cancel(); reply = nil; snapshot = nil; selectedPlan = nil; selections = [:] }
    private func reset() { invalidatePlans(); messages = []; modelHistory = []; input = "" }
}

private struct PlanSelection: Identifiable {
    let id = UUID(); let plan: AssistantPlan; let snapshot: PlanSnapshot
}

struct PlanReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: AssistantPlan
    let snapshot: PlanSnapshot
    let onApply: () -> Void
    @State private var removedConfirmation = false
    private var proposed: [Course] { plan.courses.map { $0.materialize() } }
    private var removed: [Course] { snapshot.table.courses.filter { old in !proposed.contains { $0.id == old.id } } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(plan.explanation)
                    Text("应用到“\(snapshot.table.name)”。统一课节时间保持为设置中的值。")
                        .font(.footnote).foregroundStyle(.secondary)
                    let conflicts = ScheduleEngine.conflictCount(courses: proposed)
                    Label("\(conflicts) 组课程冲突", systemImage: conflicts > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(conflicts > 0 ? Color.orange : Color.green)
                }
                Section("应用后的课程（\(proposed.count) 门）") {
                    ForEach(Array(proposed.enumerated()), id: \.offset) { _, course in
                        let old = snapshot.table.courses.first { $0.id == course.id }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(course.name).font(.headline)
                            Text(old == nil ? "新增" : (old == course ? "保留" : "已调整"))
                                .font(.caption).foregroundStyle(old == course ? Color.secondary : Color.indigo)
                            ForEach(course.schedules.indices, id: \.self) { index in
                                let schedule = course.schedules[index]
                                Text("\(weekdayNames[schedule.weekday - 1]) · 第 \(schedule.periods.map(String.init).joined(separator: ",")) 节 · 第 \(schedule.weekPattern.map(String.init).joined(separator: ",")) 周")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !removed.isEmpty {
                    Section("将移除 \(removed.count) 门课程") {
                        ForEach(removed) { Text($0.name).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle(plan.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用方案") { if removed.isEmpty { apply() } else { removedConfirmation = true } }
                }
            }
            .confirmationDialog("方案会移除 \(removed.count) 门现有课程", isPresented: $removedConfirmation, titleVisibility: .visible) {
                Button("应用这份方案", role: .destructive) { apply() }
            }
        }
    }
    private func apply() {
        do { try store.apply(plan, snapshot: snapshot); dismiss(); onApply() }
        catch { store.error = error.localizedDescription }
    }
}

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("ai.mode") private var savedMode = AssistantMode.onDevice.rawValue
    @AppStorage("ai.endpoint") private var savedEndpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("ai.model") private var savedModel = ""
    @State private var mode = AssistantMode.onDevice
    @State private var endpoint = ""
    @State private var model = ""
    @State private var apiKey = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Picker("处理方式", selection: $mode) {
                    ForEach(AssistantMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text(AIService.availability).font(.footnote).foregroundStyle(.secondary)
            }
            if mode == .remote {
                Section {
                    TextField("完整 Chat Completions HTTPS 地址", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("模型名称", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("OpenAI 兼容接口") } footer: {
                    Text("API Key 仅保存在本机钥匙串。发送后，当前课表和对话会交给此服务；图片先在本机识字，识别文字可检查修改后再发送。支持提供 OpenAI 兼容接口的服务，暂不直接支持 Claude / Gemini 原生协议。")
                }
            }
            Section {
                Text("设备端助手需要支持 Apple Intelligence 的机型、地区及语言，并完成模型下载。iOS 26 并不代表设备端模型一定可用。两种模式均会校验方案，且必须由你选择应用。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("AI 配置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try APIKeyStore.save(apiKey)
                            savedMode = mode.rawValue; savedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                            savedModel = model.trimmingCharacters(in: .whitespacesAndNewlines); dismiss()
                        } catch { store.error = error.localizedDescription }
                    }
                }
            }.onAppear {
                mode = AssistantMode(rawValue: savedMode) ?? .onDevice; endpoint = savedEndpoint; model = savedModel
                do { apiKey = try APIKeyStore.read() } catch { store.error = error.localizedDescription }
            }
    }
}
