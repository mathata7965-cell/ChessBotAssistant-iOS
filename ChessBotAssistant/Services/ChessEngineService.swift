import Foundation

@MainActor
final class ChessEngineService: ObservableObject {
    private enum DefaultsKey {
        static let targetDepth = "cbot.engine.targetDepth"
        static let multiPVCount = "cbot.engine.multiPVCount"
        static let autoHintEnabled = "cbot.engine.autoHintEnabled"
        static let useCloudStockfish = "cbot.engine.useCloudStockfish"
        static let zeroNetworkIsolationMode = "cbot.engine.zeroNetworkIsolationMode"
        static let humanMatchSafetyLockEnabled = "cbot.engine.humanMatchSafetyLockEnabled"
        static let coachPieceOnlyHintMode = "cbot.engine.coachPieceOnlyHintMode"
        static let playStyleMode = "cbot.engine.playStyleMode"
        static let botTargetProfile = "cbot.engine.botTargetProfile"
        static let masterPersonaMode = "cbot.engine.masterPersonaMode"
        static let humanTargetElo = "cbot.engine.humanTargetElo"
        static let showOpponentReplyArrow = "cbot.engine.showOpponentReplyArrow"
    }

    private var isRestoringSettings: Bool = false

    @Published var targetDepth: Int = 12 {
        didSet { persistSetting(targetDepth, forKey: DefaultsKey.targetDepth) }
    }
    @Published var multiPVCount: Int = 3 {
        didSet { persistSetting(multiPVCount, forKey: DefaultsKey.multiPVCount) }
    }
    @Published var autoHintEnabled: Bool = true {
        didSet { persistSetting(autoHintEnabled, forKey: DefaultsKey.autoHintEnabled) }
    }
    @Published var useCloudStockfish: Bool = true {
        didSet { persistSetting(useCloudStockfish, forKey: DefaultsKey.useCloudStockfish) }
    }

    // 防誤封與隱私隔離保護設定
    @Published var zeroNetworkIsolationMode: Bool = false {
        didSet { persistSetting(zeroNetworkIsolationMode, forKey: DefaultsKey.zeroNetworkIsolationMode) }
    }
    @Published var humanMatchSafetyLockEnabled: Bool = true {
        didSet { persistSetting(humanMatchSafetyLockEnabled, forKey: DefaultsKey.humanMatchSafetyLockEnabled) }
    }
    @Published var coachPieceOnlyHintMode: Bool = false {
        didSet { persistSetting(coachPieceOnlyHintMode, forKey: DefaultsKey.coachPieceOnlyHintMode) }
    }

    // 下棋風格與進階戰術視覺化設定
    @Published var playStyleMode: PlayStyleMode = .engineBest {
        didSet { persistSetting(playStyleMode.rawValue, forKey: DefaultsKey.playStyleMode) }
    }
    @Published var botTargetProfile: BotTargetProfile = .universal {
        didSet { persistSetting(botTargetProfile.rawValue, forKey: DefaultsKey.botTargetProfile) }
    }
    @Published var masterPersonaMode: MasterPersonaMode = .autoAdaptive {
        didSet { persistSetting(masterPersonaMode.rawValue, forKey: DefaultsKey.masterPersonaMode) }
    }
    @Published var humanTargetElo: Int = 1650 {
        didSet { persistSetting(humanTargetElo, forKey: DefaultsKey.humanTargetElo) }
    }
    @Published var showOpponentReplyArrow: Bool = true {
        didSet { persistSetting(showOpponentReplyArrow, forKey: DefaultsKey.showOpponentReplyArrow) }
    }
    @Published var excludedUCIMoves: Set<String> = []

    @Published private(set) var isAnalyzing: Bool = false
    @Published private(set) var currentAnalysis: EngineAnalysisResult?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastAIJudgmentReason: String = "AI 局勢自理系統待命"

    init() {
        loadSettings()
    }

