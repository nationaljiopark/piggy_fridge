import Foundation
import AVFoundation
import Vision
import VisionKit
import SwiftUI
import UIKit

/// The + button: camera permission, "Camera access is off", and batch scanning.
/// Live date reading is not wired up yet (next step: VisionKit DataScannerViewController).
/// For now the scanner shows sample results so the flow can be tested end to end.
struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch status {
            case .authorized:
                BatchScanView()
            case .notDetermined:
                permissionIntro
            default:
                cameraOff
            }
        }
        .task {
            if status == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                status = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private var permissionIntro: some View {
        VStack(spacing: 16) {
            closeBar(light: false)
            Spacer()
            Image(systemName: "camera.viewfinder").font(.system(size: 56)).foregroundStyle(Palette.ink)
            Text("Scan date label").font(.title2.weight(.bold))
            Text("Point your camera at the Use By or Best Before date")
                .font(.subheadline).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            Spacer()
            Button("Type it in instead") { typeInstead() }
                .buttonStyle(LinkButtonStyle())
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }

    private var cameraOff: some View {
        VStack(spacing: 16) {
            closeBar(light: false)
            Spacer()
            Image(systemName: "video.slash").font(.system(size: 48)).foregroundStyle(Palette.ink)
            Text("Camera access is off").font(.title2.weight(.bold))
            Text("To scan date labels, allow Piggy Fridge to use your camera in Settings. You can also type the date in.")
                .font(.subheadline).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Type it in instead") { typeInstead() }
                .buttonStyle(LinkButtonStyle())
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
    }

    private func closeBar(light: Bool) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .foregroundStyle(light ? Color.white : Palette.ink)
            .accessibilityLabel("Close")
            Spacer()
        }
    }

    private func typeInstead() {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            router.startAddFood()
        }
    }
}

/// Scanned item before it is saved (name can be added later).
struct ScannedItem: Identifiable {
    let id = UUID()
    var name: String
    var date: Date
    var dateType: DateType
    var storage: Storage
    var category: String? = nil
    var weightKg: Double? = nil
    var priceGBP: Double? = nil
    /// The matched food from the 100 list (keeps its icon and numbers even when the name is a brand name).
    var presetName: String? = nil
    var iconAsset: String? = nil
    /// False when only the name was scanned (no date yet). The date shows "Add date" until the user sets it.
    var hasDate: Bool = true
}

