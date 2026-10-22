import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import YIClassCore

struct AssistantView: View {
    var importMode = false
    @Environment(\.dismiss) private var dismiss
    @State private var importTable: Timetable?
    @State private var sourceText = ""
    @State private var sourceImages: [ChatImage] = []
    @State private var pendingImages: [ChatImage] = []
    @State private var sourceChangesCurrent = true
    @State private var planningImport = false
    @State private var pendingSubmission: AssistantSubmission?
    @State private var retrySubmission: AssistantSubmission?
    @State private var historyShowing = false
    @State private var conversationID = UUID()
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
    @FocusState private var inputFocused: Bool
    @FocusState private var sourceFocused: Bool
    @State private var importStatus = ""
    @State private var importFilename = ""
    @State private var importTask: Task<Void, Never>?
    @State private var importTimeout: Task<Void, Never>?
    @State private var importID = UUID()
    private var mode: AssistantMode { AssistantMode(rawValue: modeName) ?? .onDevice }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            VStack(alignment: .leading, spacing: 8) {
                                if let image = message.images.first, let preview = UIImage(data: image.data) {
                                    Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 160)
                                }
                                Text(message.content).font(.subheadline).textSelection(.enabled)
                            }
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
                                    Text("\(Set(plan.courses.map(\.name)).count) 门课程 · \(ScheduleEngine.conflictCount(courses: plan.courses.map { $0.materialize() })) 组冲突")
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
                .scrollDismissesKeyboard(.interactively)
                .background { AppBackdrop() }
                .safeAreaInset(edge: .top) {
                    if reading {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(importStatus).font(.subheadline)
                                if !importFilename.isEmpty { Text(importFilename).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            Button("取消") { cancelImport() }
                        }.padding(12).background(.regularMaterial)
                    }
                }
                .onChange(of: messages.count) { _, _ in reader.scrollTo("end", anchor: .bottom) }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .navigationTitle("课表助手")
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("收起键盘", systemImage: "keyboard.chevron.compact.down") { inputFocused = false }
                    }
                    if importMode { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("历史记录", systemImage: "clock.arrow.circlepath") { persistConversation(); inputFocused = false; historyShowing = true }
                            .disabled(busy || reading)
                    }
                }
            }
            .sheet(item: $selectedPlan) { PlanReviewView(plan: $0.plan, snapshot: $0.snapshot, importing: planningImport) {
                let imported = planningImport
                reply = nil; snapshot = nil; selectedPlan = nil
                messages.append(ChatMessage(role: "assistant", content: imported ? "课表已导入，可在课表页切换查看。" : "方案已应用。"))
                persistConversation()
            } }
            .sheet(isPresented: $historyShowing) {
                AssistantHistoryView(onOpen: openConversation, onNew: { reset(); historyShowing = false }, onRestored: { reset(); historyShowing = false })
            }
            .sheet(isPresented: $sourceReview, onDismiss: {
                if let pendingImport { directImport = pendingImport; self.pendingImport = nil }
                if let submission = pendingSubmission {
                    pendingSubmission = nil
                    send(submission.text, images: submission.images, importing: submission.importing, display: submission.display)
                }
            }) { sourceReviewView }
            .sheet(isPresented: Binding(get: { directImport != nil }, set: { if !$0 { directImport = nil } })) {
                if let directImport { ImportReviewView(preview: directImport) }
            }
            .alert("识别未完成", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                if let submission = retrySubmission {
                    Button("重试") {
                        localError = nil
                        send(submission.text, images: submission.images, importing: submission.importing, display: submission.display)
                    }
                }
                Button("关闭", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
            .task {
                if messages.isEmpty { planningImport = importMode; sourceChangesCurrent = !importMode }
                if let url = URL(string: endpoint) { model = AIChatRequest.resolvedModel(model, endpoint: url) }
                #if DEBUG
                if importMode, let encoded = ProcessInfo.processInfo.environment["YICLASS_UI_PDF"], let bytes = Data(base64Encoded: encoded) {
                    do { let payload = try await ImportSource.read(bytes, type: .pdf); sourceText = payload.text; sourceGrid = payload.grid; sourceReview = true }
                    catch { localError = error.localizedDescription }
                }
                #endif
            }
            .onChange(of: store.table.id) { _, _ in reset() }
            .onChange(of: store.table) { _, _ in invalidatePlans() }
            .onChange(of: store.profile) { _, _ in invalidatePlans() }
            .onChange(of: modeName) { _, _ in reset() }
            .onChange(of: photo) { _, value in
                guard let value else { return }
                cancelImport()
                let token = UUID(); importID = token
                inputFocused = false
                importFilename = "课表截图"
                importStatus = "正在识别图片…"
                reading = true
                importTask = Task {
                    do {
                        guard let data = try await value.loadTransferable(type: Data.self) else { throw AppFailure("图片读取失败。") }
                        let payload = try await ImportSource.read(data, type: .image)
                        try Task.checkCancellation()
                        guard token == importID else { return }
                        review(payload)
                    } catch is CancellationError { }
                    catch { if token == importID { localError = error.localizedDescription } }
                    if token == importID { photo = nil; reading = false; importTask = nil }
                }
            }
            .background {
                DocumentImportPicker(isPresented: $importing, contentTypes: [.pdf, .image, .text, .commaSeparatedText]) { url in
                    if let url { importChosenFile(url) }
                }.frame(width: 0, height: 0)
            }
        }
    }
    private func cancelImport() {
        importID = UUID()
        importTask?.cancel(); importTask = nil
        importTimeout?.cancel(); importTimeout = nil
        reading = false
    }
    private func importChosenFile(_ url: URL) {
        cancelImport()
        inputFocused = false
        importFilename = url.lastPathComponent
        importStatus = "正在读取文件…"
        reading = true
        let token = UUID(); importID = token
        importTimeout = Task {
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            guard token == importID else { return }
            cancelImport()
            localError = "读取或解析超时。请将文件下载到‘我的 iPhone’后重试，或改用课表截图。"
        }
        importTask = Task {
            do {
                let file = try await DocumentFileReader.read(url, maximumBytes: 20_000_000)
                try Task.checkCancellation()
                guard token == importID else { return }
                importStatus = file.type?.conforms(to: .pdf) == true ? "正在解析 PDF…" : "正在识别课表…"
                let payload = try await Task.detached(priority: .userInitiated) {
                    try await ImportSource.read(file.data, type: file.type)
                }.value
                try Task.checkCancellation()
                guard token == importID else { return }
                review(payload)
            } catch is CancellationError { }
            catch { if token == importID { localError = error.localizedDescription } }
            if token == importID {
                reading = false; importTask = nil
                importTimeout?.cancel(); importTimeout = nil
            }
        }
    }
    private func review(_ payload: ImportPayload) {
        sourceText = payload.text; sourceGrid = payload.grid; sourceImages = payload.images
        sourceChangesCurrent = !importMode || (payload.text.contains("通知") && (payload.text.contains("调整") || payload.text.contains("调课")))
        sourceReview = true
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.indigo.gradient)
            Text(importMode ? "AI 导入课表" : "一起找到合适的安排").font(.title2.bold())
            Text(importMode ? "选择截图、PDF 或文本，识别后预览导入。" : "直接说要怎么改，改完可以撤销。")
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink("\(mode.rawValue) · 配置", destination: AISettingsView()).font(.caption)
            if store.undoData != nil {
                Button("撤销最近一次更改", systemImage: "arrow.uturn.backward") {
                    store.perform { try store.undo() }
                }.font(.subheadline)
            }
            if messages.isEmpty && !importMode {
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
        GlassPanel(inset: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if !pendingImages.isEmpty {
                    HStack {
                        Label("已附原图", systemImage: "photo").font(.caption)
                        Spacer()
                        Button("移除") { pendingImages = [] }.font(.caption)
                    }.padding(.horizontal, 4)
                }
                TextField("描述课程，或补充你的偏好…", text: $input, axis: .vertical).lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 4).padding(.top, 2).disabled(busy || reading)
                HStack(alignment: .bottom, spacing: 8) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("截图", systemImage: "photo")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10).padding(.bottom, 6)
                            .frame(minHeight: 44, alignment: .bottom)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.tint)
                        .accessibilityLabel("选择课表截图").disabled(busy || reading)
                    Button { inputFocused = false; importing = true } label: {
                        Label("文件", systemImage: "doc")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10).padding(.bottom, 6)
                            .frame(minHeight: 44, alignment: .bottom)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.tint)
                        .accessibilityLabel("导入课表文件").disabled(busy || reading)
                    Spacer(minLength: 0)
                    if inputFocused {
                        Button { inputFocused = false } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.body).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.tint).accessibilityLabel("收起键盘")
                    }
                    Button { send(input, images: pendingImages) } label: {
                        Image(systemName: "arrow.up").font(.body.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.white)
                            .background(.indigo, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .opacity(busy || reading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                        .accessibilityLabel("发送")
                        .disabled(busy || reading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(.horizontal, 16).padding(.bottom, inputFocused ? 2 : 8)
    }
    private func send(_ text: String, images: [ChatImage] = [], importing: Bool? = nil, display: String? = nil) {
        guard !busy else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 20_000 else { store.error = "请输入 1–20,000 字的说明。"; return }
        guard modelHistory.reduce(0, { $0 + $1.content.count }) + text.count <= 80_000 else {
            store.error = "这段对话过长，请开始新对话，并简要说明需求。"; return
        }
        if let importing, importing != planningImport {
            planningImport = importing; importTable = nil; modelHistory = []
        }
        let deliveredImages = mode == .remote ? images : []
        guard deliveredImages.reduce(0, { $0 + $1.data.count }) <= 25_000_000 else { localError = "图片过大，请减少图片后重试。"; return }
        let submission = AssistantSubmission(text: text, images: images, importing: planningImport, display: display ?? text)
        retrySubmission = nil
        inputFocused = false
        input = ""; pendingImages = []; busy = true; reply = nil; selections = [:]
        messages.append(ChatMessage(role: "user", content: submission.display, images: images))
        modelHistory.append(ChatMessage(role: "user", content: text, images: deliveredImages))
        persistConversation()
        if planningImport && importTable == nil { importTable = store.table.emptyCopy(name: "导入课表") }
        let captured = PlanSnapshot(table: planningImport ? importTable! : store.table, profile: store.profile)
        snapshot = captured
        let history = modelHistory
        let token = UUID(); requestID = token
        requestTask = Task {
            do {
                let result = try await AIService.reply(mode: mode, messages: history, table: captured.table,
                    profile: captured.profile, endpoint: endpoint, model: model)
                try Task.checkCancellation()
                guard token == requestID else { return }
                try captured.check(current: planningImport ? (importTable ?? store.table) : store.table, profile: store.profile)
                // Keep the full structured answer in model history, but display human-readable text only.
                if result.applyDirectly == true && !planningImport, let plan = result.plans.first {
                    try store.apply(plan, snapshot: captured)
                    reply = nil; snapshot = nil
                    messages.append(ChatMessage(role: "assistant", content: "已更新课表。" + result.message))
                } else {
                    reply = result
                    messages.append(ChatMessage(role: "assistant", content: result.message))
                }
                let structured = try JSONEncoder().encode(result)
                modelHistory.append(ChatMessage(role: "assistant", content: String(decoding: structured, as: UTF8.self)))
            } catch is CancellationError { }
            catch {
                if token == requestID {
                    localError = error.localizedDescription
                    retrySubmission = submission
                    input = submission.display; pendingImages = images
                    modelHistory = Array(history.dropLast())
                    if messages.last?.role == "user" { messages.removeLast() }
                }
            }
            if token == requestID { busy = false; requestTask = nil; persistConversation() }
        }
    }
    private func cancel() {
        requestID = UUID(); requestTask?.cancel(); requestTask = nil
        if busy, modelHistory.last?.role == "user" {
            let canceled = modelHistory.removeLast()
            if messages.last?.role == "user" {
                input = messages.removeLast().content
                pendingImages = canceled.images
            }
        }
        busy = false
    }
    private func invalidatePlans() { cancel(); reply = nil; snapshot = nil; selectedPlan = nil; selections = [:] }
    private func persistConversation() {
        guard !messages.isEmpty else { return }
        store.perform {
            try store.saveConversation(id: conversationID, messages: messages, modelHistory: modelHistory, importing: planningImport, importTable: importTable)
        }
    }
    private func openConversation(_ conversation: ConversationRecord) {
        persistConversation(); invalidatePlans()
        conversationID = conversation.id; messages = conversation.messages; modelHistory = conversation.modelHistory
        planningImport = conversation.importing; importTable = conversation.importTable
        input = ""; pendingImages = []; retrySubmission = nil; historyShowing = false
    }
    private func reset() {
        persistConversation(); invalidatePlans(); messages = []; modelHistory = []; input = ""; importTable = nil
        cancelImport(); photo = nil
        conversationID = UUID(); planningImport = importMode; pendingImages = []; retrySubmission = nil
        sourceImages = []; sourceText = ""; sourceGrid = nil
    }
    private var sourceReviewView: some View {
        NavigationStack {
            Form {
                Picker("用途", selection: $sourceChangesCurrent) {
                    Text("修改当前课表").tag(true)
                    Text("导入新课表").tag(false)
                }.pickerStyle(.segmented)
                if let image = sourceImages.first, let preview = UIImage(data: image.data) {
                    Section("原图") { Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity) }
                }
                if !sourceChangesCurrent, let sourceGrid, sourceText == sourceGrid.source {
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
                Section("识别内容 · 可修正") { TextEditor(text: $sourceText).focused($sourceFocused).frame(height: 260) }
                Section { Text(mode == .remote ? (sourceImages.isEmpty ? "文字将发送到已配置的 AI 接口。" : "原图与文字将发送到已配置的 AI 接口。") : "设备端使用本机识别的文字。")
                    .font(.footnote).foregroundStyle(.secondary) }
            }.scrollDismissesKeyboard(.interactively).alert("无法直接导入", isPresented: Binding(get: { sourceIssue != nil }, set: { if !$0 { sourceIssue = nil } })) {
                Button("好", role: .cancel) { sourceIssue = nil }
            } message: { Text(sourceIssue ?? "") }
            .navigationTitle("识别课表").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("收起键盘", systemImage: "keyboard.chevron.compact.down") { sourceFocused = false }
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { sourceFocused = false; sourceReview = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(sourceChangesCurrent ? "调整课表" : "识别并生成") {
                            let purpose = sourceChangesCurrent
                                ? "请按附件中的通知或课程资料修改当前课表。明确的调课直接返回可应用的完整结果，保留其他日期课程。只有无法确定的关键目标才给选项询问。"
                                : "请将附件中的完整课表整理成新课表的导入方案。"
                            let instruction = purpose + "优先阅读原图，文字仅作辅助；不要遗漏课程、教师、地点和周次。缺少地点可留空，不要修改统一课节时间。\n资料：\n" + sourceText
                            pendingSubmission = AssistantSubmission(text: instruction, images: sourceImages, importing: !sourceChangesCurrent,
                                display: sourceChangesCurrent ? "请按这份资料调整当前课表。" : "请识别这份资料，导入为新课表。")
                            sourceFocused = false; sourceReview = false
                        }.disabled((sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sourceImages.isEmpty) || sourceText.count > 18_000)
                    }
                }
        }
    }
}

private struct AssistantSubmission {
    let text: String
    let images: [ChatImage]
    let importing: Bool
    let display: String
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
    @State private var semesterStart = Date()
    private var proposed: [Course] { plan.courses.map { $0.materialize() } }
    private var removed: [Course] { snapshot.table.courses.filter { old in !proposed.contains { $0.id == old.id } } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(plan.explanation)
                    if importing { DatePicker("开学日期", selection: $semesterStart, displayedComponents: .date) }
                    Text(importing ? "导入为新课表，保留已有课表与统一时间。" : "应用到“\(snapshot.table.name)”。")
                        .font(.footnote).foregroundStyle(.secondary)
                    let conflicts = ScheduleEngine.conflictCount(courses: proposed)
                    Label("\(conflicts) 组课程冲突", systemImage: conflicts > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(conflicts > 0 ? Color.orange : Color.green)
                }
                Section("应用后的课程记录（\(proposed.count) 条）") {
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
            .onAppear { semesterStart = snapshot.table.startDate }
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
                var table = try plan.proposedTable(from: snapshot.table, profile: store.profile)
                table.startDate = semesterStart
                if table.courses.flatMap(\.schedules).contains(where: { $0.weekday >= 6 }) { table.showWeekend = true }
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
                    Button("DeepSeek · 支持原图") {
                        endpoint = "https://api.deepseek.com/chat/completions"; model = "deepseek-flash"; testResult = nil
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
                mode = AssistantMode(rawValue: savedMode) ?? .onDevice; endpoint = savedEndpoint
                model = URL(string: savedEndpoint).map { AIChatRequest.resolvedModel(savedModel, endpoint: $0) } ?? savedModel
                if mode == .onDevice { availability = AIService.availability }
                do { apiKey = try APIKeyStore.read() } catch { store.error = error.localizedDescription }
            }.onChange(of: mode) { _, value in
                testTask?.cancel(); testResult = nil
                if value == .onDevice { availability = AIService.availability }
            }.onDisappear { testTask?.cancel() }
    }
}