    private func persistSetting(_ value: Any, forKey key: String) {
        guard !isRestoringSettings else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        isRestoringSettings = true
        defer { isRestoringSettings = false }

        if defaults.object(forKey: DefaultsKey.targetDepth) != nil {
            targetDepth = max(4, min(18, defaults.integer(forKey: DefaultsKey.targetDepth)))
        }
        if defaults.object(forKey: DefaultsKey.multiPVCount) != nil {
            multiPVCount = max(1, min(3, defaults.integer(forKey: DefaultsKey.multiPVCount)))
        }
        if defaults.object(forKey: DefaultsKey.autoHintEnabled) != nil {
            autoHintEnabled = defaults.bool(forKey: DefaultsKey.autoHintEnabled)
        }
        if defaults.object(forKey: DefaultsKey.useCloudStockfish) != nil {
            useCloudStockfish = defaults.bool(forKey: DefaultsKey.useCloudStockfish)
        }
        if defaults.object(forKey: DefaultsKey.zeroNetworkIsolationMode) != nil {
            zeroNetworkIsolationMode = defaults.bool(forKey: DefaultsKey.zeroNetworkIsolationMode)
        }
        if defaults.object(forKey: DefaultsKey.humanMatchSafetyLockEnabled) != nil {
            humanMatchSafetyLockEnabled = defaults.bool(forKey: DefaultsKey.humanMatchSafetyLockEnabled)
        }
        if defaults.object(forKey: DefaultsKey.coachPieceOnlyHintMode) != nil {
            coachPieceOnlyHintMode = defaults.bool(forKey: DefaultsKey.coachPieceOnlyHintMode)
        }
        if let styleRaw = defaults.string(forKey: DefaultsKey.playStyleMode),
           let parsedStyle = PlayStyleMode(rawValue: styleRaw) {
            playStyleMode = parsedStyle
        }
        if let profileRaw = defaults.string(forKey: DefaultsKey.botTargetProfile),
           let parsedProfile = BotTargetProfile(rawValue: profileRaw) {
            botTargetProfile = parsedProfile
        }
        if let personaRaw = defaults.string(forKey: DefaultsKey.masterPersonaMode),
           let parsedPersona = MasterPersonaMode(rawValue: personaRaw) {
            masterPersonaMode = parsedPersona
        }
        if defaults.object(forKey: DefaultsKey.humanTargetElo) != nil {
            humanTargetElo = defaults.integer(forKey: DefaultsKey.humanTargetElo)
        }
        if defaults.object(forKey: DefaultsKey.showOpponentReplyArrow) != nil {
            showOpponentReplyArrow = defaults.bool(forKey: DefaultsKey.showOpponentReplyArrow)
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(max(4, min(18, targetDepth)), forKey: DefaultsKey.targetDepth)
        defaults.set(max(1, min(3, multiPVCount)), forKey: DefaultsKey.multiPVCount)
        defaults.set(autoHintEnabled, forKey: DefaultsKey.autoHintEnabled)
        defaults.set(useCloudStockfish, forKey: DefaultsKey.useCloudStockfish)
        defaults.set(zeroNetworkIsolationMode, forKey: DefaultsKey.zeroNetworkIsolationMode)
        defaults.set(humanMatchSafetyLockEnabled, forKey: DefaultsKey.humanMatchSafetyLockEnabled)
        defaults.set(coachPieceOnlyHintMode, forKey: DefaultsKey.coachPieceOnlyHintMode)
        defaults.set(playStyleMode.rawValue, forKey: DefaultsKey.playStyleMode)
        defaults.set(botTargetProfile.rawValue, forKey: DefaultsKey.botTargetProfile)
        defaults.set(masterPersonaMode.rawValue, forKey: DefaultsKey.masterPersonaMode)
        defaults.set(humanTargetElo, forKey: DefaultsKey.humanTargetElo)
        defaults.set(showOpponentReplyArrow, forKey: DefaultsKey.showOpponentReplyArrow)
    }

    func resetSettingsToDefaults() {
        isRestoringSettings = true
        targetDepth = 12
        multiPVCount = 3
        autoHintEnabled = true
        useCloudStockfish = true
        zeroNetworkIsolationMode = false
        humanMatchSafetyLockEnabled = true
        coachPieceOnlyHintMode = false
        playStyleMode = .engineBest
        botTargetProfile = .universal
        masterPersonaMode = .autoAdaptive
        humanTargetElo = 1650
        showOpponentReplyArrow = true
        isRestoringSettings = false
        saveSettings()
    }

    private var activeTask: Task<Void, Never>?
    private var ponderTask: Task<Void, Never>?
    private var cloudCache: [String: EngineAnalysisResult] = [:]
    private var localCache: [String: EngineAnalysisResult] = [:]
    private var lastRawAnalysis: EngineAnalysisResult?
    private var lastRawPositionKey: String?

    private let fastURLSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 1.2
        config.timeoutIntervalForResource = 1.8
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    private func storeCloudCache(_ result: EngineAnalysisResult, forKey key: String) {
        if cloudCache.count >= 128 {
            cloudCache.removeAll(keepingCapacity: true)
        }
        cloudCache[key] = result
    }

    private func storeLocalCache(_ result: EngineAnalysisResult, forKey key: String) {
        if localCache.count >= 128 {
            localCache.removeAll(keepingCapacity: true)
        }
        localCache[key] = result
    }

    @discardableResult
    func reapplyPlayStyle(for board: ChessBoardState) -> Bool {
        guard lastRawPositionKey == board.positionKey, let raw = lastRawAnalysis else { return false }
        let safeRaw = Self.enforceSafeLines(raw, board: board, excludedUCIs: excludedUCIMoves, multiPV: multiPVCount)
        let applied = Self.applyPlayStyle(
            playStyleMode,
            botProfile: botTargetProfile,
            masterPersona: masterPersonaMode,
            humanTargetElo: humanTargetElo,
            to: safeRaw,
            board: board
        )
        currentAnalysis = applied
        lastAIJudgmentReason = Self.describeAutonomousJudgment(
            persona: masterPersonaMode,
            board: board,
            bestCpForSide: (applied.lines.first?.scoreCentipawns ?? 0) * (board.sideToMove == .white ? 1 : -1)
        )
        return true
    }

    func cancelAnalysis() {
        activeTask?.cancel()
        activeTask = nil
        ponderTask?.cancel()
        ponderTask = nil
        isAnalyzing = false
    }

    func clearAnalysis() {
        activeTask?.cancel()
        activeTask = nil
        ponderTask?.cancel()
        ponderTask = nil
        isAnalyzing = false
        currentAnalysis = nil
        lastRawAnalysis = nil
        lastRawPositionKey = nil
    }

    func analyze(board: ChessBoardState, preserveExcludedMoves: Bool = false) {
        activeTask?.cancel()
        ponderTask?.cancel()
        ponderTask = nil
        lastErrorMessage = nil

        if !preserveExcludedMoves {
            excludedUCIMoves.removeAll()
        }

        if lastRawPositionKey != board.positionKey {
            currentAnalysis = nil
        }

        let legal = board.legalMoves()
        let fen = board.toFEN()

        if legal.isEmpty {
            isAnalyzing = false
            let inCheck = board.isKingInCheck(board.sideToMove)
            let winnerCP = inCheck ? (board.sideToMove == .white ? -30000 : 30000) : 0
            let mateVal: Int? = inCheck ? (board.sideToMove == .white ? -0 : 0) : nil
            currentAnalysis = EngineAnalysisResult(
                fen: fen,
                sideToMove: board.sideToMove,
                lines: [],
                depthReached: 0,
                isCloudVerified: false,
                engineSource: inCheck ? "將殺結束" : "逼和結束",
                nodesSearched: 0,
                timestamp: Date()
            )
            _ = (winnerCP, mateVal)
            return
        }

        let requestedDepth = max(4, min(18, targetDepth))
        let requestedPV = max(1, min(3, multiPVCount))
        let isZeroNetwork = zeroNetworkIsolationMode
        let allowCloud = useCloudStockfish && !isZeroNetwork
        let activeStyle = playStyleMode
        let activeBotProfile = botTargetProfile
        let activeMasterPersona = masterPersonaMode
        let activeElo = humanTargetElo
        let excludedSet = excludedUCIMoves
        let cacheKey = "\(board.positionKey)|d\(requestedDepth)|pv\(requestedPV)"

        // 0. Check bundled 10MB Offline GM Engine Pack opening book first (0ms response)
        if excludedSet.isEmpty,
           let bookHit = OfflineEnginePack.shared.lookupBookLines(for: board, multiPV: requestedPV),
           !bookHit.lines.isEmpty {
            let bookResult = EngineAnalysisResult(
                fen: fen,
                sideToMove: board.sideToMove,
                lines: bookHit.lines,
                depthReached: 20,
                isCloudVerified: true,
                engineSource: "離線大師開局庫 (\(OfflineEnginePack.shared.packSizeMBString))",
                nodesSearched: bookHit.lines.count,
                timestamp: Date()
            )
            let safeBook = Self.enforceSafeLines(bookResult, board: board, excludedUCIs: excludedSet, multiPV: requestedPV)
            lastRawAnalysis = safeBook
            lastRawPositionKey = board.positionKey
            currentAnalysis = Self.applyPlayStyle(
                activeStyle,
                botProfile: activeBotProfile,
                masterPersona: activeMasterPersona,
                humanTargetElo: activeElo,
                to: safeBook,
                board: board
            )
            lastAIJudgmentReason = Self.describeAutonomousJudgment(
                persona: activeMasterPersona,
                board: board,
                bestCpForSide: (currentAnalysis?.lines.first?.scoreCentipawns ?? 0) * (board.sideToMove == .white ? 1 : -1)
            )
            if !allowCloud || safeBook.lines.count >= requestedPV {
                isAnalyzing = false
                ponderOpponentReplies(from: board, analysis: currentAnalysis)
                return
            }
        }

        let prefetchedLocal = localCache[cacheKey]

        if allowCloud, let cached = cloudCache[cacheKey] {
            let safeCached = Self.enforceSafeLines(cached, board: board, excludedUCIs: excludedSet, multiPV: requestedPV)
            if !safeCached.lines.isEmpty {
                lastRawAnalysis = safeCached
                lastRawPositionKey = board.positionKey
                currentAnalysis = Self.applyPlayStyle(
                    activeStyle,
                    botProfile: activeBotProfile,
                    masterPersona: activeMasterPersona,
                    humanTargetElo: activeElo,
                    to: safeCached,
                    board: board
                )
                lastAIJudgmentReason = Self.describeAutonomousJudgment(
                    persona: activeMasterPersona,
                    board: board,
                    bestCpForSide: (currentAnalysis?.lines.first?.scoreCentipawns ?? 0) * (board.sideToMove == .white ? 1 : -1)
                )
                isAnalyzing = false
                ponderOpponentReplies(from: board, analysis: currentAnalysis)
                return
            }
        }

        if !allowCloud, let cachedLocal = prefetchedLocal {
            let safeCached = Self.enforceSafeLines(cachedLocal, board: board, excludedUCIs: excludedSet, multiPV: requestedPV)
            if !safeCached.lines.isEmpty {
                lastRawAnalysis = safeCached
                lastRawPositionKey = board.positionKey
                currentAnalysis = Self.applyPlayStyle(
                    activeStyle,
                    botProfile: activeBotProfile,
                    masterPersona: activeMasterPersona,
                    humanTargetElo: activeElo,
                    to: safeCached,
                    board: board
                )
                lastAIJudgmentReason = Self.describeAutonomousJudgment(
                    persona: activeMasterPersona,
                    board: board,
                    bestCpForSide: (currentAnalysis?.lines.first?.scoreCentipawns ?? 0) * (board.sideToMove == .white ? 1 : -1)
                )
                isAnalyzing = false
                ponderOpponentReplies(from: board, analysis: currentAnalysis)
                return
            }
        }

        isAnalyzing = true

        activeTask = Task { [weak self] in
            guard let self else { return }

            if allowCloud {
                let cloudTask = Task {
                    await self.fetchCloudAnalysis(
                        board: board,
                        requestedDepth: requestedDepth,
                        multiPV: requestedPV,
                        addHumanJitter: activeStyle == .humanSafe
                    )
                }

                let localTask: Task<EngineAnalysisResult, Never>? = (prefetchedLocal?.depthReached ?? 0) >= 6
                    ? nil
                    : Task.detached(priority: .userInitiated) {
                        LocalAlphaBetaEngine.analyze(
                            board: board,
                            maxDepth: min(requestedDepth, 10),
                            multiPV: requestedPV,
                            timeBudgetSeconds: 0.28,
                            isZeroNetworkMode: isZeroNetwork,
                            excludedUCIs: excludedSet
                        )
                    }

                // Single-Commit Policy: race Cloud (up to 0.42s) simultaneously with LocalAlphaBetaEngine (0.28s)
                let raceOutcome: (timedOut: Bool, result: EngineAnalysisResult?) = await withTaskGroup(
                    of: (timedOut: Bool, result: EngineAnalysisResult?).self
                ) { group in
                    group.addTask {
                        let val = await cloudTask.value
                        return (false, val)
                    }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 420_000_000)
                        return (true, nil)
                    }
                    while let first = await group.next() {
                        group.cancelAll()
                        return first
                    }
                    return (true, nil)
                }

                if Task.isCancelled {
                    cloudTask.cancel()
                    localTask?.cancel()
                    return
                }

                if let rawCloud = raceOutcome.result, !rawCloud.lines.isEmpty {
                    let finalCloud: EngineAnalysisResult
                    if rawCloud.lines.count < requestedPV {
                        let localFallback: EngineAnalysisResult
                        if let pre = prefetchedLocal {
                            localFallback = pre
                            localTask?.cancel()
                        } else if let localTask {
                            localFallback = await localTask.value
                        } else {
                            localFallback = LocalAlphaBetaEngine.analyze(
                                board: board,
                                maxDepth: min(requestedDepth, 8),
                                multiPV: requestedPV,
                                timeBudgetSeconds: 0.18,
                                isZeroNetworkMode: isZeroNetwork,
                                excludedUCIs: excludedSet
                            )
                        }
                        if Task.isCancelled { return }
                        finalCloud = Self.mergeCloudWithLocalFallback(
                            cloud: rawCloud,
                            localLines: localFallback.lines,
                            multiPV: requestedPV
                        )
                    } else {
                        localTask?.cancel()
                        finalCloud = rawCloud
                    }

                    self.storeCloudCache(finalCloud, forKey: cacheKey)
                    let safeCloud = Self.enforceSafeLines(finalCloud, board: board, excludedUCIs: excludedSet, multiPV: requestedPV)
                    self.lastRawAnalysis = safeCloud
                    self.lastRawPositionKey = board.positionKey
                    self.currentAnalysis = Self.applyPlayStyle(
                        self.playStyleMode,
                        botProfile: self.botTargetProfile,
                        masterPersona: self.masterPersonaMode,
                        humanTargetElo: self.humanTargetElo,
                        to: safeCloud,
                        board: board
                    )
                } else {
                    let localResult: EngineAnalysisResult
                    if let pre = prefetchedLocal, pre.depthReached >= 6 {
                        localResult = pre
                        localTask?.cancel()
                    } else if let localTask {
                        localResult = await localTask.value
                    } else {
                        localResult = prefetchedLocal ?? LocalAlphaBetaEngine.analyze(
                            board: board,
                            maxDepth: min(requestedDepth, 10),
                            multiPV: requestedPV,
                            timeBudgetSeconds: 0.28,
                            isZeroNetworkMode: isZeroNetwork,
                            excludedUCIs: excludedSet
                        )
                    }

                    if Task.isCancelled {
                        cloudTask.cancel()
                        return
                    }

                    // Silently warm cloudCache in background if 0.42s cutoff fired (never mutates currentAnalysis mid-turn)
                    if raceOutcome.timedOut {
                        Task { [weak self] in
                            guard let self else { return }
                            if let lateCloud = await cloudTask.value, !lateCloud.lines.isEmpty {
                                let mergedLate = Self.mergeCloudWithLocalFallback(
                                    cloud: lateCloud,
                                    localLines: localResult.lines,
                                    multiPV: requestedPV
                                )
                                self.storeCloudCache(mergedLate, forKey: cacheKey)
                            }
                        }
                    } else {
                        cloudTask.cancel()
                    }

                    let safeLocal = Self.enforceSafeLines(localResult, board: board, excludedUCIs: excludedSet, multiPV: requestedPV)
                    self.storeLocalCache(safeLocal, forKey: cacheKey)
                    self.lastRawAnalysis = safeLocal
                    self.lastRawPositionKey = board.positionKey
                    self.currentAnalysis = Self.applyPlayStyle(
                        self.playStyleMode,
                        botProfile: self.botTargetProfile,
                        masterPersona: self.masterPersonaMode,
                        humanTargetElo: self.humanTargetElo,
                        to: safeLocal,
                        board: board
                    )
                }
            } else {
                let localResult = await Task.detached(priority: .userInitiated) {
                    LocalAlphaBetaEngine.analyze(
                        board: board,
                        maxDepth: min(requestedDepth, 12),
                        multiPV: requestedPV,
                        timeBudgetSeconds: 0.85,
                        isZeroNetworkMode: isZeroNetwork,
                        excludedUCIs: excludedSet
                    )
                }.value

                if Task.isCancelled { return }

                let safeLocal = Self.enforceSafeLines(localResult, board: board, excludedUCIs: excludedSet, multiPV: requestedPV)
                self.storeLocalCache(safeLocal, forKey: cacheKey)
                self.lastRawAnalysis = safeLocal
                self.lastRawPositionKey = board.positionKey
                self.currentAnalysis = Self.applyPlayStyle(
                    self.playStyleMode,
                    botProfile: self.botTargetProfile,
                    masterPersona: self.masterPersonaMode,
                    humanTargetElo: self.humanTargetElo,
                    to: safeLocal,
                    board: board
                )
            }

            if !Task.isCancelled {
                self.isAnalyzing = false
                let stmSign = board.sideToMove == .white ? 1 : -1
                let topCp = (self.currentAnalysis?.lines.first?.scoreCentipawns ?? 0) * stmSign
                self.lastAIJudgmentReason = Self.describeAutonomousJudgment(
                    persona: self.masterPersonaMode,
                    board: board,
                    bestCpForSide: topCp
                )
                self.ponderOpponentReplies(from: board, analysis: self.currentAnalysis)
            }
        }
    }

    func ponderOpponentReplies(from board: ChessBoardState, analysis: EngineAnalysisResult?) {
        guard autoHintEnabled, let topLine = analysis?.lines.first else { return }
        let afterOurMove = board.applyingRaw(topLine.bestMove)
        if let oppReply = topLine.predictedOpponentReply {
            let nextOurBoard = afterOurMove.applyingRaw(oppReply)
            startPonderTask(targetBoards: [nextOurBoard], seedBoard: nil)
        } else {
            startPonderTask(targetBoards: [], seedBoard: afterOurMove)
        }
    }

    func ponderWhileWaitingForOpponent(boardAfterOurMove: ChessBoardState) {
        guard autoHintEnabled else { return }
        startPonderTask(targetBoards: [], seedBoard: boardAfterOurMove)
    }

    private func startPonderTask(targetBoards: [ChessBoardState], seedBoard: ChessBoardState?) {
        ponderTask?.cancel()
        ponderTask = nil

        let requestedDepth = max(4, min(18, targetDepth))
        let requestedPV = max(1, min(3, multiPVCount))
        let isZeroNetwork = zeroNetworkIsolationMode
        let allowCloud = useCloudStockfish && !isZeroNetwork

        ponderTask = Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            if Task.isCancelled { return }

            var boardsToPonder = targetBoards
            if boardsToPonder.isEmpty, let seed = seedBoard, !seed.legalMoves(includeFormattedSAN: false).isEmpty {
                let oppAnalysis = await Task.detached(priority: .utility) {
                    LocalAlphaBetaEngine.analyze(
                        board: seed,
                        maxDepth: 6,
                        multiPV: 2,
                        timeBudgetSeconds: 0.22,
                        isZeroNetworkMode: true,
                        excludedUCIs: []
                    )
                }.value
                if Task.isCancelled { return }
                boardsToPonder = oppAnalysis.lines.prefix(2).map { seed.applyingRaw($0.bestMove) }
            }

            for candidate in boardsToPonder.prefix(2) {
                if Task.isCancelled { return }
                guard !candidate.legalMoves(includeFormattedSAN: false).isEmpty else { continue }

                let pKey = "\(candidate.positionKey)|d\(requestedDepth)|pv\(requestedPV)"

                if self.localCache[pKey] == nil {
                    let ponderedLocal = await Task.detached(priority: .utility) {
                        LocalAlphaBetaEngine.analyze(
                            board: candidate,
                            maxDepth: min(requestedDepth, 10),
                            multiPV: requestedPV,
                            timeBudgetSeconds: 0.42,
                            isZeroNetworkMode: isZeroNetwork,
                            excludedUCIs: []
                        )
                    }.value
                    if Task.isCancelled { return }
                    if !ponderedLocal.lines.isEmpty {
                        self.storeLocalCache(ponderedLocal, forKey: pKey)
                    }
                }

                if allowCloud && self.cloudCache[pKey] == nil {
                    if let ponderedCloud = await self.fetchCloudAnalysis(
                        board: candidate,
                        requestedDepth: requestedDepth,
                        multiPV: requestedPV,
                        addHumanJitter: false
                    ), !ponderedCloud.lines.isEmpty {
                        if Task.isCancelled { return }
                        let localLines = self.localCache[pKey]?.lines ?? []
                        let merged = Self.mergeCloudWithLocalFallback(
                            cloud: ponderedCloud,
                            localLines: localLines,
                            multiPV: requestedPV
                        )
                        self.storeCloudCache(merged, forKey: pKey)
                    }
                }
            }
        }
    }

    // MARK: - Cloud Stockfish Integration

    private static func enforceSafeLines(
        _ result: EngineAnalysisResult,
        board: ChessBoardState,
        excludedUCIs: Set<String>,
        multiPV: Int
    ) -> EngineAnalysisResult {
        var filtered = result.lines.filter { !excludedUCIs.contains($0.bestMove.uci) }

        if filtered.isEmpty && !excludedUCIs.isEmpty {
            let emergency = LocalAlphaBetaEngine.analyze(
                board: board,
                maxDepth: 3,
                multiPV: multiPV,
                timeBudgetSeconds: 0.20,
                isZeroNetworkMode: true,
                excludedUCIs: excludedUCIs
            )
            filtered = emergency.lines
        }

        // Guarantee at least one non-castling legal move if #1 is castling
        if filtered.first?.bestMove.isCastling == true,
           !filtered.contains(where: { !$0.bestMove.isCastling }) {
            let nonCastleLegal = board.legalMoves().filter {
                !$0.isCastling && !excludedUCIs.contains($0.uci)
            }
            if let fallbackMove = nonCastleLegal.max(by: { m1, m2 in
                let b1 = board.applyingRaw(m1)
                let b2 = board.applyingRaw(m2)
                let s1 = LocalAlphaBetaEngine.evaluate(board: b1) * (board.sideToMove == .white ? 1 : -1)
                let s2 = LocalAlphaBetaEngine.evaluate(board: b2) * (board.sideToMove == .white ? 1 : -1)
                return s1 < s2
            }) {
                let evalCP = LocalAlphaBetaEngine.evaluate(board: board.applyingRaw(fallbackMove))
                let reply = extractOpponentReply(on: board, firstMove: fallbackMove, continuationUCI: [fallbackMove.uci])
                let extraLine = PVLine(
                    multipvIndex: filtered.count + 1,
                    bestMove: fallbackMove,
                    continuationSAN: [fallbackMove.san],
                    continuationUCI: [fallbackMove.uci],
                    scoreCentipawns: evalCP,
                    mateInMoves: nil,
                    depth: max(2, result.depthReached),
                    sourceLabel: "安全備選",
                    predictedOpponentReply: reply,
                    tacticalReason: board.explainMoveTactics(fallbackMove)
                )
                filtered.append(extraLine)
            }
        }

        let reindexed = filtered.prefix(max(1, multiPV)).enumerated().map { idx, line in
            let reason = line.tacticalReason.isEmpty ? board.explainMoveTactics(line.bestMove) : line.tacticalReason
            return PVLine(
                multipvIndex: idx + 1,
                bestMove: line.bestMove,
                continuationSAN: line.continuationSAN,
                continuationUCI: line.continuationUCI,
                scoreCentipawns: line.scoreCentipawns,
                mateInMoves: line.mateInMoves,
                depth: line.depth,
                sourceLabel: line.sourceLabel,
                predictedOpponentReply: line.predictedOpponentReply,
                tacticalReason: reason
            )
        }

        return EngineAnalysisResult(
            fen: result.fen,
            sideToMove: result.sideToMove,
            lines: reindexed,
            depthReached: result.depthReached,
            isCloudVerified: result.isCloudVerified,
            engineSource: result.engineSource,
            nodesSearched: result.nodesSearched,
            timestamp: result.timestamp,
            searchTimeMs: result.searchTimeMs
        )
    }

    private static func mergeCloudWithLocalFallback(
        cloud: EngineAnalysisResult,
        localLines: [PVLine],
        multiPV: Int
    ) -> EngineAnalysisResult {
        guard cloud.lines.count < multiPV else { return cloud }
        var merged = cloud.lines
        let existingUCIs = Set(merged.map { $0.bestMove.uci })
        var nextIdx = merged.count + 1

        for local in localLines where !existingUCIs.contains(local.bestMove.uci) {
            if merged.count >= multiPV { break }
            merged.append(PVLine(
                multipvIndex: nextIdx,
                bestMove: local.bestMove,
                continuationSAN: local.continuationSAN,
                continuationUCI: local.continuationUCI,
                scoreCentipawns: local.scoreCentipawns,
                mateInMoves: local.mateInMoves,
                depth: local.depth,
                sourceLabel: "本地備選",
                predictedOpponentReply: local.predictedOpponentReply,
                tacticalReason: local.tacticalReason
            ))
            nextIdx += 1
        }

        return EngineAnalysisResult(
            fen: cloud.fen,
            sideToMove: cloud.sideToMove,
            lines: merged,
            depthReached: cloud.depthReached,
            isCloudVerified: cloud.isCloudVerified,
            engineSource: cloud.engineSource,
            nodesSearched: cloud.nodesSearched,
            timestamp: cloud.timestamp,
            searchTimeMs: cloud.searchTimeMs
        )
    }

    private nonisolated static func totalPieceCount(in board: ChessBoardState) -> Int {
        var count = 0
        for r in 0..<8 {
            let row = board.squares[r]
            for c in 0..<8 where row[c] != nil {
                count += 1
            }
        }
        return count
    }

    private func fetchCloudAnalysis(
        board: ChessBoardState,
        requestedDepth: Int,
        multiPV: Int,
        addHumanJitter: Bool = false
    ) async -> EngineAnalysisResult? {
        if addHumanJitter {
            let jitterNs = UInt64(Int.random(in: 45...120)) * 1_000_000
            try? await Task.sleep(nanoseconds: jitterNs)
            if Task.isCancelled { return nil }
        }
        let cloudStart = CFAbsoluteTimeGetCurrent()
        let sfDepth = min(max(requestedDepth, 10), 15)
        let fen = board.toFEN()
        let isSyzygyEligible = Self.totalPieceCount(in: board) <= 7

        return await withTaskGroup(of: EngineAnalysisResult?.self) { group in
            if isSyzygyEligible {
                group.addTask { [weak self] in
                    guard let self,
                          let syzygyLines = await self.querySyzygyTablebase(board: board, multiPV: multiPV),
                          !syzygyLines.isEmpty else { return nil }
                    let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - cloudStart) * 1000.0).rounded()))
                    return EngineAnalysisResult(
                        fen: fen,
                        sideToMove: board.sideToMove,
                        lines: Array(syzygyLines.prefix(multiPV)),
                        depthReached: 99,
                        isCloudVerified: true,
                        engineSource: "Syzygy 7-Man 殘局庫",
                        nodesSearched: syzygyLines.count,
                        timestamp: Date(),
                        searchTimeMs: elapsedMs
                    )
                }
            }
            group.addTask { [weak self] in
                guard let self,
                      let lichessLines = await self.queryLichessCloudEval(board: board, multiPV: multiPV),
                      !lichessLines.lines.isEmpty else { return nil }
                let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - cloudStart) * 1000.0).rounded()))
                return EngineAnalysisResult(
                    fen: fen,
                    sideToMove: board.sideToMove,
                    lines: Array(lichessLines.lines.prefix(multiPV)),
                    depthReached: lichessLines.depth,
                    isCloudVerified: true,
                    engineSource: "Stockfish NNUE (Lichess Cloud)",
                    nodesSearched: lichessLines.knodes * 1000,
                    timestamp: Date(),
                    searchTimeMs: elapsedMs
                )
            }
            group.addTask { [weak self] in
                guard let self,
                      let sfLine = await self.queryStockfishOnline(board: board, depth: sfDepth) else { return nil }
                let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - cloudStart) * 1000.0).rounded()))
                return EngineAnalysisResult(
                    fen: fen,
                    sideToMove: board.sideToMove,
                    lines: [sfLine],
                    depthReached: sfDepth,
                    isCloudVerified: true,
                    engineSource: "Stockfish 16 NNUE",
                    nodesSearched: 0,
                    timestamp: Date(),
                    searchTimeMs: elapsedMs
                )
            }

            while let candidate = await group.next() {
                if let valid = candidate, !valid.lines.isEmpty {
                    group.cancelAll()
                    return valid
                }
            }
            return nil
        }
    }

    private func querySyzygyTablebase(board: ChessBoardState, multiPV: Int) async -> [PVLine]? {
        let fen = board.toFEN()
        guard var components = URLComponents(string: "https://tablebase.lichess.ovh/standard") else { return nil }
        components.queryItems = [URLQueryItem(name: "fen", value: fen)]
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 0.9)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await fastURLSession.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(SyzygyTablebaseResponse.self, from: data)
            guard !decoded.moves.isEmpty else { return nil }

            var parsedLines: [PVLine] = []
            for entry in decoded.moves {
                if parsedLines.count >= multiPV { break }
                guard let firstMove = board.legalMove(uci: entry.uci) else { continue }

                var mateMoves: Int? = nil
                let whiteCP: Int

                if entry.checkmate == true {
                    mateMoves = board.sideToMove == .white ? 1 : -1
                    whiteCP = board.sideToMove == .white ? 29990 : -29990
                } else {
                    // In Lichess tablebase API, each move's `category` and `dtm` describe the position AFTER the move (opponent's turn).
                    switch entry.category {
                    case "loss":
                        if let dtm = entry.dtm {
                            let fullMoves = max(1, (abs(dtm) + 2) / 2)
                            mateMoves = board.sideToMove == .white ? fullMoves : -fullMoves
                            whiteCP = board.sideToMove == .white ? (30000 - fullMoves * 10) : (-30000 + fullMoves * 10)
                        } else {
                            let sideCP = 1800 - min(600, abs(entry.dtz ?? 0) * 8)
                            whiteCP = board.sideToMove == .white ? sideCP : -sideCP
                        }
                    case "blessed-loss":
                        let sideCP = 140 - min(80, abs(entry.dtz ?? 20))
                        whiteCP = board.sideToMove == .white ? sideCP : -sideCP
                    case "draw":
                        whiteCP = 0
                    case "cursed-win":
                        let sideCP = -140 + min(80, abs(entry.dtz ?? 20))
                        whiteCP = board.sideToMove == .white ? sideCP : -sideCP
                    case "win":
                        if let dtm = entry.dtm {
                            let fullMoves = max(1, (abs(dtm) + 2) / 2)
                            mateMoves = board.sideToMove == .white ? -fullMoves : fullMoves
                            whiteCP = board.sideToMove == .white ? (-30000 + fullMoves * 10) : (30000 - fullMoves * 10)
                        } else {
                            let sideCP = -1800 + min(600, abs(entry.dtz ?? 0) * 8)
                            whiteCP = board.sideToMove == .white ? sideCP : -sideCP
                        }
                    default:
                        continue
                    }
                }

                let sanText = firstMove.san.isEmpty ? (entry.san ?? firstMove.uci) : firstMove.san
                let dtzNote = entry.dtz.map { " · Syzygy DTZ \(abs($0))" } ?? ""
                let baseReason = board.explainMoveTactics(firstMove)

                parsedLines.append(PVLine(
                    multipvIndex: parsedLines.count + 1,
                    bestMove: firstMove,
                    continuationSAN: [sanText],
                    continuationUCI: [firstMove.uci],
                    scoreCentipawns: whiteCP,
                    mateInMoves: mateMoves,
                    depth: 99,
                    sourceLabel: "Syzygy 7子",
                    predictedOpponentReply: Self.extractOpponentReply(
                        on: board,
                        firstMove: firstMove,
                        continuationUCI: [firstMove.uci]
                    ),
                    tacticalReason: baseReason + dtzNote
                ))
            }

            return parsedLines.isEmpty ? nil : parsedLines
        } catch {
            return nil
        }
    }

    private func queryLichessCloudEval(board: ChessBoardState, multiPV: Int) async -> (lines: [PVLine], depth: Int, knodes: Int)? {
        let fen = board.toFEN()
        guard var components = URLComponents(string: "https://lichess.org/api/cloud-eval") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "multiPv", value: String(multiPV))
        ]
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 1.0)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await fastURLSession.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(LichessCloudEvalResponse.self, from: data)
            let depth = decoded.depth ?? 20
            var parsedLines: [PVLine] = []

            for (idx, pv) in decoded.pvs.enumerated() {
                let uciTokens = pv.moves.split(separator: " ").map { String($0) }
                guard let firstUCI = uciTokens.first,
                      let firstMove = board.legalMove(uci: firstUCI) else { continue }

                let sanLine = Self.convertUCILineToSAN(startBoard: board, uciMoves: uciTokens)
                let cp: Int
                if let mate = pv.mate {
                    cp = mate > 0 ? (30000 - abs(mate) * 10) : (-30000 + abs(mate) * 10)
                } else {
                    cp = pv.cp ?? 0
                }

                parsedLines.append(PVLine(
                    multipvIndex: idx + 1,
                    bestMove: firstMove,
                    continuationSAN: sanLine,
                    continuationUCI: uciTokens,
                    scoreCentipawns: cp,
                    mateInMoves: pv.mate,
                    depth: depth,
                    sourceLabel: "SF Cloud",
                    predictedOpponentReply: Self.extractOpponentReply(
                        on: board,
                        firstMove: firstMove,
                        continuationUCI: uciTokens
                    ),
                    tacticalReason: board.explainMoveTactics(firstMove)
                ))
            }
            return (parsedLines, depth, decoded.knodes ?? 0)
        } catch {
            return nil
        }
    }

    private func queryStockfishOnline(board: ChessBoardState, depth: Int) async -> PVLine? {
        let fen = board.toFEN()
        guard var components = URLComponents(string: "https://stockfish.online/api/s/v2.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "depth", value: String(depth))
        ]
        guard let url = components.url else { return nil }

        let req = URLRequest(url: url, timeoutInterval: 1.1)

        do {
            let (data, response) = try await fastURLSession.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(StockfishOnlineResponse.self, from: data)
            guard decoded.success else { return nil }

            let bestParts = (decoded.bestmove ?? "").split(separator: " ").map { String($0) }
            let bestUCI: String?
            if bestParts.count >= 2 && bestParts[0] == "bestmove" {
                bestUCI = bestParts[1]
            } else {
                bestUCI = bestParts.first
            }

            let contTokens = (decoded.continuation ?? "").split(separator: " ").map { String($0) }
            let primaryUCI = bestUCI ?? contTokens.first
            guard let uci = primaryUCI,
                  let bestMove = board.legalMove(uci: uci) else { return nil }

            let fullUCI: [String]
            if contTokens.first == uci {
                fullUCI = contTokens
            } else {
                fullUCI = [uci] + contTokens.filter { $0 != uci }
            }

            let sanLine = Self.convertUCILineToSAN(startBoard: board, uciMoves: fullUCI)
            let cp: Int
            if let mate = decoded.mate {
                cp = mate > 0 ? (30000 - abs(mate) * 10) : (-30000 + abs(mate) * 10)
            } else {
                cp = Int(((decoded.evaluation ?? 0.0) * 100.0).rounded())
            }

            return PVLine(
                multipvIndex: 1,
                bestMove: bestMove,
                continuationSAN: sanLine,
                continuationUCI: fullUCI,
                scoreCentipawns: cp,
                mateInMoves: decoded.mate,
                depth: depth,
                sourceLabel: "SF16 NNUE",
                predictedOpponentReply: Self.extractOpponentReply(
                    on: board,
                    firstMove: bestMove,
                    continuationUCI: fullUCI
                ),
                tacticalReason: board.explainMoveTactics(bestMove)
            )
        } catch {
            return nil
        }
    }

    nonisolated static func extractOpponentReply(
        on board: ChessBoardState,
        firstMove: ChessMove,
        continuationUCI: [String]
    ) -> ChessMove? {
        let afterFirst = board.applying(firstMove)
        if let secondUCI = continuationUCI.dropFirst().first,
           let reply = afterFirst.legalMove(uci: secondUCI) {
            return reply
        }

        let opponentMoves = afterFirst.legalMoves()
        guard !opponentMoves.isEmpty else { return nil }
        var bestReply = opponentMoves[0]
        var bestVal = -Int.max
        for move in opponentMoves {
            let afterOpp = afterFirst.applyingRaw(move)
            let val = -LocalAlphaBetaEngine.evaluate(board: afterOpp)
            if val > bestVal {
                bestVal = val
                bestReply = move
            }
        }
        return bestReply
    }

    nonisolated static func resolveAutonomousPersona(
        persona: MasterPersonaMode,
        board: ChessBoardState,
        bestCpForSide: Int
    ) -> MasterPersonaMode {
        guard persona == .autoAdaptive else { return persona }
        let nonKingCount = totalPieceCount(in: board) - 2
        if board.isKingInCheck(board.sideToMove) || bestCpForSide <= -140 {
            return .streamerTricks
        }
        if nonKingCount <= 12 {
            return .carlsenEndgame
        }
        if nonKingCount >= 16 && bestCpForSide >= 75 {
            return .talAttack
        }
        if board.fullMoveNumber <= 12 {
            return .nakamuraBlitz
        }
        return .karpovPositional
    }

    nonisolated static func describeAutonomousJudgment(
        persona: MasterPersonaMode,
        board: ChessBoardState,
        bestCpForSide: Int
    ) -> String {
        let resolved = resolveAutonomousPersona(persona: persona, board: board, bestCpForSide: bestCpForSide)
        if persona == .autoAdaptive {
            return "AI自理判斷 → 採用\(resolved.shortName)"
        }
        return "指定模型：\(resolved.shortName)"
    }

    nonisolated static func applyPlayStyle(
        _ style: PlayStyleMode,
        botProfile: BotTargetProfile = .universal,
        masterPersona: MasterPersonaMode = .autoAdaptive,
        humanTargetElo: Int = 1650,
        to result: EngineAnalysisResult,
        board: ChessBoardState
    ) -> EngineAnalysisResult {
        guard result.lines.count > 1 else {
            return result
        }

        let sideMultiplier = board.sideToMove == .white ? 1 : -1
        let bestCpForSide = (result.lines.first?.scoreCentipawns ?? 0) * sideMultiplier
        let effectivePersona = resolveAutonomousPersona(persona: masterPersona, board: board, bestCpForSide: bestCpForSide)

        let styleTolerance: Int
        switch style {
        case .engineBest: styleTolerance = 18
        case .humanSafe:
            if humanTargetElo <= 0 {
                styleTolerance = 25
            } else if humanTargetElo <= 1300 {
                styleTolerance = 75
            } else if humanTargetElo <= 1700 {
                styleTolerance = 45
            } else if humanTargetElo <= 2000 {
                styleTolerance = 30
            } else {
                styleTolerance = 18
            }
        case .aggressive: styleTolerance = 45
        case .defensive: styleTolerance = 35
        }
        let profileTolerance: Int
        switch botProfile {
        case .universal: profileTolerance = 0
        case .antiNelson: profileTolerance = 40
        case .beginnerCrusher: profileTolerance = 45
        case .antiMaster: profileTolerance = 25
        }
        let toleranceCp = max(styleTolerance, profileTolerance)

        let enemyColor = board.sideToMove.opposite
        var enemyQueenSq: BoardSquare? = nil
        var enemyKingSq: BoardSquare? = nil
        for r in 0..<8 {
            for c in 0..<8 {
                guard let p = board.squares[r][c], p.color == enemyColor else { continue }
                if p.type == .queen && enemyQueenSq == nil {
                    enemyQueenSq = BoardSquare(row: r, col: c)
                } else if p.type == .king {
                    enemyKingSq = BoardSquare(row: r, col: c)
                }
            }
        }
        let nonKingPieces = max(0, totalPieceCount(in: board) - 2)

        func styleBonus(for line: PVLine) -> Int {
            let lineCpForSide = line.scoreCentipawns * sideMultiplier
            if line.mateInMoves == nil && (bestCpForSide - lineCpForSide) > toleranceCp {
                return -10_000
            }
            var bonus = 0
            let san = line.bestMove.san
            let move = line.bestMove
            let after = board.applying(move)
            let isInDangerAfter = after.isSquareAttacked(row: move.to.row, col: move.to.col, by: enemyColor)
                && !after.isSquareAttacked(row: move.to.row, col: move.to.col, by: board.sideToMove)
            let movingPiece = board.piece(at: move.from)

            // Master / Streamer Trained Persona Evaluation Modulation
            switch effectivePersona {
            case .autoAdaptive:
                break
            case .carlsenEndgame:
                if nonKingPieces <= 12 && movingPiece?.type == .king {
                    let centerDistBefore = abs(move.from.row * 2 - 7) + abs(move.from.col * 2 - 7)
                    let centerDistAfter = abs(move.to.row * 2 - 7) + abs(move.to.col * 2 - 7)
                    if centerDistAfter < centerDistBefore { bonus += 42 }
                }
                if movingPiece?.type == .pawn {
                    let rankAdvance = board.sideToMove == .white ? (move.from.row - move.to.row) : (move.to.row - move.from.row)
                    if rankAdvance > 0 && !isInDangerAfter { bonus += 24 }
                }
                if bestCpForSide >= 120 && move.capturedPiece != nil && !isInDangerAfter {
                    bonus += 30
                }
            case .nakamuraBlitz:
                if (2...5).contains(move.to.row) && (2...5).contains(move.to.col) && !isInDangerAfter {
                    bonus += 24
                }
                if board.fullMoveNumber <= 12 && (movingPiece?.type == .knight || movingPiece?.type == .bishop || move.isCastling) {
                    bonus += 32
                }
                if let qSq = enemyQueenSq,
                   !isInDangerAfter,
                   after.isSquareAttacked(row: qSq.row, col: qSq.col, by: board.sideToMove) {
                    bonus += 35
                }
            case .talAttack:
                if san.contains("#") { bonus += 600 }
                if san.contains("+") { bonus += 70 }
                if move.capturedPiece != nil { bonus += 42 }
                if let ek = enemyKingSq {
                    let kingDist = max(abs(move.to.row - ek.row), abs(move.to.col - ek.col))
                    if kingDist <= 2 && movingPiece?.type != .king {
                        bonus += 36
                    }
                }
            case .karpovPositional:
                if !isInDangerAfter { bonus += 38 }
                if move.isCastling { bonus += 55 }
                if movingPiece?.type == .knight && (2...5).contains(move.to.row) && (1...6).contains(move.to.col) {
                    bonus += 26
                }
                if movingPiece?.type == .pawn && board.fullMoveNumber <= 16 && (move.from.col >= 5 || move.from.col <= 2) {
                    bonus -= 18
                }
            case .streamerTricks:
                if san.contains("+") && !isInDangerAfter { bonus += 52 }
                if let qSq = enemyQueenSq,
                   !isInDangerAfter,
                   after.isSquareAttacked(row: qSq.row, col: qSq.col, by: board.sideToMove) {
                    bonus += 65
                }
                if movingPiece?.type == .knight && !isInDangerAfter && (2...5).contains(move.to.row) {
                    bonus += 28
                }
            }

            switch style {
            case .engineBest:
                break
            case .aggressive:
                if san.contains("#") { bonus += 500 }
                if san.contains("+") { bonus += 90 }
                if move.capturedPiece != nil { bonus += 70 }
                if move.promotion != nil { bonus += 80 }
            case .defensive:
                if move.isCastling { bonus += 100 }
                if !isInDangerAfter { bonus += 60 }
                if move.capturedPiece == nil && !san.contains("+") { bonus += 35 }
            case .humanSafe:
                if !isInDangerAfter { bonus += 40 }
                if move.isCastling { bonus += 60 }
                if let p = board.piece(at: move.from), p.type == .knight || p.type == .bishop {
                    bonus += 30
                }
            }

            switch botProfile {
            case .universal:
                break
            case .antiNelson:
                if move.capturedPiece?.type == .queen {
                    bonus += 600
                } else if let qSq = enemyQueenSq,
                          !isInDangerAfter,
                          after.isSquareAttacked(row: qSq.row, col: qSq.col, by: board.sideToMove) {
                    bonus += 140
                }
                if board.fullMoveNumber <= 12,
                   let p = board.piece(at: move.from),
                   p.type == .knight || p.type == .bishop || move.isCastling {
                    bonus += 55
                }
            case .beginnerCrusher:
                if san.contains("#") { bonus += 600 }
                if san.contains("+") { bonus += 110 }
                if move.capturedPiece != nil { bonus += 80 }
            case .antiMaster:
                if !isInDangerAfter { bonus += 75 }
                if move.isCastling { bonus += 95 }
                if let p = board.piece(at: move.from),
                   !(p.type == .pawn && board.fullMoveNumber <= 16 && (move.from.col >= 5 || move.from.col <= 2)) {
                    bonus += 30
                }
            }
            return bonus
        }

        let ranked = result.lines.sorted { a, b in
            let sa = styleBonus(for: a)
            let sb = styleBonus(for: b)
            if sa != sb { return sa > sb }
            return a.scoreCentipawns * sideMultiplier > b.scoreCentipawns * sideMultiplier
        }

        let modeTag = style == .engineBest
            ? (botProfile == .universal ? effectivePersona.shortName : "\(effectivePersona.shortName)·\(botProfile.shortName)")
            : "\(style.displayName)·\(effectivePersona.shortName)"
        let reindexed: [PVLine] = ranked.enumerated().map { idx, line in
            var moveCopy = line.bestMove
            if idx == 0 && (moveCopy.tacticalTag == nil || moveCopy.tacticalTag?.isEmpty == true) {
                moveCopy.tacticalTag = modeTag
            }
            return PVLine(
                multipvIndex: idx + 1,
                bestMove: moveCopy,
                continuationSAN: line.continuationSAN,
                continuationUCI: line.continuationUCI,
                scoreCentipawns: line.scoreCentipawns,
                mateInMoves: line.mateInMoves,
                depth: line.depth,
                sourceLabel: "\(line.sourceLabel)•\(modeTag)",
                predictedOpponentReply: line.predictedOpponentReply,
                tacticalReason: line.tacticalReason.isEmpty ? board.explainMoveTactics(moveCopy) : line.tacticalReason
            )
        }

        return EngineAnalysisResult(
            fen: result.fen,
            sideToMove: result.sideToMove,
            lines: reindexed,
            depthReached: result.depthReached,
            isCloudVerified: result.isCloudVerified,
            engineSource: "\(result.engineSource)（\(modeTag)）",
            nodesSearched: result.nodesSearched,
            timestamp: result.timestamp,
            searchTimeMs: result.searchTimeMs
        )
    }

    nonisolated static func convertUCILineToSAN(startBoard: ChessBoardState, uciMoves: [String]) -> [String] {
        var cursor = startBoard
        var result: [String] = []
        for uci in uciMoves.prefix(10) {
            guard let legal = cursor.legalMove(uci: uci) else { break }
            result.append(legal.san)
            cursor = cursor.applying(legal)
        }
        return result
    }
}

