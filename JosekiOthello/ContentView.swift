import SwiftUI

// MARK: - Colors

extension Color {
    static let boardGreen = Color(red: 0.1, green: 0.42, blue: 0.22)
    static let boardLine = Color(red: 0.06, green: 0.31, blue: 0.15)
    static let darkBg = Color(red: 0.05, green: 0.07, blue: 0.09)
    static let cardBg = Color(red: 0.09, green: 0.11, blue: 0.13)
    static let accentGreen = Color(red: 0.25, green: 0.73, blue: 0.31)
    static let lastMoveHighlight = Color(red: 0.94, green: 0.53, blue: 0.24)
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var game = OthelloGame()
    @StateObject private var camera = BoardCamera()

    var body: some View {
        ZStack {
            Color.darkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                boardSection
                josekiInfoBar
                josekiPanel
                controlBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: runDemoIfRequested)
    }

    // スクショ用：-demo で定石を数手自動で進める
    private func runDemoIfRequested() {
        // -demoai：定石を最後まで進め、そのまま AI 対戦の中盤まで自動で打つ（ストア用スクショ）
        if ProcessInfo.processInfo.arguments.contains("-demoai") {
            for i in 0..<12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(i) * 1.6) {
                    guard game.currentPlayer == .black, !game.isGameOver, !game.isAIThinking else { return }
                    if game.isInJoseki, let b = game.availableJosekiBranches.first {
                        game.playJosekiMove(notation: b.notation)
                    } else if let m = game.validMoveSet.sorted().first {
                        if game.makeMove(row: m / 8, col: m % 8), game.currentPlayer == .white { game.scheduleAIMove() }
                    }
                }
            }
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        for t in [1.5, 4.0, 6.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                guard game.currentPlayer == .black, let b = game.availableJosekiBranches.first else { return }
                game.playJosekiMove(notation: b.notation)
            }
        }
    }

    // MARK: - Header

    var headerBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(.black).frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                Text("\(game.blackCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .accessibilityIdentifier("blackCount")
            }

            Spacer()

            turnIndicator

            Spacer()

            HStack(spacing: 6) {
                Text("\(game.whiteCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .accessibilityIdentifier("whiteCount")
                Circle().fill(.white).frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.cardBg)
    }

    var turnIndicator: some View {
        Group {
            if game.isGameOver {
                let result: LocalizedStringKey = game.blackCount > game.whiteCount ? "あなたの勝ち!" :
                             game.blackCount < game.whiteCount ? "AIの勝ち" : "引き分け"
                Text(result)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.accentGreen)
            } else if game.isAIThinking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.accentGreen)
                    Text("AI思考中...")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.gray)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(game.currentPlayer == .black ? Color.black : Color.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    Text(game.currentPlayer == .black ? LocalizedStringKey("あなたの番") : LocalizedStringKey("AIの番"))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - Board

    var boardSection: some View {
        GeometryReader { geo in
            let boardSize = min(geo.size.width - 16, geo.size.height)
            Board3DView(game: game, camera: camera)
                .frame(width: boardSize, height: boardSize)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if !camera.isTopDown {
                        Button { camera.resetToTop() } label: {
                            Label("真上", systemImage: "arrow.down.to.line.compact")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .tint(.white)
                        .padding(8)
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: camera.isTopDown)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Joseki Info

    var josekiInfoBar: some View {
        HStack {
            if game.isInJoseki {
                Image(systemName: "book.fill")
                    .foregroundColor(.accentGreen)
                    .font(.system(size: 12))
                Text("定石モード")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.accentGreen)
                if !game.currentJosekiName.isEmpty {
                    Text(verbatim: "- " + josekiName(game.currentJosekiName))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.gray)
                }
                Text("(\(game.moveNotations.count)手目)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.gray.opacity(0.7))
            } else {
                Image(systemName: "cpu")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                Text("AI対戦モード")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.orange)
                Text("Lv.\(Int(game.aiDifficulty))")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Joseki Panel

    var josekiPanel: some View {
        Group {
            if game.isInJoseki && game.currentPlayer == .black && !game.availableJosekiBranches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("次の定石を選択")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(game.availableJosekiBranches, id: \.notation) { branch in
                                josekiCard(branch: branch)
                                    .onTapGesture {
                                        game.playJosekiMove(notation: branch.notation)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .frame(height: 110)
            } else if !game.isInJoseki && !game.isGameOver {
                difficultySlider
            } else {
                Spacer().frame(height: 40)
            }
        }
    }

    func josekiCard(branch: (notation: String, row: Int, col: Int, names: [String])) -> some View {
        let preview = game.boardAfterMove(row: branch.row, col: branch.col)
        let displayName = branch.names.first ?? branch.notation

        return VStack(spacing: 4) {
            MiniBoardView(
                board: preview,
                highlightRow: branch.row,
                highlightCol: branch.col
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(verbatim: josekiName(displayName))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(branch.notation.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.accentGreen)
        }
        .frame(width: 72)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.cardBg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentGreen.opacity(0.3), lineWidth: 1)
        )
    }

    var difficultySlider: some View {
        VStack(spacing: 4) {
            HStack {
                Text("AI強さ")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.gray)
                Spacer()
                Text(difficultyLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
            }
            Slider(value: $game.aiDifficulty, in: 1...6, step: 1)
                .tint(.orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    var difficultyLabel: LocalizedStringKey {
        switch Int(game.aiDifficulty) {
        case 1: return "入門"
        case 2: return "初級"
        case 3: return "中級"
        case 4: return "上級"
        case 5: return "強い"
        case 6: return "最強"
        default: return "中級"
        }
    }

    // MARK: - Controls

    var controlBar: some View {
        HStack(spacing: 20) {
            Button {
                game.undoToPlayerTurn()
            } label: {
                Label("戻る", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .disabled(game.moveHistory.isEmpty || game.isAIThinking)

            Spacer()

            Button {
                game.reset()
            } label: {
                Label("新しい対局", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .tint(.accentGreen)
    }
}

// 定石名は内部の照合にも使うので、表示するときだけ訳す（en.lproj/Localizable.strings）
func josekiName(_ name: String) -> String { NSLocalizedString(name, comment: "joseki name") }

// MARK: - Mini Board View

struct MiniBoardView: View {
    let board: [[CellState]]
    let highlightRow: Int
    let highlightCol: Int

    var body: some View {
        Canvas { context, size in
            let cs = size.width / 8

            // Background
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.boardGreen))

            // Grid
            for i in 0...8 {
                let pos = CGFloat(i) * cs
                var h = Path(); h.move(to: CGPoint(x: 0, y: pos)); h.addLine(to: CGPoint(x: size.width, y: pos))
                var v = Path(); v.move(to: CGPoint(x: pos, y: 0)); v.addLine(to: CGPoint(x: pos, y: size.height))
                context.stroke(h, with: .color(.boardLine), lineWidth: 0.5)
                context.stroke(v, with: .color(.boardLine), lineWidth: 0.5)
            }

            // Pieces
            for r in 0..<8 {
                for c in 0..<8 {
                    guard board[r][c] != .empty else { continue }
                    let cx = CGFloat(c) * cs + cs / 2
                    let cy = CGFloat(r) * cs + cs / 2
                    let ps = cs * 0.75
                    let rect = CGRect(x: cx - ps / 2, y: cy - ps / 2, width: ps, height: ps)
                    let color: Color = board[r][c] == .black ? .black : .white
                    context.fill(Path(ellipseIn: rect), with: .color(color))

                    // Highlight the joseki move
                    if r == highlightRow && c == highlightCol {
                        let hlRect = CGRect(x: cx - ps / 2 - 1, y: cy - ps / 2 - 1, width: ps + 2, height: ps + 2)
                        context.stroke(Path(ellipseIn: hlRect), with: .color(.lastMoveHighlight), lineWidth: 2)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
