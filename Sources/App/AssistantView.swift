import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import YIClassCore

struct AssistantView: View {
    var importMode = false
    @State private var importTable: Timetable?
    @State private var sourceText = ""
    @State private var sourceGrid: PDFGridDocument?
    @State private var directImport: ImportPreview?
    @State private var pendingImport: ImportPreview?
    @State private var sourceIssue: String?
    @State private var sourceReview = false
    @State private var reading = false
    @State private var localError: String?
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
                            Text(message.content.hasPrefix("请将以下课表资料") ? "已提交课表资料，请识别并生成导入方案。" : message.content).font(.subheadline).textSelection(.enabled)
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
                        if reading { ProgressView("正在读取课表…") }
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
            .sheet(item: $selectedPlan) { PlanReviewView(plan: $0.plan, snapshot: $0.snapshot, importing: importMode) {
                reset()
                messages = [ChatMessage(role: "assistant", content: importMode ? "课表已导入，可在课表页切换查看。" : "方案已应用。")]
            } }
            .sheet(isPresented: $sourceReview, onDismiss: {
                if let pendingImport { directImport = pendingImport; self.pendingImport = nil }
            }) { sourceReviewView }
            .sheet(isPresented: Binding(get: { directImport != nil }, set: { if !$0 { directImport = nil } })) {
                if let directImport { ImportReviewView(preview: directImport) }
            }
            .alert("识别未完成", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("好", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
            .onChange(of: store.table.id) { _, _ in reset() }
            .onChange(of: store.table) { _, _ in invalidatePlans() }
            .onChange(of: store.profile) { _, _ in invalidatePlans() }
            .onChange(of: modeName) { _, _ in reset() }
            .onChange(of: photo) { _, value in
                guard let value else { return }
                reading = true
                Task {
                    do {
                        guard let data = try await value.loadTransferable(type: Data.self) else { throw AppFailure("图片读取失败。") }
                        sourceGrid = nil
                        sourceText = try await ImageTextRecognition.recognize(data)
                        sourceReview = true
                    } catch { localError = error.localizedDescription }
                    photo = nil; reading = false
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .commaSeparatedText, .pdf, .image]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20_000_000 else { throw AppFailure("文件不能超过 20 MB。") }
                    let bytes = try Data(contentsOf: url)
                    let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
                    reading = true
                    Task {
                        do {
                            let payload = try await ImportSource.read(bytes, type: type)
                            sourceText = payload.text; sourceGrid = payload.grid
                            sourceReview = true
                        } catch { localError = error.localizedDescription }
                        reading = false
                    }
                } catch { localError = error.localizedDescription }
            }
        }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.indigo.gradient)
            Text(importMode ? "AI 导入课表" : "一起找到合适的安排").font(.title2.bold())
            Text(importMode ? "选择截图、PDF 或文本，识别后预览导入。" : "说说你的想法，选好方案再应用。")
                .font(.subheadline).foregroundStyle(.secondary)
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
                    PhotosPicker(selection: $photo, matching: .images) { Label("课表截图", systemImage: "photo") }.disabled(busy || reading)
                    Button("导入文件", systemImage: "doc") { importing = true }.disabled(busy || reading)
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
        if importMode && importTable == nil { importTable = store.table.emptyCopy(name: "导入课表") }
        let captured = PlanSnapshot(table: importMode ? importTable! : store.table, profile: store.profile)
        snapshot = captured
        let history = modelHistory
        let token = UUID(); requestID = token
        requestTask = Task {
            do {
                let result = try await AIService.reply(mode: mode, messages: history, table: captured.table,
                    profile: captured.profile, endpoint: endpoint, model: model)
                try Task.checkCancellation()
                guard token == requestID else { return }
                try captured.check(current: importMode ? (importTable ?? store.table) : store.table, profile: store.profile)
                // Keep the full structured answer in model history, but display human-readable text only.
                reply = result
                messages.append(ChatMessage(role: "assistant", content: result.message))
                let structured = try JSONEncoder().encode(result)
                modelHistory.append(ChatMessage(role: "assistant", content: String(decoding: structured, as: UTF8.self)))
            } catch is CancellationError { }
            catch {
                if token == requestID {
                    localError = error.localizedDescription; input = text
                    modelHistory = Array(history.dropLast())
                    if messages.last?.role == "user", messages.last?.content == text { messages.removeLast() }
                }
            }
            if token == requestID { busy = false; requestTask = nil }
        }
    }
    private func cancel() { requestID = UUID(); requestTask?.cancel(); requestTask = nil; busy = false }
    private func invalidatePlans() { cancel(); reply = nil; snapshot = nil; selectedPlan = nil; selections = [:] }
    private func reset() { invalidatePlans(); messages = []; modelHistory = []; input = ""; importTable = nil }
    private var sourceReviewView: some View {
        NavigationStack {
            Form {
                if let sourceGrid {
                    Section {
                        Button("直接预览结构化课表") {
                            do {
                                let table = try PDFTimetableImporter.parse(sourceGrid, template: store.table, profile: store.profile)
                                sourceReview = false
                                pendingImport = ImportPreview(table: table, suggestedProfile: nil)
                            } catch { sourceIssue = error.localizedDescription }
                        }
                    } footer: { Text("已识别星期列；可直接预览，或交给 AI 整理。") }
                }
                if sourceText.count > 18_000 { Text("内容超过 18,000 字，请分批导入，避免漏课。").font(.footnote).foregroundStyle(.orange) }
                Section("识别内容 · 可修正") { TextEditor(text: $sourceText).frame(minHeight: 280).onChange(of: sourceText) { _, _ in sourceGrid = nil } }
                Section { Text(mode == .remote ? "识别时会将以上文字发送到已配置的 AI 接口。" : "使用设备端模型整理课表。")
                    .font(.footnote).foregroundStyle(.secondary) }
            }.alert("无法直接导入", isPresented: Binding(get: { sourceIssue != nil }, set: { if !$0 { sourceIssue = nil } })) {
                Button("好", role: .cancel) { sourceIssue = nil }
            } message: { Text(sourceIssue ?? "") }
            .navigationTitle("识别课表").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { sourceReview = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("识别并生成") {
                            sourceReview = false
                            send("请将以下课表资料整理成可导入的完整课程方案。保留已有课程，不要重复创建同一课程。准确识别星期、节次、周次、单双周、教室和教师；截图文字带有归一化坐标（x 从左到右、y 从上到下），请结合表头和位置恢复行列对应。资料里明确的课程事实必须照录，无法确定的关键字段集中给出选项询问，不得猜测。不要更改统一课节时间；若资料的时间无法映射到当前节次，先提示用户调整设置。\n资料：\n" + sourceText)
                        }.disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceText.count > 18_000)
                    }
                }
        }
    }
}