private struct LichessCloudEvalResponse: Decodable {
    struct PV: Decodable {
        let moves: String
        let cp: Int?
        let mate: Int?
    }
    let depth: Int?
    let knodes: Int?
    let pvs: [PV]
}

private struct StockfishOnlineResponse: Decodable {
    let success: Bool
    let evaluation: Double?
    let mate: Int?
    let bestmove: String?
    let continuation: String?
}

private struct SyzygyTablebaseResponse: Decodable {
    struct MoveEntry: Decodable {
        let uci: String
        let san: String?
        let checkmate: Bool?
        let stalemate: Bool?
        let insufficient_material: Bool?
        let dtz: Int?
        let dtm: Int?
        let category: String
    }
    let checkmate: Bool?
    let stalemate: Bool?
    let insufficient_material: Bool?
    let dtz: Int?
    let dtm: Int?
    let category: String
    let moves: [MoveEntry]
}

// MARK: - Built-in Offline PeSTO Tapered Alpha-Beta Multi-PV Engine

private enum LocalAlphaBetaEngine {
    private static let mateScore = 30000

    @inline(__always)
    private static func mgPieceValue(_ type: PieceType) -> Int {
        switch type {
        case .pawn: return 82
        case .knight: return 337
        case .bishop: return 365
        case .rook: return 477
        case .queen: return 1025
        case .king: return 0
        }
    }