/// Figma "Camera — Batch scan": live camera on top, scanned items sheet below.
/// The camera reads the label text (and barcode). Each reading is matched to one of the 100 foods,
/// or to a category, and shown in the panel at the bottom of the camera. "Add" puts it in the list.
struct BatchScanView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var scanned: [ScannedItem] = []
    @State private var candidate = ScanCandidate()
    @State private var lookedUpBarcodes: Set<String> = []
    @State private var naming: ScannedItem?
    @State private var nameText = ""

    /// False on the simulator and on phones without the live text scanner.
    enum CameraMode { case checking, live, preview }
    @State private var cameraMode: CameraMode = .live
    @State private var scannerNote = ""
    @State private var lookingUpBarcode = false
    @State private var barcodeNote: String?
    @State private var barcodeCache: [String: ScanCandidate] = [:]
    @State private var lastReadAt = Date.distantPast

    // Auto capture: once the same date has been read twice in a row (about 0.7 s), the food is added
    // without tapping Add. The same label is not added again until a different date comes into view.
    @State private var stableDate: Date?
    @State private var stableCount = 0
    @State private var justAdded: String?

    // 아래 카드: 내려간 상태로 시작, 위로 끌거나 탭하면 열림
    @State private var sheetExpanded = false
    @GestureState private var dragOffset: CGFloat = 0
    private let collapsedHeight: CGFloat = 190   // 손잡이 + 제목 + Add manually + Save 버튼이 들어가는 높이

    // 스캔한 아이템 수정 화면
    @State private var editing: ScannedItem?
    /// Add 전에 카드를 눌러 수정할 때 쓰는 초안, 그리고 수정이 끝난 카드
    @State private var candidateDraft: ScannedItem?
    @State private var editedCandidate: ScannedItem?
    /// Add 직후 잠깐(1.5초) 카메라를 무시하고, 방금 추가한 라벨이 다시 카드에 올라오지 않게 해요
    @State private var ignoreUntil = Date.distantPast
    @State private var lastAddedBarcodes: Set<String> = []
    /// "Add manually" while there are scanned items that are not saved yet
    @State private var confirmLeave = false

    private var liveAvailable: Bool { cameraMode == .live }

    /// Decides once which camera view to use, so two camera views never run at the same time
    /// (that made the screen freeze). The text scanner can say "not available" for a moment right after
    /// the permission was granted, so it is checked a few times before falling back to the plain camera picture.
    private func chooseCamera() async {
        for _ in 0..<10 {
            let supported = DataScannerViewController.isSupported
            let available = DataScannerViewController.isAvailable
            scannerNote = "supported: \(supported ? "yes" : "no"), available: \(available ? "yes" : "no")"
            if supported && available { cameraMode = .live; return }
            if !supported { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        cameraMode = .preview
    }

    var body: some View {
        GeometryReader { geo in
            let expandedHeight = geo.size.height * 0.6
            let base = sheetExpanded ? expandedHeight : collapsedHeight
            let sheetHeight = min(max(base - dragOffset, collapsedHeight), expandedHeight)

            ZStack(alignment: .bottom) {
                cameraArea(panelBottom: sheetHeight)
                listSheet(showList: sheetHeight > collapsedHeight + 30)
                    .frame(height: sheetHeight)
            }
        }
        .background(Color.black.ignoresSafeArea())
        // 아이템을 누르면 수정 화면 (아이콘, 이름, 날짜)
        .sheet(item: $editing) { item in
            ScannedItemEditor(item: item) { updated in
                if let i = scanned.firstIndex(where: { $0.id == updated.id }) {
                    scanned[i] = updated
                }
            }
            .environment(store)
        }
        // Add 전에 카드(검은 패널)를 눌러 수정
        .sheet(item: $candidateDraft) { draft in
            ScannedItemEditor(item: draft) { updated in
                editedCandidate = updated
            }
            .environment(store)
        }
        // 스캔한 게 있는데 Add manually를 누르면: 먼저 저장할지 물어봐요
        .confirmationDialog(
            scanned.count == 1 ? "Save your scanned item first?" : "Save your \(scanned.count) scanned items first?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button(scanned.count == 1 ? "Save 1 item and continue" : "Save \(scanned.count) items and continue") {
                saveThenAddManually()
            }
            Button("Discard and continue", role: .destructive) {
                scanned = []
                openManualAdd()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They aren’t saved yet. If you leave without saving, they’ll be lost.")
        }
    }

    // MARK: Camera

    private func cameraArea(panelBottom: CGFloat) -> some View {
        ZStack {
            switch cameraMode {
            case .checking:
                Color.black
            case .live:
                LabelCameraView(
                    onTexts: { handle(texts: $0) },
                    onBarcode: { handle(barcode: $0) },
                    onFail: { reason in
                        // Fall back to the plain camera picture and show why on screen.
                        scannerNote = reason
                        cameraMode = .preview
                    },
                    onStatus: { _ in })
            case .preview:
                CameraPreviewView()
                Text("Live label reading is not available yet.\nTry a sample label to test the flow.\n(\(scannerNote))")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 60)
                    .shadow(color: .black.opacity(0.6), radius: 4)
            }
            ViewfinderCorners()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .padding(.horizontal, 48)
                .padding(.top, 64)                          // below the title bar
                .padding(.bottom, collapsedHeight + 84)     // above the result panel and the card
                .allowsHitTesting(false)
            VStack {
                ZStack {
                    Text("Add food").font(.headline)
                    HStack {
                        Button { dismiss() } label: {
                            PFCloseIconLight().frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Close")
                        Spacer()
                    }
                }
                .frame(height: 48)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                Spacer()
                candidatePanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, panelBottom + 12)     // sits just above the card, moves with it
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // camera fills the whole screen
        .clipped()
    }

    /// 이름이나 날짜 중 하나만 읽혀도 Add 할 수 있어요.
    private var candidateName: String? {
        candidate.productName ?? candidate.preset?.name ?? candidate.category
    }

    private var canAdd: Bool {
        editedCandidate != nil || candidate.date != nil || candidateName != nil
    }

    private var candidatePanel: some View {
        HStack(spacing: 12) {
            // 아이콘 + 이름 + 날짜: 누르면 Add 전에 수정할 수 있어요
            Button { openCandidateEditor() } label: {
                HStack(spacing: 12) {
                    if let edited = editedCandidate {
                        FoodIconView(asset: edited.iconAsset ?? "food_unknown_food", size: 40)
                    } else if let preset = candidate.preset {
                        FoodIconView(asset: preset.icon, size: 40)
                    } else if candidate.category != nil {
                        FoodIconView(asset: "food_unknown_food", size: 40)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidateTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(candidateSubtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)

            if cameraMode != .live && candidate.isEmpty && editedCandidate == nil {
                Button("Try sample") { handle(texts: Self.sampleLabel()) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
            } else {
                if (!candidate.isEmpty || editedCandidate != nil) && !isSameAsLastAdded {
                    Button {
                        candidate = ScanCandidate()
                        editedCandidate = nil
                        lookedUpBarcodes = []
                    } label: {
                        Image(systemName: "arrow.counterclockwise").font(.subheadline.weight(.semibold)).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Clear")
                }
                // 자동으로 추가되지 않아요. Add를 눌러야 Scanned items에 들어가요.
                Button(isSameAsLastAdded ? "Add again" : "Add") { addCandidate() }
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule().fill(Palette.yellow))
                    .opacity(canAdd ? 1 : 0.4)
                    .disabled(!canAdd)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.7)))
    }

    private func openCandidateEditor() {
        guard canAdd else { return }
        candidateDraft = editedCandidate ?? makeScannedItem()
    }

    private var candidateTitle: String {
        if let edited = editedCandidate { return edited.name.isEmpty ? "No name yet" : edited.name }
        if let justAdded, candidate.isEmpty { return "Added · \(justAdded)" }
        if let name = candidate.productName { return name }
        if let preset = candidate.preset { return preset.name }
        if let category = candidate.category { return category }
        if lookingUpBarcode { return "Barcode found" }
        return liveAvailable ? "Point at the label" : "No label yet"
    }

    private var candidateSubtitle: String {
        if let edited = editedCandidate {
            return edited.hasDate
                ? "\(edited.dateType.title) · \(PFDate.longDay.string(from: edited.date))"
                : "No date yet · Tap to edit"
        }
        guard let date = candidate.date else {
            if lookingUpBarcode { return "Looking up the product…" }
            if candidate.fromBarcode { return "Now show the date on the pack" }
            if let barcodeNote, candidate.isEmpty { return barcodeNote }
            if justAdded != nil, candidate.isEmpty { return "Show the next barcode or date" }
            return candidate.isEmpty ? "Show the barcode, then the date" : "Looking for the date…"
        }
        let type = candidate.dateType?.title ?? candidate.preset?.dateType.title ?? "Date"
        return "\(type) · \(PFDate.longDay.string(from: date))"
    }

    // MARK: Reading

    private func handle(texts: [String]) {
        // The scanner reports many times a second. Read at most about 3 times a second so the screen stays smooth.
        // 카드를 수정 중이거나 수정이 끝났으면 카메라가 덮어쓰지 않게 잠깐 멈춰요
        guard editedCandidate == nil, candidateDraft == nil, editing == nil else { return }
        guard Date() > ignoreUntil else { return }
        guard Date().timeIntervalSince(lastReadAt) > 0.35 else { return }
        lastReadAt = Date()
        let reading = LabelParser.read(texts, presets: store.presets)
        // 방금 Add 한 라벨이 아직 화면에 보이면 카드에 다시 올리지 않아요
        if isJustAdded(reading) { return }
        // 다른 라벨이 보이기 시작하면 "방금 추가한 것" 기억을 지워요
        if !reading.isEmpty {
            lastAutoName = nil
            lastAutoDate = nil
            lastAddedBarcodes = []
        }
        var next = candidate
        next.merge(reading)
        if next != candidate { candidate = next }
        // 자동 추가는 껐어요. Add를 눌러야만 추가돼요.
    }

    /// 카드가 비어 있는 동안, 방금 추가한 것과 같은 이름/날짜만 읽히면 true
    private func isJustAdded(_ reading: ScanCandidate) -> Bool {
        guard candidate.isEmpty else { return false }
        let name = reading.productName ?? reading.preset?.name ?? reading.category
        let sameName = name != nil && name == lastAutoName
        let sameDate = reading.date != nil && reading.date == lastAutoDate
        let nothingNew = (name == nil || sameName) && (reading.date == nil || sameDate)
        return (sameName || sameDate) && nothingNew
    }

    @State private var lastAutoDate: Date?
    @State private var lastAutoName: String?
    @State private var lastAutoCategory: String?

    /// True when what the camera sees now is most likely the label that was just added
    /// (same date, and either no name yet, the same name, or the exact food of the category added before).
    private var isSameAsLastAdded: Bool {
        guard let date = candidate.date, date == lastAutoDate else { return false }
        let name = candidate.productName ?? candidate.preset?.name ?? candidate.category
        guard let name, let lastAutoName else { return true }
        return name == lastAutoName || candidate.category == lastAutoCategory && candidate.preset != nil && lastAutoName == lastAutoCategory
    }

    private func autoCapture(seen date: Date?) {
        guard let date else { return }
        if date == stableDate {
            stableCount += 1
        } else {
            stableDate = date
            stableCount = 1
        }
        guard stableCount >= 2, candidate.date != nil, !isSameAsLastAdded else { return }
        stableCount = 0
        addCandidate()
    }

    /// A barcode tells us exactly what the product is (name, kind of food). It never tells us the date.
    /// Once a barcode is read, that product is locked in and the label text is only used for the date.
    private func handle(barcode: String) {
        guard editedCandidate == nil, candidateDraft == nil, editing == nil else { return }
        guard Date() > ignoreUntil else { return }
        guard !lastAddedBarcodes.contains(barcode) else { return }   // 방금 추가한 상품의 바코드
        guard !lookedUpBarcodes.contains(barcode) else { return }
        lookedUpBarcodes.insert(barcode)
        if let cached = barcodeCache[barcode] {
            apply(barcodeReading: cached)
            return
        }
        lookingUpBarcode = true
        barcodeNote = nil
        Task {
            let info = await ProductLookup.info(forBarcode: barcode)
            lookingUpBarcode = false
            guard let info else {
                barcodeNote = "Barcode not in the database. Reading the label text."
                return
            }
            var reading = LabelParser.read(info.names, presets: store.presets)
            if reading.preset == nil, reading.category == nil {
                reading.category = LabelParser.category(in: info.categoryTags)
            }
            reading.productName = info.productName
            reading.fromBarcode = true
            reading.date = nil          // a barcode never tells us the date
            reading.dateType = nil
            barcodeCache[barcode] = reading
            apply(barcodeReading: reading)
        }
    }

    private func apply(barcodeReading reading: ScanCandidate) {
        var next = candidate
        next.merge(reading)
        candidate = next
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 지금 카메라가 읽은 내용으로 ScannedItem을 만들어요. 날짜가 없으면 "Add date"로 표시돼요.
    private func makeScannedItem() -> ScannedItem {
        let preset = candidate.preset
        let fallback = CategoryFallback.named(candidate.category ?? "Other (unknown)")
        var type = candidate.dateType ?? preset?.dateType ?? fallback.dateType
        if type == .notSure { type = .bestBefore }
        return ScannedItem(
            name: candidate.productName ?? preset?.name ?? "",
            date: candidate.date ?? Calendar.current.startOfDay(for: .now),
            dateType: type,
            // Storage: 1. label wording  2. the matched food  3. Use by means chilled  4. category default
            storage: candidate.storage ?? preset?.storageBeforeOpening ?? (type == .useBy ? .fridge : fallback.storage),
            category: candidate.category,
            weightKg: candidate.weightKg,
            priceGBP: candidate.priceGBP,
            presetName: preset?.name,
            iconAsset: preset?.icon,
            hasDate: candidate.date != nil)
    }

    private func addCandidate() {
        guard canAdd else { return }
        let item = editedCandidate ?? makeScannedItem()
        scanned.insert(item, at: 0)
        let addedName = item.name.isEmpty ? (item.category ?? "Food") : item.name
        lastAutoDate = candidate.date
        lastAutoName = candidateName
        lastAutoCategory = candidate.category
        candidate = ScanCandidate()
        editedCandidate = nil
        lastAddedBarcodes = lookedUpBarcodes
        lookedUpBarcodes = []
        barcodeNote = nil
        ignoreUntil = Date().addingTimeInterval(1.5)
        withAnimation(.easeIn(duration: 0.2)) { justAdded = addedName }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if justAdded == addedName { withAnimation(.easeIn(duration: 0.2)) { justAdded = nil } }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Sample label for the simulator: goes through the same reader as a real camera.
    private static func sampleLabel() -> [String] {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.dateFormat = "d MMM"
        func day(_ n: Int) -> String { format.string(from: PFDate.addingDays(n)).uppercased() }
        let samples: [[String]] = [
            ["Semi Skimmed Milk", "4 pints", "USE BY \(day(3))"],
            ["Scottish Salmon Fillets", "240g", "£4.50", "USE BY \(day(2))"],
            ["Tomato & Basil Soup", "BEST BEFORE \(day(12))"],
            ["Crunchy Peanut Butter", "340g", "BEST BEFORE END \(day(200))"],
            ["Chicken Katsu Curry", "USE BY \(day(1))"],
            ["Greek Style Yogurt", "500g", "USE BY \(day(6))"]
        ]
        return samples.randomElement() ?? samples[0]
    }

    // MARK: Scanned list

    private func listSheet(showList: Bool) -> some View {
        VStack(spacing: 0) {
            // 손잡이 + 제목: 위/아래로 끌거나 탭하면 카드가 열리고 닫혀요
            VStack(spacing: 0) {
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 8)
                HStack {
                    Text("Scanned items").font(.pfSection)
                    Spacer()
                    Text("\(scanned.count)").font(.pfSection)
                    Image(systemName: sheetExpanded ? "chevron.down" : "chevron.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy) { sheetExpanded.toggle() }
            }
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        withAnimation(.snappy) {
                            if value.translation.height < -40 { sheetExpanded = true }
                            if value.translation.height > 40 { sheetExpanded = false }
                        }
                    }
            )

            // 바코드 없는 음식(과일, 채소, 빵 등)은 여기서 수기로 추가. 카드가 내려가 있어도 보여요.
            Button { manualAddTapped() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    Text("Add manually")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showList {
                List {
                    if scanned.isEmpty {
                        Text("Show the barcode, then the date, and tap Add. Each food you add shows up here.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkTertiary)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(scanned) { item in
                        Button {
                            editing = item          // 누르면 수정 화면 열기
                        } label: {
                            scannedRow(item)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    }
                    .onDelete { scanned.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
            } else {
                Spacer(minLength: 0)
            }

            Button(scanned.count == 1 ? "Save 1 item" : "Save \(scanned.count) items") { saveAll() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(scanned.isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func scannedRow(_ item: ScannedItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon = item.iconAsset ?? store.preset(named: item.name)?.icon {
                FoodIconView(asset: icon)
            } else if item.category != nil {
                FoodIconView(asset: "food_unknown_food")
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.surface)
                    .frame(width: 62, height: 62)
                    .overlay(Image(systemName: "pencil").foregroundStyle(Palette.inkTertiary))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name.isEmpty ? "No name yet" : item.name)
                    .font(.pfRowTitle)
                    .foregroundStyle(item.name.isEmpty ? Palette.inkTertiary : Palette.ink)
                HStack(spacing: 6) {
                    DateTypeBadge(type: item.dateType)
                        .fixedSize()                       // 태그는 줄바꿈 안 함
                    if item.name.isEmpty, let category = item.category {
                        Text(category).font(.caption).foregroundStyle(Palette.inkTertiary)
                            .lineLimit(1)                  // 카테고리도 한 줄
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if item.hasDate {
                    Text(PFDate.longDay.string(from: item.date)).font(.callout.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("Add date").font(.callout.weight(.bold)).foregroundStyle(Palette.danger)
                }
                Text(item.storage.title).font(.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func saveName() {
        guard let target = naming, let i = scanned.firstIndex(where: { $0.id == target.id }) else { return }
        scanned[i].name = nameText.trimmingCharacters(in: .whitespaces)
        if let preset = store.preset(named: scanned[i].name) {
            scanned[i].category = preset.category
            scanned[i].storage = preset.storageBeforeOpening
            scanned[i].presetName = preset.name
            scanned[i].iconAsset = preset.icon
        }
        naming = nil
    }

    // MARK: Add manually

    /// Nothing scanned yet: go straight to manual add.
    /// Something scanned: ask first, so leaving this screen never loses the scanned items.
    private func manualAddTapped() {
        if scanned.isEmpty {
            openManualAdd()
        } else {
            confirmLeave = true
        }
    }

    private func openManualAdd() {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            router.startAddFood()
        }
    }

    private func saveThenAddManually() {
        let count = storeScanned()
        scanned = []
        router.goHome()
        toasts.show("\(count) item\(count == 1 ? "" : "s") added to My Food")
        openManualAdd()
    }

    private func saveAll() {
        let count = storeScanned()
        dismiss()
        router.goHome()
        toasts.show("\(count) item\(count == 1 ? "" : "s") added to My Food")
    }

    /// Puts every scanned item into My Food and returns how many were saved.
    @discardableResult
    private func storeScanned() -> Int {
        for s in scanned {
            let draft = AddFoodDraft(name: s.name.isEmpty ? "Unnamed food" : s.name, dateType: s.dateType, date: s.date, storage: s.storage)
            var item = store.makeItem(from: draft)
            item.storage = s.storage
            if let icon = s.iconAsset { item.iconAsset = icon }
            if let preset = store.preset(named: s.presetName ?? item.name) {
                item.category = preset.category
                // One of the 100 foods: use the weight read from the label, if any.
                if let kg = s.weightKg, preset.weightKg > 0 {
                    item.weightKg = kg
                    item.co2eKg = preset.co2eKg / preset.weightKg * kg
                }
                if let price = s.priceGBP { item.priceGBP = price }
            } else {
                // Not in the 100: category medians, then anything read from the label.
                let fallback = CategoryFallback.named(s.category ?? "Other (unknown)")
                let kg = s.weightKg ?? fallback.weightKg
                item.category = fallback.category == "Other (unknown)" ? "Other" : fallback.category
                item.weightKg = kg
                item.priceGBP = s.priceGBP ?? fallback.priceGBP
                item.co2eKg = fallback.co2ePerKg * kg
            }
            store.add(item)
        }
        return scanned.count
    }
}

/// Live camera that reads text and barcodes (VisionKit). Needs the camera permission, asked just before.
/// Holds the text scanner and starts it only once it is really on screen.
/// Starting it too early (while the full-screen sheet is still sliding up) fails silently and leaves a black area,
/// so it tries again a few times, and reports the reason if it still cannot start.
final class ScannerHostController: UIViewController {
    let scanner: DataScannerViewController
    var onFail: (String) -> Void = { _ in }

    init(scanner: DataScannerViewController) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    // Keep the camera picture the same size as the area, or it can stay black at zero size.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scanner.view.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        start(attempt: 0)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }

    private func start(attempt: Int) {
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            if attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.start(attempt: attempt + 1) }
            } else {
                onFail("scanner could not start: \(error.localizedDescription)")
            }
        }
    }
}

struct LiveScannerView: UIViewControllerRepresentable {
    var onTexts: ([String]) -> Void
    var onBarcode: (String) -> Void
    var onFail: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTexts: onTexts, onBarcode: onBarcode, onFail: onFail)
    }

    func makeUIViewController(context: Context) -> ScannerHostController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(), .barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        let host = ScannerHostController(scanner: scanner)
        host.onFail = onFail
        return host
    }

    func updateUIViewController(_ host: ScannerHostController, context: Context) {
        context.coordinator.onTexts = onTexts
        context.coordinator.onBarcode = onBarcode
        context.coordinator.onFail = onFail
        host.onFail = onFail
    }

    static func dismantleUIViewController(_ host: ScannerHostController, coordinator: Coordinator) {
        host.scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onTexts: ([String]) -> Void
        var onBarcode: (String) -> Void
        var onFail: (String) -> Void

        init(onTexts: @escaping ([String]) -> Void, onBarcode: @escaping (String) -> Void,
             onFail: @escaping (String) -> Void) {
            self.onTexts = onTexts
            self.onBarcode = onBarcode
            self.onFail = onFail
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onFail("scanner became unavailable: \(error)")
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            publish(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            publish(allItems)
        }

        private func publish(_ items: [RecognizedItem]) {
            var texts: [String] = []
            for item in items {
                switch item {
                case .text(let text):
                    texts.append(text.transcript)
                case .barcode(let barcode):
                    if let value = barcode.payloadStringValue { onBarcode(value) }
                @unknown default:
                    break
                }
            }
            if !texts.isEmpty { onTexts(texts) }
        }
    }
}

/// Four corner brackets of the camera frame.
nonisolated struct ViewfinderCorners: Shape {
    var length: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return p
    }
}


/// White close icon for the camera screen (same shape as PFCloseIcon).
struct PFCloseIconLight: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 6, y: 6)); p.addLine(to: CGPoint(x: 18, y: 18))
            p.move(to: CGPoint(x: 18, y: 6)); p.addLine(to: CGPoint(x: 6, y: 18))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 24)
    }
}

/// Plain live camera picture. Used whenever the text scanner cannot start, so the camera is always visible.
struct CameraPreviewView: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = view.session
        view.previewLayer.videoGravity = .resizeAspectFill
        let session = view.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.beginConfiguration()
            if let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            session.startRunning()
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        let session = uiView.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}

// MARK: - Edit a scanned item (icon, name, date)

/// 스캔한 아이템 수정 화면: 아이콘, 이름, 날짜 종류, 유통기한
struct ScannedItemEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: ScannedItem
    var onSave: (ScannedItem) -> Void

    @State private var name = ""
    @State private var date = Date()
    @State private var dateType: DateType = .useBy
    @State private var icon: String?
    @State private var iconPickedByUser = false
    @State private var showIconPicker = false
    @State private var hasDate = true

    var body: some View {
        NavigationStack {
            Form {
                // 아이콘 (누르면 직접 고르기)
                Section {
                    HStack {
                        Spacer()
                        Button { showIconPicker = true } label: {
                            VStack(spacing: 8) {
                                FoodIconView(asset: icon ?? "food_unknown_food", size: 88)
                                Text(iconPickedByUser ? "Tap to change" : "Suggested · Tap to change")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("Name") {
                    TextField("e.g. Chicken breasts", text: $name)
                }

                Section("Date") {
                    Picker("Date type", selection: $dateType) {
                        Text(DateType.useBy.title).tag(DateType.useBy)
                        Text(DateType.bestBefore.title).tag(DateType.bestBefore)
                    }
                    .pickerStyle(.segmented)
                    if hasDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    } else {
                        Button("Add date") { hasDate = true }
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = item.name
                date = item.date
                dateType = item.dateType
                hasDate = item.hasDate
                icon = item.iconAsset ?? suggestedIcon(for: item.name)
            }
            // 이름을 바꾸면 아이콘 추천 (직접 고른 뒤에는 안 바뀜)
            .onChange(of: name) { _, newName in
                guard !iconPickedByUser else { return }
                if let suggested = suggestedIcon(for: newName) { icon = suggested }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selected: icon) { picked in
                    icon = picked
                    iconPickedByUser = true
                }
                .environment(store)
            }
        }
    }

    /// 이름으로 아이콘 추천: 스캔할 때와 같은 방식(LabelParser)으로 100개 음식 중에서 찾기
    private func suggestedIcon(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let exact = store.preset(named: trimmed) { return exact.icon }
        return LabelParser.read([trimmed], presets: store.presets).preset?.icon
    }

    private func save() {
        var updated = item
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.date = date
        updated.dateType = dateType
        updated.hasDate = hasDate
        if let preset = store.preset(named: updated.name) {
            updated.category = preset.category
            updated.storage = preset.storageBeforeOpening
            updated.presetName = preset.name
        }
        updated.iconAsset = icon
        onSave(updated)
        dismiss()
    }
}

/// 아이콘 직접 고르기: 100개 음식 아이콘 격자 + 검색
struct IconPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let selected: String?
    var onPick: (String) -> Void
    @State private var search = ""

    private struct IconChoice: Identifiable {
        let id: String      // icon asset name
        let name: String
    }

    private var choices: [IconChoice] {
        var seen: Set<String> = ["food_unknown_food"]
        var list = [IconChoice(id: "food_unknown_food", name: "Other")]
        for preset in store.presets where !seen.contains(preset.icon) {
            seen.insert(preset.icon)
            list.append(IconChoice(id: preset.icon, name: preset.name))
        }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? list : list.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 16) {
                    ForEach(choices) { choice in
                        Button {
                            onPick(choice.id)
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                FoodIconView(asset: choice.id, size: 56)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(choice.id == selected ? Palette.ink : Color.clear, lineWidth: 2)
                                    )
                                Text(choice.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .searchable(text: $search, prompt: "Search food")
            .navigationTitle("Choose icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