private struct PlanSelection: Identifiable {
    let id = UUID(); let plan: AssistantPlan; let snapshot: PlanSnapshot
}

struct PlanReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: AssistantPlan
    let snapshot: PlanSnapshot
    var importing = false
    let onApply: () -> Void
    @State private var issue: String?
    @State private var removedConfirmation = false
    private var proposed: [Course] { plan.courses.map { $0.materialize() } }
    private var removed: [Course] { snapshot.table.courses.filter { old in !proposed.contains { $0.id == old.id } } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(plan.explanation)
                    Text(importing ? "导入为新课表，保留已有课表与统一时间。" : "应用到“\(snapshot.table.name)”。")
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
                            if let weeks = course.unscheduledWeeks {
                                Text("未排时间 · 第 \(weeks.map(String.init).joined(separator: ",")) 周").font(.caption).foregroundStyle(.secondary)
                            }
                            Text([course.location, course.teacher].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
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
                    Button(importing ? "导入课表" : "应用方案") { if removed.isEmpty { apply() } else { removedConfirmation = true } }
                }
            }
            .alert("无法应用", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
                Button("好", role: .cancel) { issue = nil }
            } message: { Text(issue ?? "") }
            .confirmationDialog("方案会移除 \(removed.count) 门现有课程", isPresented: $removedConfirmation, titleVisibility: .visible) {
                Button("应用这份方案", role: .destructive) { apply() }
            }
        }
    }
    private func apply() {
        do {
            if importing {
                guard store.profile == snapshot.profile else { throw AppFailure("课节时间已变化，请重新识别。") }
                let table = try plan.proposedTable(from: snapshot.table, profile: store.profile)
                try store.importTable(ImportPreview(table: table, suggestedProfile: nil), adoptTimes: false)
            } else { try store.apply(plan, snapshot: snapshot) }
            dismiss(); onApply()
        } catch { issue = error.localizedDescription }
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
    @State private var availability = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Picker("处理方式", selection: $mode) {
                    ForEach(AssistantMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if mode == .onDevice { Text(availability).font(.footnote).foregroundStyle(.secondary) }
            }
            if mode == .remote {
                Section("快捷配置") {
                    Button("DeepSeek") {
                        endpoint = "https://api.deepseek.com/chat/completions"; model = "deepseek-chat"; testResult = nil
                    }
                }
                Section("OpenAI 兼容接口") {
                    TextField("Chat Completions HTTPS 地址", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("模型名称", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        testing = true; testResult = nil
                        let capturedEndpoint = endpoint, capturedModel = model, capturedKey = apiKey
                        testTask = Task {
                            do { testResult = try await AIService.test(endpoint: capturedEndpoint, model: capturedModel, key: capturedKey) }
                            catch { if !Task.isCancelled { testResult = error.localizedDescription } }
                            testing = false
                        }
                    } label: {
                        HStack { Text(testing ? "测试中…" : "测试 API"); if testing { ProgressView() } }
                    }.disabled(testing || endpoint.isEmpty || model.isEmpty || apiKey.isEmpty)
                    if let testResult { Text(testResult).font(.footnote).textSelection(.enabled) }
                }.disabled(testing)
                Section { Text("密钥存于本机钥匙串。对话与当前课表会发送至所选服务；测试仅发送连接检查。")
                    .font(.footnote).foregroundStyle(.secondary) }
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
                    }.disabled(testing)
                }
            }.onAppear {
                mode = AssistantMode(rawValue: savedMode) ?? .onDevice; endpoint = savedEndpoint; model = savedModel
                if mode == .onDevice { availability = AIService.availability }
                do { apiKey = try APIKeyStore.read() } catch { store.error = error.localizedDescription }
            }.onChange(of: mode) { _, value in
                testTask?.cancel(); testResult = nil
                if value == .onDevice { availability = AIService.availability }
            }.onDisappear { testTask?.cancel() }
    }
}