    @inline(__always)
    private static func egPieceValue(_ type: PieceType) -> Int {
        switch type {
        case .pawn: return 94
        case .knight: return 281
        case .bishop: return 297
        case .rook: return 512
        case .queen: return 936
        case .king: return 0
        }
    }

    @inline(__always)
    private static func piecePhaseWeight(_ type: PieceType) -> Int {
        switch type {
        case .pawn, .king: return 0
        case .knight, .bishop: return 1
        case .rook: return 2
        case .queen: return 4
        }
    }

    @inline(__always)
    private static func pieceBaseValue(_ type: PieceType) -> Int {
        switch type {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 20000
        }
    }

    private static let passedPawnBonus: [Int] = [0, 65, 45, 32, 22, 18, 12, 0]

    private static let whitePassedMasks: [UInt64] = {
        var masks = Array(repeating: UInt64(0), count: 64)
        for r in 0..<8 {
            for c in 0..<8 {
                var m: UInt64 = 0
                for ar in 0..<r {
                    for fc in max(0, c - 1)...min(7, c + 1) {
                        m |= (UInt64(1) &<< (ar * 8 + fc))
                    }
                }
                masks[r * 8 + c] = m
            }
        }
        return masks
    }()

    private static let blackPassedMasks: [UInt64] = {
        var masks = Array(repeating: UInt64(0), count: 64)
        for r in 0..<8 {
            for c in 0..<8 {
                var m: UInt64 = 0
                for ar in (r + 1)..<8 {
                    for fc in max(0, c - 1)...min(7, c + 1) {
                        m |= (UInt64(1) &<< (ar * 8 + fc))
                    }
                }
                masks[r * 8 + c] = m
            }
        }
        return masks
    }()

