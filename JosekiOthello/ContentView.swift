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
    @State private var gameCount = 0
    @StateObject private var interstitial = InterstitialAdManager()

    var body: some View {
        ZStack {
            Color.darkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                boardSection
                josekiInfoBar
                josekiPanel
                controlBar
                BannerAdView().frame(height: 50)
            }
        }
        .preferredColorScheme(.dark)
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
            }

            Spacer()

            turnIndicator

            Spacer()

            HStack(spacing: 6) {
                Text("\(game.whiteCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
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
                let result = game.blackCount > game.whiteCount ? "あなたの勝ち!" :
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
                    Text(game.currentPlayer == .black ? "あなたの番" : "AIの番")
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
            BoardView(game: game, size: boardSize)
                .frame(width: boardSize, height: boardSize)
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
                    Text("- \(game.currentJosekiName)")
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

            Text(displayName)
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

    var difficultyLabel: String {
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
                gameCount += 1
                if gameCount % 3 == 0 {
                    interstitial.showAd()
                }
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

// MARK: - Board View

struct BoardView: View {
    @ObservedObject var game: OthelloGame
    let size: CGFloat

    var cellSize: CGFloat { size / 8 }

    var body: some View {
        Canvas { context, canvasSize in
            let cs = canvasSize.width / 8

            // Board background
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(.boardGreen)
            )

            // Grid lines
            for i in 0...8 {
                let pos = CGFloat(i) * cs
                var hLine = Path(); hLine.move(to: CGPoint(x: 0, y: pos)); hLine.addLine(to: CGPoint(x: canvasSize.width, y: pos))
                var vLine = Path(); vLine.move(to: CGPoint(x: pos, y: 0)); vLine.addLine(to: CGPoint(x: pos, y: canvasSize.height))
                context.stroke(hLine, with: .color(.boardLine), lineWidth: 1)
                context.stroke(vLine, with: .color(.boardLine), lineWidth: 1)
            }

            // Star points
            for (r, c) in [(2,2),(2,6),(6,2),(6,6)] {
                let center = CGPoint(x: CGFloat(c) * cs + cs / 2, y: CGFloat(r) * cs + cs / 2)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(.boardLine))
            }

            // Pieces
            for r in 0..<8 {
                for c in 0..<8 {
                    let center = CGPoint(x: CGFloat(c) * cs + cs / 2, y: CGFloat(r) * cs + cs / 2)
                    let pieceSize = cs * 0.82

                    if game.board[r][c] != .empty {
                        let isBlack = game.board[r][c] == .black
                        let rect = CGRect(x: center.x - pieceSize / 2, y: center.y - pieceSize / 2, width: pieceSize, height: pieceSize)

                        // Shadow
                        let shadowRect = rect.offsetBy(dx: 1, dy: 2)
                        context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.3)))

                        // Piece
                        context.fill(Path(ellipseIn: rect), with: .color(isBlack ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color(red: 0.95, green: 0.95, blue: 0.95)))

                        // Inner highlight
                        let hlSize = pieceSize * 0.5
                        let hlRect = CGRect(x: center.x - hlSize / 2 - 2, y: center.y - hlSize / 2 - 2, width: hlSize, height: hlSize)
                        context.fill(Path(ellipseIn: hlRect), with: .color(isBlack ? Color.white.opacity(0.08) : Color.white.opacity(0.3)))

                        // Last move indicator
                        if let last = game.lastMove, last.0 == r && last.1 == c {
                            let dotSize: CGFloat = 6
                            let dotRect = CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize)
                            context.fill(Path(ellipseIn: dotRect), with: .color(.lastMoveHighlight))
                        }
                    }

                    // Valid move indicator
                    if game.validMoveSet.contains(r * 8 + c) && game.currentPlayer == .black && !game.isAIThinking {
                        let dotSize = cs * 0.25
                        let dotRect = CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: dotRect), with: .color(.accentGreen.opacity(0.5)))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard game.currentPlayer == .black && !game.isAIThinking && !game.isGameOver else { return }
            let col = Int(location.x / cellSize)
            let row = Int(location.y / cellSize)
            guard row >= 0 && row < 8 && col >= 0 && col < 8 else { return }

            if game.makeMove(row: row, col: col) {
                if game.currentPlayer == .white && !game.isGameOver {
                    game.scheduleAIMove()
                }
            }
        }
    }
}

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