    private static let whiteShieldFileMasks: [UInt64] = (0..<8).map { c in
        (UInt64(1) &<< (5 * 8 + c)) | (UInt64(1) &<< (6 * 8 + c))
    }

    private static let blackShieldFileMasks: [UInt64] = (0..<8).map { c in
        (UInt64(1) &<< (1 * 8 + c)) | (UInt64(1) &<< (2 * 8 + c))
    }

    private static let fileMasks: [UInt64] = (0..<8).map { c in
        var m: UInt64 = 0
        for r in 0..<8 {
            m |= (UInt64(1) &<< (r * 8 + c))
        }
        return m
    }

    private static let adjacentFileMasks: [UInt64] = (0..<8).map { c in
        var m: UInt64 = 0
        if c > 0 { m |= fileMasks[c - 1] }
        if c < 7 { m |= fileMasks[c + 1] }
        return m
    }

    private static let whiteOutpostMasks: [UInt64] = {
        var masks = Array(repeating: UInt64(0), count: 64)
        for r in 0..<8 {
            for c in 0..<8 {
                var m: UInt64 = 0
                for ar in 0..<r {
                    if c > 0 { m |= (UInt64(1) &<< (ar * 8 + c - 1)) }
                    if c < 7 { m |= (UInt64(1) &<< (ar * 8 + c + 1)) }
                }
                masks[r * 8 + c] = m
            }
        }
        return masks
    }()

    private static let blackOutpostMasks: [UInt64] = {
        var masks = Array(repeating: UInt64(0), count: 64)
        for r in 0..<8 {
            for c in 0..<8 {
                var m: UInt64 = 0
                for ar in (r + 1)..<8 {
                    if c > 0 { m |= (UInt64(1) &<< (ar * 8 + c - 1)) }
                    if c < 7 { m |= (UInt64(1) &<< (ar * 8 + c + 1)) }
                }
                masks[r * 8 + c] = m
            }
        }
        return masks
    }()

    private static let whiteOutpostSupportMasks: [UInt64] = {
        var masks = Array(repeating: UInt64(0), count: 64)
        for r in 0..<7 {
            for c in 0..<8 {
                var m: UInt64 = 0
                if c > 0 { m |= (UInt64(1) &<< ((r + 1) * 8 + c - 1)) }
                if c < 7 { m |= (UInt64(1) &<< ((r + 1) * 8 + c + 1)) }
                masks[r * 8 + c] = m
            }
        }
        return masks
    }()

    private static let blackOutpostSupportMasks: [UInt64] = {
        var masks = Array(repeating: UInt64(0), count: 64)
        for r in 1..<8 {
            for c in 0..<8 {
                var m: UInt64 = 0
                if c > 0 { m |= (UInt64(1) &<< ((r - 1) * 8 + c - 1)) }
                if c < 7 { m |= (UInt64(1) &<< ((r - 1) * 8 + c + 1)) }
                masks[r * 8 + c] = m
            }
        }
        return masks
    }()

    private static func leastValuableAttacker(
        in grid: [[ChessPiece?]],
        toRow: Int,
        toCol: Int,
        by color: PieceColor
    ) -> (row: Int, col: Int, type: PieceType)? {
        // 1. Pawn
        let pawnRow = toRow + (color == .white ? 1 : -1)
        if pawnRow >= 0 && pawnRow < 8 {
            if toCol - 1 >= 0, let p = grid[pawnRow][toCol - 1], p.color == color, p.type == .pawn {
                return (pawnRow, toCol - 1, .pawn)
            }
            if toCol + 1 < 8, let p = grid[pawnRow][toCol + 1], p.color == color, p.type == .pawn {
                return (pawnRow, toCol + 1, .pawn)
            }
        }

        // 2. Knight
        let knightOffsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
        for (dr, dc) in knightOffsets {
            let nr = toRow + dr
            let nc = toCol + dc
            if nr >= 0 && nr < 8 && nc >= 0 && nc < 8,
               let p = grid[nr][nc], p.color == color, p.type == .knight {
                return (nr, nc, .knight)
            }
        }

        var queenCandidate: (row: Int, col: Int, type: PieceType)? = nil

        // 3. Bishop (or Queen on diagonal)
        let diagDirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for (dr, dc) in diagDirs {
            var nr = toRow + dr
            var nc = toCol + dc
            while nr >= 0 && nr < 8 && nc >= 0 && nc < 8 {
                if let p = grid[nr][nc] {
                    if p.color == color {
                        if p.type == .bishop {
                            return (nr, nc, .bishop)
                        } else if p.type == .queen && queenCandidate == nil {
                            queenCandidate = (nr, nc, .queen)
                        }
                    }
                    break
                }
                nr += dr
                nc += dc
            }
        }

        // 4. Rook (or Queen on orthogonal)
        let orthoDirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (dr, dc) in orthoDirs {
            var nr = toRow + dr
            var nc = toCol + dc
            while nr >= 0 && nr < 8 && nc >= 0 && nc < 8 {
                if let p = grid[nr][nc] {
                    if p.color == color {
                        if p.type == .rook {
                            return (nr, nc, .rook)
                        } else if p.type == .queen && queenCandidate == nil {
                            queenCandidate = (nr, nc, .queen)
                        }
                    }
                    break
                }
                nr += dr
                nc += dc
            }
        }

        // 5. Queen
        if let q = queenCandidate {
            return q
        }

        // 6. King
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let nr = toRow + dr
                let nc = toCol + dc
                if nr >= 0 && nr < 8 && nc >= 0 && nc < 8,
                   let p = grid[nr][nc], p.color == color, p.type == .king {
                    return (nr, nc, .king)
                }
            }
        }

        return nil
    }

    private static func seeCaptureScore(board: ChessBoardState, move: ChessMove) -> Int {
        guard let initialCaptured = move.capturedPiece else {
            if let promo = move.promotion {
                return pieceBaseValue(promo) - 100
            }
            return 0
        }

        var grid = board.squares
        if move.isEnPassant {
            grid[move.from.row][move.to.col] = nil
        }

        guard let mover = grid[move.from.row][move.from.col] else { return 0 }
        let placedType = move.promotion ?? mover.type

        var gain: [Int] = []
        gain.reserveCapacity(12)
        var firstGain = pieceBaseValue(initialCaptured.type)
        if move.promotion != nil {
            firstGain += pieceBaseValue(placedType) - 100
        }
        gain.append(firstGain)

        grid[move.from.row][move.from.col] = nil
        grid[move.to.row][move.to.col] = ChessPiece(color: mover.color, type: placedType)

        var side = board.sideToMove.opposite
        var currentTargetType = placedType

        while gain.count < 24 {
            guard let atk = leastValuableAttacker(in: grid, toRow: move.to.row, toCol: move.to.col, by: side) else {
                break
            }
            let nextGain = pieceBaseValue(currentTargetType) - gain[gain.count - 1]
            gain.append(nextGain)
            grid[atk.row][atk.col] = nil
            currentTargetType = atk.type
            side = side.opposite
        }

        var idx = gain.count - 1
        while idx > 0 {
            gain[idx - 1] = -max(-gain[idx - 1], gain[idx])
            idx -= 1
        }
        return gain[0]
    }

    private static let rootOpeningBonuses: [String: Int] = [
        "e2e4": 12, "d2d4": 11, "f1b5": 9, "f1c4": 8,
        "g1f3": 6, "b1c3": 5, "c2c4": 6,
        "e7e5": 11, "d7d5": 10, "c7c5": 10, "g8f6": 6,
        "e7e6": 6, "c7c6": 5
    ]

    // PeSTO Piece-Square Tables (White orientation, index 0 = rank 8, index 63 = rank 1)
    private static let mgPawnPST: [Int] = [
          0,   0,   0,   0,   0,   0,  0,   0,
         98, 134,  61,  95,  68, 126, 34, -11,
         -6,   7,  26,  31,  65,  56, 25, -20,
        -14,  13,   6,  21,  23,  12, 17, -23,
        -27,  -2,  -5,  12,  17,   6, 10, -25,
        -26,  -4,  -4, -10,   3,   3, 33, -12,
        -35,  -1, -20, -23, -15,  24, 38, -22,
          0,   0,   0,   0,   0,   0,  0,   0
    ]

    private static let egPawnPST: [Int] = [
          0,   0,   0,   0,   0,   0,   0,   0,
        178, 173, 158, 134, 147, 132, 165, 187,
         94, 100,  85,  67,  56,  53,  82,  84,
         32,  24,  13,   5,  -2,   4,  17,  17,
         13,   9,  -3,  -7,  -7,  -8,   3,  -1,
          4,   7,  -6,   1,   0,  -5,  -1,  -8,
         13,   8,   8,  10,  13,   0,   2,  -7,
          0,   0,   0,   0,   0,   0,   0,   0
    ]

    private static let mgKnightPST: [Int] = [
        -167, -89, -34, -49,  61, -97, -15, -107,
         -73, -41,  72,  36,  23,  62,   7,  -17,
         -47,  60,  37,  65,  84, 129,  73,   44,
          -9,  17,  19,  53,  37,  69,  18,   22,
         -13,   4,  16,  13,  28,  19,  21,   -8,
         -23,  -9,  12,  10,  19,  17,  25,  -16,
         -29, -53, -12,  -3,  -1,  18, -14,  -19,
        -105, -21, -58, -33, -17, -28, -19,  -23
    ]

    private static let mgBishopPST: [Int] = [
        -29,   4, -82, -37, -25, -42,   7,  -8,
        -26,  16, -18, -13,  30,  59,  18, -47,
        -16,  37,  43,  40,  35,  50,  37,  -2,
         -4,   5,  19,  50,  37,  37,   7,  -2,
         -6,  13,  13,  26,  34,  12,  10,   4,
          0,  15,  15,  15,  14,  27,  18,  10,
          4,  15,  16,   0,   7,  21,  33,   1,
        -33,  -3, -14, -21, -13, -12, -39, -21
    ]

    private static let mgRookPST: [Int] = [
         32,  42,  32,  51, 63,  9,  31,  43,
         27,  32,  58,  62, 80, 67,  26,  44,
         -5,  19,  26,  36, 17, 45,  61,  16,
        -24, -11,   7,  26, 24, 35,  -8, -20,
        -36, -26, -12,  -1,  9, -7,   6, -23,
        -45, -25, -16, -17,  3,  0,  -5, -33,
        -44, -16, -20,  -9, -1, 11,  -6, -71,
        -19, -13,   1,  17, 16,  7, -37, -26
    ]

    private static let mgQueenPST: [Int] = [
        -28,   0,  29,  12,  59,  44,  43,  45,
        -24, -39,  -5,   1, -16,  57,  28,  54,
        -13, -17,   7,   8,  29,  56,  47,  57,
        -27, -27, -16, -16,  -1,  17,  -2,   1,
         -9, -26,  -9, -10,  -2,  -4,   3,  -3,
        -14,   2, -11,  -2,  -5,   2,  14,   5,
        -35,  -8,  11,   2,   8,  15,  -3,   1,
         -1, -18,  -9,  10, -15, -25, -31, -50
    ]

    private static let mgKingPST: [Int] = [
        -65,  23,  16, -15, -56, -34,   2,  13,
         29,  -1, -20,  -7,  -8,  -4, -38, -29,
         -9,  24,   2, -16, -20,   6,  22, -22,
        -17, -20, -12, -27, -30, -25, -14, -36,
        -49,  -1, -27, -39, -46, -44, -33, -51,
        -14, -14, -22, -46, -44, -30, -15, -27,
          1,   7,  -8, -64, -43, -16,   9,   8,
        -15,  36,  12, -54,   8, -28,  24,  14
    ]

    private static let egKingPST: [Int] = [
        -74, -35, -18, -18, -11,  15,   4, -17,
        -12,  17,  14,  17,  17,  38,  23,  11,
         10,  17,  23,  15,  20,  45,  44,  13,
         -8,  22,  24,  27,  26,  33,  26,   3,
        -18,  -4,  21,  24,  27,  23,   9, -11,
        -19,  -3,  11,  21,  23,  16,   7,  -9,
        -27, -11,   4,  13,  14,   4,  -5, -17,
        -53, -33, -21, -11, -28, -14, -24, -43
    ]

    private static let egKnightPST: [Int] = [
        -58, -38, -13, -28, -31, -27, -63, -99,
        -25,  -8, -25,  -2,  -9, -25, -24, -52,
        -24, -20,  10,   9,  -1,  -9, -19, -41,
        -17,   3,  22,  22,  22,  11,   8, -18,
        -18,  -6,  16,  25,  16,  17,   4, -18,
        -23,  -3,  -1,  15,  10,  -3, -20, -22,
        -42, -20, -10,  -5,  -2, -20, -23, -44,
        -29, -51, -23, -15, -22, -18, -50, -64
    ]

    private static let egBishopPST: [Int] = [
        -14, -21, -11,  -8,  -7,  -9, -17, -24,
         -8,  -4,   7, -12,  -3, -13,  -4, -14,
          2,  -8,   0,  -1,  -2,   6,   0,   4,
         -3,   9,  12,   9,  14,  10,   3,   2,
         -6,   3,  13,  19,   7,  10,  -3,  -9,
        -12,  -3,   8,  10,  13,   3,  -7, -15,
        -14, -18,  -7,  -1,   4,  -9, -15, -27,
        -23,  -9, -23,  -5,  -9, -16,  -5, -17
    ]

    private static let egRookPST: [Int] = [
         13,  10,  18,  15,  12,  12,   8,   5,
         11,  13,  13,  11,  -3,   3,   8,   3,
          7,   7,   7,   5,   4,  -3,  -5,  -3,
          4,   3,  13,   1,   2,   1,  -1,   2,
          3,   5,   8,   4,  -5,  -6,  -8, -11,
         -4,   0,  -5,  -1,  -7, -12,  -8, -16,
         -6,  -6,   0,   2,  -9,  -9, -11,  -3,
         -9,   2,   3,  -1,  -5, -13,   4, -20
    ]

    private static let egQueenPST: [Int] = [
         -9,  22,  22,  27,  27,  19,  10,  20,
        -17,  20,  32,  41,  58,  25,  30,   0,
        -20,   6,   9,  49,  47,  35,  19,   9,
          3,  22,  24,  45,  57,  40,  57,  36,
        -18,  28,  19,  47,  31,  34,  39,  23,
        -16, -27,  15,   6,   9,  17,  10,   5,
        -22, -23, -30, -16, -16, -23, -36, -32,
        -33, -28, -22, -43,  -5, -32, -20, -41
    ]

    private struct TTEntry {
        var key: UInt64 = 0
        var depth: Int8 = -1
        var score: Int32 = 0
        var flag: UInt8 = 0
        var generation: UInt8 = 0
        var bestPacked: UInt16 = 0
    }

    private final class PersistentTTStore: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [TTEntry] = Array(repeating: TTEntry(), count: 65_536)
        private var currentGen: UInt8 = 1

        func checkout() -> (entries: [TTEntry], generation: UInt8) {
            lock.lock()
            defer { lock.unlock() }
            currentGen = currentGen &+ 1
            if currentGen == 0 { currentGen = 1 }
            return (entries, currentGen)
        }

        func commit(_ updated: [TTEntry], generation: UInt8) {
            lock.lock()
            defer { lock.unlock() }
            for i in 0..<entries.count {
                let cand = updated[i]
                guard cand.generation == generation && cand.flag != 0 else { continue }
                let cur = entries[i]
                if cur.flag == 0 || cur.generation != generation || cand.depth >= cur.depth {
                    entries[i] = cand
                }
            }
        }
    }

    private static let sharedTT = PersistentTTStore()

    private final class SearchContext {
        var nodes: Int = 0
        let deadline: CFAbsoluteTime
        var cancelled: Bool = false
        var tt: [TTEntry]
        let generation: UInt8
        var killers0: [UInt16] = Array(repeating: 0, count: 64)
        var killers1: [UInt16] = Array(repeating: 0, count: 64)
        var counterMoves: [UInt16] = Array(repeating: 0, count: 4_096)
        var historyTable: [Int] = Array(repeating: 0, count: 8_192)

        init(deadline: CFAbsoluteTime, tt: [TTEntry], generation: UInt8) {
            self.deadline = deadline
            self.tt = tt
            self.generation = generation
        }

        @inline(__always)
        func checkTimeAndCancel() -> Bool {
            if cancelled { return true }
            if (nodes & 511) == 0 {
                if CFAbsoluteTimeGetCurrent() > deadline || Task.isCancelled {
                    cancelled = true
                    return true
                }
            }
            return false
        }

        @inline(__always)
        func recordKiller(_ packed: UInt16, ply: Int) {
            guard ply >= 0 && ply < 64 && packed != 0 else { return }
            if killers0[ply] != packed {
                killers1[ply] = killers0[ply]
                killers0[ply] = packed
            }
        }

        @inline(__always)
        func recordCounterMove(prevPacked: UInt16, movePacked: UInt16) {
            guard prevPacked != 0 && movePacked != 0 else { return }
            counterMoves[Int(prevPacked & 0x0FFF)] = movePacked
        }

        @inline(__always)
        func counterMove(for prevPacked: UInt16) -> UInt16 {
            guard prevPacked != 0 else { return 0 }
            return counterMoves[Int(prevPacked & 0x0FFF)]
        }

        @inline(__always)
        func historyIndex(color: PieceColor, packed: UInt16) -> Int {
            ((color == .white ? 0 : 1) << 12) | Int(packed & 0x0FFF)
        }

        @inline(__always)
        func recordHistory(color: PieceColor, packed: UInt16, depth: Int) {
            let idx = historyIndex(color: color, packed: packed)
            let bonus = depth * depth
            let updated = historyTable[idx] + bonus - (historyTable[idx] * bonus) / 16_384
            historyTable[idx] = min(16_384, max(-16_384, updated))
        }
    }

    private static func rootPositionalTieBreaker(for move: ChessMove, board: ChessBoardState) -> Int {
        var bonus = 0
        if board.fullMoveNumber <= 8, let openBonus = rootOpeningBonuses[move.uci] {
            bonus += openBonus
        }

        if let piece = board.squares[move.from.row][move.from.col] {
            if piece.type == .king && abs(move.to.col - move.from.col) == 2 {
                bonus += 6
            }
            let homeRow = piece.color == .white ? 7 : 0
            if (piece.type == .knight || piece.type == .bishop) && move.from.row == homeRow && move.to.row != homeRow {
                bonus += 3
            }
            if (3...4).contains(move.to.row) && (3...4).contains(move.to.col) {
                bonus += 3
            } else if (2...5).contains(move.to.row) && (2...5).contains(move.to.col) {
                bonus += 1
            }
            if piece.type == .pawn && board.fullMoveNumber <= 6 && (move.from.col == 0 || move.from.col == 7) {
                bonus -= 2
            }
        }
        return bonus
    }

    @inline(__always)
    private static func hasNonPawnMaterial(_ board: ChessBoardState, color: PieceColor) -> Bool {
        for r in 0..<8 {
            let row = board.squares[r]
            for c in 0..<8 {
                if let p = row[c], p.color == color,
                   p.type != .pawn && p.type != .king {
                    return true
                }
            }
        }
        return false
    }

    static func analyze(
        board: ChessBoardState,
        maxDepth: Int,
        multiPV: Int,
        timeBudgetSeconds: TimeInterval,
        isZeroNetworkMode: Bool = false,
        excludedUCIs: Set<String> = []
    ) -> EngineAnalysisResult {
        let searchStart = CFAbsoluteTimeGetCurrent()
        let allLegal = board.legalMoves()
        let filteredRoot = excludedUCIs.isEmpty
            ? allLegal
            : allLegal.filter { !excludedUCIs.contains($0.uci) }
        let rootMoves = filteredRoot.isEmpty ? allLegal : filteredRoot
        let fen = board.toFEN()
        guard !rootMoves.isEmpty else {
            return EngineAnalysisResult(
                fen: fen,
                sideToMove: board.sideToMove,
                lines: [],
                depthReached: 0,
                isCloudVerified: false,
                engineSource: "本地引擎 (PeSTO)",
                nodesSearched: 0,
                timestamp: Date(),
                searchTimeMs: 0
            )
        }

        // Immediate early return on forced single legal move (0ms latency)
        if rootMoves.count == 1 {
            let onlyMove = rootMoves[0]
            let nextBoard = board.applyingRaw(onlyMove)
            let nextLegal = nextBoard.legalMoves(includeFormattedSAN: false)
            let rawScore: Int
            if nextLegal.isEmpty {
                rawScore = nextBoard.isKingInCheck(nextBoard.sideToMove) ? (mateScore - 1) : 0
            } else {
                rawScore = -evaluate(board: nextBoard)
            }
            let whiteCP = board.sideToMove == .white ? rawScore : -rawScore
            var mateMoves: Int? = nil
            if abs(rawScore) > mateScore - 200 {
                mateMoves = board.sideToMove == .white ? 1 : -1
            }
            let singleLine = PVLine(
                multipvIndex: 1,
                bestMove: onlyMove,
                continuationSAN: [onlyMove.san],
                continuationUCI: [onlyMove.uci],
                scoreCentipawns: whiteCP,
                mateInMoves: mateMoves,
                depth: 1,
                sourceLabel: "唯一合法著",
                predictedOpponentReply: nil,
                tacticalReason: board.explainMoveTactics(onlyMove)
            )
            let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - searchStart) * 1000.0).rounded()))
            return EngineAnalysisResult(
                fen: fen,
                sideToMove: board.sideToMove,
                lines: [singleLine],
                depthReached: 1,
                isCloudVerified: false,
                engineSource: isZeroNetworkMode
                    ? "本機零連網安全引擎 (強制著)"
                    : "本地離線引擎 (強制著)",
                nodesSearched: 1,
                timestamp: Date(),
                searchTimeMs: elapsedMs
            )
        }

        let clampedMaxDepth = min(max(1, maxDepth), 12)
        let checkedOut = sharedTT.checkout()
        let ctx = SearchContext(
            deadline: CFAbsoluteTimeGetCurrent() + timeBudgetSeconds,
            tt: checkedOut.entries,
            generation: checkedOut.generation
        )
        defer {
            sharedTT.commit(ctx.tt, generation: ctx.generation)
        }

        var bestScoredMoves: [(move: ChessMove, scoreFromSideToMove: Int, pv: [ChessMove])] = []
        var completedDepth = 1

        let rootZKey = OfflineEnginePack.shared.computeZobristHash(for: board)
        let rootTT = ctx.tt[Int(rootZKey & 65_535)]
        let rootHintPacked: UInt16 = (rootTT.key == rootZKey && rootTT.flag != 0) ? rootTT.bestPacked : 0
        let orderedInitial = orderMoves(rootMoves, board: board, ttPacked: rootHintPacked, prevPacked: 0, ply: 0, ctx: ctx)
        let targetPVCount = max(1, min(multiPV, orderedInitial.count))

        // Iterative deepening over root moves with Multi-PV Root Window Pruning
        for depth in 1...clampedMaxDepth {
            if (CFAbsoluteTimeGetCurrent() > ctx.deadline || Task.isCancelled) && depth > 1 {
                break
            }
            var currentResults: [(move: ChessMove, scoreFromSideToMove: Int, pv: [ChessMove])] = []
            currentResults.reserveCapacity(rootMoves.count)
            let candidates = bestScoredMoves.isEmpty ? orderedInitial : bestScoredMoves.map(\.move)
            var topScores: [Int] = []
            topScores.reserveCapacity(targetPVCount + 1)

            for (rootIdx, move) in candidates.enumerated() {
                if (CFAbsoluteTimeGetCurrent() > ctx.deadline || Task.isCancelled) && !bestScoredMoves.isEmpty {
                    ctx.cancelled = true
                    break
                }
                let nextBoard = board.applyingRaw(move)
                var childPV: [ChessMove] = []

                // Once we already have `targetPVCount` candidates at depth >= 3, prune root moves strictly worse than the kth cutoff
                var rootAlpha = -mateScore
                if depth >= 3 && rootIdx >= targetPVCount && topScores.count >= targetPVCount {
                    let kthCutoff = topScores[targetPVCount - 1] - 25
                    if abs(kthCutoff) < mateScore - 600 {
                        rootAlpha = kthCutoff
                    }
                }

                let score = -negamax(
                    board: nextBoard,
                    depth: depth - 1,
                    ply: 1,
                    alpha: -mateScore,
                    beta: -rootAlpha,
                    allowNullMove: true,
                    prevPacked: move.packed,
                    ctx: ctx,
                    pvOut: &childPV
                )
                if ctx.cancelled { break }
                let tieBreaker = abs(score) < mateScore - 200
                    ? rootPositionalTieBreaker(for: move, board: board)
                    : 0
                let finalRootScore = score + tieBreaker
                currentResults.append((move, finalRootScore, [move] + childPV))
                if topScores.count < targetPVCount {
                    topScores.append(finalRootScore)
                    topScores.sort(by: >)
                } else if finalRootScore > topScores[targetPVCount - 1] {
                    topScores[targetPVCount - 1] = finalRootScore
                    topScores.sort(by: >)
                }
            }

            if !ctx.cancelled && !currentResults.isEmpty {
                currentResults.sort { $0.scoreFromSideToMove > $1.scoreFromSideToMove }
                bestScoredMoves = currentResults
                completedDepth = depth

                if let topRoot = currentResults.first, abs(topRoot.scoreFromSideToMove) < mateScore - 500 {
                    ctx.tt[Int(rootZKey & 65_535)] = TTEntry(
                        key: rootZKey,
                        depth: Int8(min(depth, 127)),
                        score: Int32(topRoot.scoreFromSideToMove),
                        flag: 1,
                        generation: ctx.generation,
                        bestPacked: topRoot.move.packed
                    )
                }
            } else {
                break
            }
        }

        if bestScoredMoves.isEmpty {
            bestScoredMoves = orderedInitial.map { ($0, rootPositionalTieBreaker(for: $0, board: board), [$0]) }
        }

        let pvCount = min(multiPV, bestScoredMoves.count)
        var pvLines: [PVLine] = []
        pvLines.reserveCapacity(pvCount)

        for idx in 0..<pvCount {
            let entry = bestScoredMoves[idx]
            let rawScore = entry.scoreFromSideToMove
            let whiteCP = board.sideToMove == .white ? rawScore : -rawScore

            var mateMoves: Int? = nil
            if abs(rawScore) > mateScore - 200 {
                let plyToMate = mateScore - abs(rawScore)
                let fullMoves = max(1, (plyToMate + 1) / 2)
                if rawScore > 0 {
                    mateMoves = board.sideToMove == .white ? fullMoves : -fullMoves
                } else {
                    mateMoves = board.sideToMove == .white ? -fullMoves : fullMoves
                }
            }

            let uciLine = entry.pv.map(\.uci)
            let sanLine = ChessEngineService.convertUCILineToSAN(startBoard: board, uciMoves: uciLine)

            pvLines.append(PVLine(
                multipvIndex: idx + 1,
                bestMove: entry.move,
                continuationSAN: sanLine,
                continuationUCI: uciLine,
                scoreCentipawns: whiteCP,
                mateInMoves: mateMoves,
                depth: completedDepth,
                sourceLabel: "本地 D\(completedDepth)",
                predictedOpponentReply: ChessEngineService.extractOpponentReply(
                    on: board,
                    firstMove: entry.move,
                    continuationUCI: uciLine
                ),
                tacticalReason: board.explainMoveTactics(entry.move)
            ))
        }

        let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - searchStart) * 1000.0).rounded()))
        return EngineAnalysisResult(
            fen: fen,
            sideToMove: board.sideToMove,
            lines: pvLines,
            depthReached: completedDepth,
            isCloudVerified: false,
            engineSource: isZeroNetworkMode
                ? "本機零連網安全引擎 (D\(completedDepth))"
                : "本地離線引擎 (D\(completedDepth))",
            nodesSearched: ctx.nodes,
            timestamp: Date(),
            searchTimeMs: elapsedMs
        )
    }

    private static func negamax(
        board: ChessBoardState,
        depth: Int,
        ply: Int,
        alpha: Int,
        beta: Int,
        allowNullMove: Bool,
        prevPacked: UInt16,
        ctx: SearchContext,
        pvOut: inout [ChessMove]
    ) -> Int {
        if ctx.checkTimeAndCancel() {
            return 0
        }

        let inCheck = board.isKingInCheck(board.sideToMove)
        let effectiveDepth = (inCheck && ply < 24) ? (depth + 1) : depth

        if effectiveDepth <= 0 {
            return quiescence(board: board, alpha: alpha, beta: beta, ply: ply, ctx: ctx)
        }

        ctx.nodes += 1

        let pvNode = (beta - alpha) > 1
        let zKey = OfflineEnginePack.shared.computeZobristHash(for: board)
        let ttIdx = Int(zKey & 65_535)
        let ttEntry = ctx.tt[ttIdx]
        var curAlpha = alpha
        var curBeta = beta
        var ttPacked: UInt16 = 0

        if ttEntry.key == zKey && ttEntry.flag != 0 {
            ttPacked = ttEntry.bestPacked
            if !pvNode && Int(ttEntry.depth) >= effectiveDepth && abs(Int(ttEntry.score)) < mateScore - 500 {
                let ttScore = Int(ttEntry.score)
                if ttEntry.flag == 1 {
                    return ttScore
                } else if ttEntry.flag == 2 {
                    if ttScore >= curBeta { return ttScore }
                    curAlpha = max(curAlpha, ttScore)
                } else if ttEntry.flag == 3 {
                    if ttScore <= curAlpha { return ttScore }
                    curBeta = min(curBeta, ttScore)
                }
                if curAlpha >= curBeta {
                    return curAlpha
                }
            }
        }

        // Static pruning (Reverse Futility Pruning, Null-Move Pruning, and Forward Futility Pruning prep)
        var cachedStaticEval: Int? = nil
        if !inCheck && !pvNode && abs(curBeta) < mateScore - 500 && hasNonPawnMaterial(board, color: board.sideToMove) {
            let staticEval = evaluate(board: board)
            cachedStaticEval = staticEval

            if effectiveDepth <= 3 && staticEval - 85 * effectiveDepth >= curBeta {
                return curBeta
            }

            if allowNullMove && effectiveDepth >= 3 && staticEval >= curBeta {
                var nullBoard = board
                nullBoard.sideToMove = board.sideToMove == .white ? .black : .white
                nullBoard.enPassantTarget = nil
                nullBoard.halfMoveClock += 1
                if board.sideToMove == .black {
                    nullBoard.fullMoveNumber += 1
                }
                let reduction = effectiveDepth >= 6 ? 3 : 2
                var nullPV: [ChessMove] = []
                let nullScore = -negamax(
                    board: nullBoard,
                    depth: max(0, effectiveDepth - 1 - reduction),
                    ply: ply + 1,
                    alpha: -curBeta,
                    beta: -curBeta + 1,
                    allowNullMove: false,
                    prevPacked: 0,
                    ctx: ctx,
                    pvOut: &nullPV
                )
                if ctx.cancelled { return 0 }
                if nullScore >= curBeta {
                    return curBeta
                }
            }
        }

        let legal = board.legalMoves(includeFormattedSAN: false)

        if legal.isEmpty {
            return inCheck ? (-mateScore + ply) : 0
        }

        let ordered = orderMoves(legal, board: board, ttPacked: ttPacked, prevPacked: prevPacked, ply: ply, ctx: ctx)
        let origAlpha = curAlpha
        var bestAlpha = curAlpha
        var bestPV: [ChessMove] = []
        var bestPacked: UInt16 = ordered[0].packed
        let newDepth = effectiveDepth - 1

        let futilityMargin = effectiveDepth == 1 ? 190 : 360
        let canFutilityBase = (cachedStaticEval != nil && effectiveDepth <= 2 && abs(bestAlpha) < mateScore - 500)

        for (moveIdx, move) in ordered.enumerated() {
            let isQuiet = (move.capturedPiece == nil && move.promotion == nil)
            let next = board.applyingRaw(move)

            if canFutilityBase && moveIdx >= 2 && isQuiet,
               let staticEval = cachedStaticEval,
               staticEval + futilityMargin <= bestAlpha,
               !next.isKingInCheck(next.sideToMove) {
                continue
            }
            var childPV: [ChessMove] = []
            var score: Int

            if moveIdx == 0 {
                score = -negamax(
                    board: next,
                    depth: newDepth,
                    ply: ply + 1,
                    alpha: -curBeta,
                    beta: -bestAlpha,
                    allowNullMove: true,
                    prevPacked: move.packed,
                    ctx: ctx,
                    pvOut: &childPV
                )
            } else {
                var reduction = 0
                if effectiveDepth >= 3 && moveIdx >= 3 && isQuiet && !inCheck && move.packed != ttPacked {
                    let isKiller = (ply < 64) && (move.packed == ctx.killers0[ply] || move.packed == ctx.killers1[ply])
                    if !isKiller && !next.isKingInCheck(next.sideToMove) {
                        reduction = (moveIdx >= 7 && effectiveDepth >= 5) ? 2 : 1
                    }
                }

                let reducedDepth = max(0, newDepth - reduction)
                score = -negamax(
                    board: next,
                    depth: reducedDepth,
                    ply: ply + 1,
                    alpha: -(bestAlpha + 1),
                    beta: -bestAlpha,
                    allowNullMove: true,
                    prevPacked: move.packed,
                    ctx: ctx,
                    pvOut: &childPV
                )

                if !ctx.cancelled && reduction > 0 && score > bestAlpha {
                    childPV.removeAll(keepingCapacity: true)
                    score = -negamax(
                        board: next,
                        depth: newDepth,
                        ply: ply + 1,
                        alpha: -(bestAlpha + 1),
                        beta: -bestAlpha,
                        allowNullMove: true,
                        prevPacked: move.packed,
                        ctx: ctx,
                        pvOut: &childPV
                    )
                }

                if !ctx.cancelled && score > bestAlpha && score < curBeta {
                    childPV.removeAll(keepingCapacity: true)
                    score = -negamax(
                        board: next,
                        depth: newDepth,
                        ply: ply + 1,
                        alpha: -curBeta,
                        beta: -bestAlpha,
                        allowNullMove: true,
                        prevPacked: move.packed,
                        ctx: ctx,
                        pvOut: &childPV
                    )
                }
            }

            if ctx.cancelled { return 0 }

            if score >= curBeta {
                if isQuiet {
                    ctx.recordKiller(move.packed, ply: ply)
                    ctx.recordCounterMove(prevPacked: prevPacked, movePacked: move.packed)
                    ctx.recordHistory(color: board.sideToMove, packed: move.packed, depth: effectiveDepth)
                }
                if abs(curBeta) < mateScore - 500 {
                    ctx.tt[ttIdx] = TTEntry(
                        key: zKey,
                        depth: Int8(min(effectiveDepth, 127)),
                        score: Int32(curBeta),
                        flag: 2,
                        generation: ctx.generation,
                        bestPacked: move.packed
                    )
                }
                return curBeta
            }
            if score > bestAlpha {
                bestAlpha = score
                bestPV = [move] + childPV
                bestPacked = move.packed
            }
        }

        if abs(bestAlpha) < mateScore - 500 {
            let flag: UInt8 = bestAlpha > origAlpha ? 1 : 3
            ctx.tt[ttIdx] = TTEntry(
                key: zKey,
                depth: Int8(min(effectiveDepth, 127)),
                score: Int32(bestAlpha),
                flag: flag,
                generation: ctx.generation,
                bestPacked: bestPacked
            )
        }

        pvOut = bestPV
        return bestAlpha
    }

    private static func quiescence(
        board: ChessBoardState,
        alpha: Int,
        beta: Int,
        ply: Int,
        ctx: SearchContext
    ) -> Int {
        if ctx.checkTimeAndCancel() {
            return 0
        }
        ctx.nodes += 1

        let inCheck = board.isKingInCheck(board.sideToMove)
        var bestAlpha = alpha
        var standPat = -mateScore

        if !inCheck {
            standPat = evaluate(board: board)
            if standPat >= beta {
                return beta
            }
            if standPat > bestAlpha {
                bestAlpha = standPat
            }
            if ply >= 12 {
                return bestAlpha
            }
        } else if ply >= 16 {
            return evaluate(board: board)
        }

        let candidates = inCheck
            ? board.legalMoves(includeFormattedSAN: false)
            : board.legalTacticalMoves()

        if candidates.isEmpty {
            return inCheck ? (-mateScore + ply) : bestAlpha
        }

        let ordered = orderMoves(candidates, board: board, ttPacked: 0, prevPacked: 0, ply: ply, ctx: ctx)

        for move in ordered {
            let precomputedNext: ChessBoardState?
            if !inCheck {
                let capGain = move.capturedPiece.map { pieceBaseValue($0.type) } ?? 0
                let promoGain = move.promotion.map { pieceBaseValue($0) } ?? 0
                if standPat + capGain + promoGain + 180 <= bestAlpha {
                    continue
                }
                if move.promotion == nil && move.capturedPiece != nil {
                    let see = seeCaptureScore(board: board, move: move)
                    if see < 0 {
                        let candidateNext = board.applyingRaw(move)
                        if !candidateNext.isKingInCheck(candidateNext.sideToMove) {
                            continue
                        }
                        precomputedNext = candidateNext
                    } else {
                        precomputedNext = nil
                    }
                } else {
                    precomputedNext = nil
                }
            } else {
                precomputedNext = nil
            }

            let next = precomputedNext ?? board.applyingRaw(move)
            let score = -quiescence(board: next, alpha: -beta, beta: -bestAlpha, ply: ply + 1, ctx: ctx)
            if ctx.cancelled { return 0 }
            if score >= beta {
                return beta
            }
            if score > bestAlpha {
                bestAlpha = score
            }
        }
        return bestAlpha
    }

    private static func orderMoves(
        _ moves: [ChessMove],
        board: ChessBoardState,
        ttPacked: UInt16,
        prevPacked: UInt16 = 0,
        ply: Int,
        ctx: SearchContext?
    ) -> [ChessMove] {
        let count = moves.count
        guard count > 1 else { return moves }

        let k0: UInt16 = (ply >= 0 && ply < 64) ? (ctx?.killers0[ply] ?? 0) : 0
        let k1: UInt16 = (ply >= 0 && ply < 64) ? (ctx?.killers1[ply] ?? 0) : 0
        let cm: UInt16 = (prevPacked != 0) ? (ctx?.counterMove(for: prevPacked) ?? 0) : 0
        let stm = board.sideToMove

        var scored: [(score: Int, idx: Int)] = []
        scored.reserveCapacity(count)

        for idx in 0..<count {
            let move = moves[idx]
            let pk = move.packed
            var s: Int

            if ttPacked != 0 && pk == ttPacked {
                s = 2_000_000
            } else if let captured = move.capturedPiece {
                let attackerValue = pieceBaseValue(board.squares[move.from.row][move.from.col]?.type ?? .pawn)
                let see = seeCaptureScore(board: board, move: move)
                if see >= 0 || move.promotion != nil {
                    s = 1_000_000 + see + pieceBaseValue(captured.type) * 8 - (attackerValue / 4)
                    if let promo = move.promotion {
                        s += 50_000 + pieceBaseValue(promo)
                    }
                } else {
                    s = -100_000 + see
                }
            } else if let promo = move.promotion {
                s = 900_000 + pieceBaseValue(promo)
            } else if k0 != 0 && pk == k0 {
                s = 800_000
            } else if k1 != 0 && pk == k1 {
                s = 750_000
            } else if cm != 0 && pk == cm {
                s = 720_000
            } else {
                s = ctx.map { $0.historyTable[$0.historyIndex(color: stm, packed: pk)] } ?? 0
                if move.isCastling {
                    s += 6_000
                }
                let dist2 = abs(move.to.row * 2 - 7) + abs(move.to.col * 2 - 7)
                s += (14 - dist2) * 20
            }

            scored.append((s, idx))
        }

        scored.sort { $0.score > $1.score }
        var ordered: [ChessMove] = []
        ordered.reserveCapacity(count)
        for item in scored {
            ordered.append(moves[item.idx])
        }
        return ordered
    }

    /// PeSTO Tapered Evaluation + Bitboard Pawn Structure / Outposts / Rook Files / Mop-Up + Micro-NNUE
    fileprivate static func evaluate(board: ChessBoardState) -> Int {
        var mgWhite = 0, mgBlack = 0
        var egWhite = 0, egBlack = 0
        var phase = 0
        var whiteBishops = 0, blackBishops = 0
        var whiteKingRow = -1, whiteKingCol = -1
        var blackKingRow = -1, blackKingCol = -1
        var whitePawnsBB: UInt64 = 0
        var blackPawnsBB: UInt64 = 0
        var whiteKnightsBB: UInt64 = 0
        var blackKnightsBB: UInt64 = 0
        var whiteRooksBB: UInt64 = 0
        var blackRooksBB: UInt64 = 0

        for r in 0..<8 {
            let row = board.squares[r]
            for c in 0..<8 {
                guard let p = row[c] else { continue }
                phase += piecePhaseWeight(p.type)
                let sqIdx = p.color == .white ? (r * 8 + c) : ((7 - r) * 8 + c)
                let bit = UInt64(1) &<< (r * 8 + c)

                let mgMat = mgPieceValue(p.type)
                let egMat = egPieceValue(p.type)
                let mgPST: Int
                let egPST: Int

                switch p.type {
                case .pawn:
                    mgPST = mgPawnPST[sqIdx]
                    egPST = egPawnPST[sqIdx]
                    if p.color == .white {
                        whitePawnsBB |= bit
                    } else {
                        blackPawnsBB |= bit
                    }
                case .knight:
                    mgPST = mgKnightPST[sqIdx]
                    egPST = egKnightPST[sqIdx]
                    if p.color == .white {
                        whiteKnightsBB |= bit
                    } else {
                        blackKnightsBB |= bit
                    }
                case .bishop:
                    mgPST = mgBishopPST[sqIdx]
                    egPST = egBishopPST[sqIdx]
                    if p.color == .white { whiteBishops += 1 } else { blackBishops += 1 }
                case .rook:
                    mgPST = mgRookPST[sqIdx]
                    egPST = egRookPST[sqIdx]
                    if p.color == .white {
                        whiteRooksBB |= bit
                    } else {
                        blackRooksBB |= bit
                    }
                case .queen:
                    mgPST = mgQueenPST[sqIdx]
                    egPST = egQueenPST[sqIdx]
                case .king:
                    mgPST = mgKingPST[sqIdx]
                    egPST = egKingPST[sqIdx]
                    if p.color == .white {
                        whiteKingRow = r
                        whiteKingCol = c
                    } else {
                        blackKingRow = r
                        blackKingCol = c
                    }
                }

                let microAdj = OfflineEnginePack.shared.nnueTableAdjustment(piece: p, row: r, col: c, phase: phase)
                if p.color == .white {
                    mgWhite += mgMat + mgPST + microAdj
                    egWhite += egMat + egPST + microAdj
                } else {
                    mgBlack += mgMat + mgPST + microAdj
                    egBlack += egMat + egPST + microAdj
                }
            }
        }

        // O(1) Bitwise Passed Pawn evaluation
        var wp = whitePawnsBB
        while wp != 0 {
            let sq = wp.trailingZeroBitCount
            wp &= wp &- 1
            let r = sq >> 3
            if r >= 1 && r <= 6 && (blackPawnsBB & whitePassedMasks[sq]) == 0 {
                let bonus = passedPawnBonus[r]
                mgWhite += bonus >> 1
                egWhite += bonus
            }
        }

        var bp = blackPawnsBB
        while bp != 0 {
            let sq = bp.trailingZeroBitCount
            bp &= bp &- 1
            let r = sq >> 3
            if r >= 1 && r <= 6 && (whitePawnsBB & blackPassedMasks[sq]) == 0 {
                let bonus = passedPawnBonus[7 - r]
                mgBlack += bonus >> 1
                egBlack += bonus
            }
        }

        // Doubled & Isolated Pawns
        for c in 0..<8 {
            let fMask = fileMasks[c]
            let adjMask = adjacentFileMasks[c]
            let wpCount = (whitePawnsBB & fMask).nonzeroBitCount
            if wpCount >= 2 {
                let dbl = wpCount - 1
                mgWhite -= 12 * dbl
                egWhite -= 18 * dbl
            }
            if wpCount > 0 && (whitePawnsBB & adjMask) == 0 {
                mgWhite -= 14 * wpCount
                egWhite -= 16 * wpCount
            }

            let bpCount = (blackPawnsBB & fMask).nonzeroBitCount
            if bpCount >= 2 {
                let dbl = bpCount - 1
                mgBlack -= 12 * dbl
                egBlack -= 18 * dbl
            }
            if bpCount > 0 && (blackPawnsBB & adjMask) == 0 {
                mgBlack -= 14 * bpCount
                egBlack -= 16 * bpCount
            }
        }

        // Rook Open / Semi-Open File, Doubled Rooks & 7th Rank
        var wr = whiteRooksBB
        while wr != 0 {
            let sq = wr.trailingZeroBitCount
            wr &= wr &- 1
            let r = sq >> 3
            let c = sq & 7
            if r == 1 {
                mgWhite += 22
                egWhite += 32
            }
            let sameFileCount = (whiteRooksBB & fileMasks[c]).nonzeroBitCount
            if sameFileCount >= 2 {
                mgWhite += 10
                egWhite += 8
            }
            if (whitePawnsBB & fileMasks[c]) == 0 {
                if (blackPawnsBB & fileMasks[c]) == 0 {
                    mgWhite += 24
                    egWhite += 18
                } else {
                    mgWhite += 12
                    egWhite += 8
                }
            }
        }

        var br = blackRooksBB
        while br != 0 {
            let sq = br.trailingZeroBitCount
            br &= br &- 1
            let r = sq >> 3
            let c = sq & 7
            if r == 6 {
                mgBlack += 22
                egBlack += 32
            }
            let sameFileCount = (blackRooksBB & fileMasks[c]).nonzeroBitCount
            if sameFileCount >= 2 {
                mgBlack += 10
                egBlack += 8
            }
            if (blackPawnsBB & fileMasks[c]) == 0 {
                if (whitePawnsBB & fileMasks[c]) == 0 {
                    mgBlack += 24
                    egBlack += 18
                } else {
                    mgBlack += 12
                    egBlack += 8
                }
            }
        }

        // Protected Knight Outposts
        var wn = whiteKnightsBB
        while wn != 0 {
            let sq = wn.trailingZeroBitCount
            wn &= wn &- 1
            let r = sq >> 3
            let c = sq & 7
            if r >= 2 && r <= 4 && c >= 1 && c <= 6 &&
               (blackPawnsBB & whiteOutpostMasks[sq]) == 0 &&
               (whitePawnsBB & whiteOutpostSupportMasks[sq]) != 0 {
                mgWhite += 26
                egWhite += 16
            }
        }

        var bn = blackKnightsBB
        while bn != 0 {
            let sq = bn.trailingZeroBitCount
            bn &= bn &- 1
            let r = sq >> 3
            let c = sq & 7
            if r >= 3 && r <= 5 && c >= 1 && c <= 6 &&
               (whitePawnsBB & blackOutpostMasks[sq]) == 0 &&
               (blackPawnsBB & blackOutpostSupportMasks[sq]) != 0 {
                mgBlack += 26
                egBlack += 16
            }
        }

        // Castled king pawn shield bonus (middlegame)
        if whiteKingRow == 7 && (whiteKingCol >= 5 || whiteKingCol <= 2) {
            for fc in max(0, whiteKingCol - 1)...min(7, whiteKingCol + 1) {
                if (whitePawnsBB & whiteShieldFileMasks[fc]) != 0 {
                    mgWhite += 14
                }
            }
        }
        if blackKingRow == 0 && (blackKingCol >= 5 || blackKingCol <= 2) {
            for fc in max(0, blackKingCol - 1)...min(7, blackKingCol + 1) {
                if (blackPawnsBB & blackShieldFileMasks[fc]) != 0 {
                    mgBlack += 14
                }
            }
        }

        if whiteBishops >= 2 { mgWhite += 30; egWhite += 45 }
        if blackBishops >= 2 { mgBlack += 30; egBlack += 45 }

        // Master Principle: Central Pawn Control & King Ring Attack Safety
        let centerSquares: [(Int, Int)] = [(3, 3), (3, 4), (4, 3), (4, 4)]
        for (cr, cc) in centerSquares {
            if let cpPiece = board.squares[cr][cc], cpPiece.type == .pawn {
                if cpPiece.color == .white { mgWhite += 18 } else { mgBlack += 18 }
            }
        }
        let clampedPhase = min(24, phase)
        if clampedPhase >= 8 {
            if whiteKingRow >= 0 && board.squares[whiteKingRow][whiteKingCol]?.type == .king {
                var dangerToWhite = 0
                if (blackRooksBB & fileMasks[whiteKingCol]) != 0 && (whitePawnsBB & fileMasks[whiteKingCol]) == 0 {
                    dangerToWhite += 20
                }
                if whiteKingRow == 7 && (whiteKingCol >= 5 || whiteKingCol <= 2) {
                    var bnCheck = blackKnightsBB
                    while bnCheck != 0 {
                        let sq = bnCheck.trailingZeroBitCount
                        bnCheck &= bnCheck &- 1
                        if abs((sq >> 3) - whiteKingRow) <= 3 && abs((sq & 7) - whiteKingCol) <= 3 {
                            dangerToWhite += 14
                        }
                    }
                }
                mgWhite -= dangerToWhite
            }
            if blackKingRow >= 0 && board.squares[blackKingRow][blackKingCol]?.type == .king {
                var dangerToBlack = 0
                if (whiteRooksBB & fileMasks[blackKingCol]) != 0 && (blackPawnsBB & fileMasks[blackKingCol]) == 0 {
                    dangerToBlack += 20
                }
                if blackKingRow == 0 && (blackKingCol >= 5 || blackKingCol <= 2) {
                    var wnCheck = whiteKnightsBB
                    while wnCheck != 0 {
                        let sq = wnCheck.trailingZeroBitCount
                        wnCheck &= wnCheck &- 1
                        if abs((sq >> 3) - blackKingRow) <= 3 && abs((sq & 7) - blackKingCol) <= 3 {
                            dangerToBlack += 14
                        }
                    }
                }
                mgBlack -= dangerToBlack
            }
        }
        if clampedPhase <= 4 && whiteKingRow >= 0 && blackKingRow >= 0 {
            let rawEgDiff = egWhite - egBlack
            let kingDist = abs(whiteKingRow - blackKingRow) + abs(whiteKingCol - blackKingCol)
            if rawEgDiff >= 180 {
                let edgePush = abs(blackKingRow * 2 - 7) + abs(blackKingCol * 2 - 7)
                egWhite += edgePush * 8 + (14 - kingDist) * 5
            } else if rawEgDiff <= -180 {
                let edgePush = abs(whiteKingRow * 2 - 7) + abs(whiteKingCol * 2 - 7)
                egBlack += edgePush * 8 + (14 - kingDist) * 5
            }
        }

        let mgDiff = mgWhite - mgBlack
        let egDiff = egWhite - egBlack
        let taperedWhite = (mgDiff * clampedPhase + egDiff * (24 - clampedPhase)) / 24

        return (board.sideToMove == .white ? taperedWhite : -taperedWhite) + 10
    }
}
