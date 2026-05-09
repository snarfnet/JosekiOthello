import Foundation

enum CellState: Int {
    case empty = 0, black = 1, white = 2

    var opponent: CellState {
        switch self {
        case .black: return .white
        case .white: return .black
        default: return .empty
        }
    }
}

struct Move {
    let row: Int
    let col: Int
    let player: CellState
    let flipped: [(Int, Int)]
}

class OthelloGame: ObservableObject {
    @Published var board: [[CellState]] = Array(repeating: Array(repeating: .empty, count: 8), count: 8)
    @Published var currentPlayer: CellState = .black
    @Published var moveHistory: [Move] = []
    @Published var moveNotations: [String] = []
    @Published var isGameOver = false
    @Published var blackCount = 2
    @Published var whiteCount = 2
    @Published var aiDifficulty: Double = 3
    @Published var isAIThinking = false
    @Published var validMoveSet: Set<Int> = []
    @Published var lastMove: (Int, Int)? = nil
    @Published var passCount = 0

    // Joseki
    @Published var isInJoseki = true
    @Published var currentJosekiName = ""
    @Published var availableJosekiBranches: [(notation: String, row: Int, col: Int, names: [String])] = []

    let josekiTrie = JosekiTrie()

    private let directions = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]

    private let positionWeights = [
        [100, -20, 10,  5,  5, 10, -20, 100],
        [-20, -50, -2, -2, -2, -2, -50, -20],
        [ 10,  -2,  5,  1,  1,  5,  -2,  10],
        [  5,  -2,  1,  0,  0,  1,  -2,   5],
        [  5,  -2,  1,  0,  0,  1,  -2,   5],
        [ 10,  -2,  5,  1,  1,  5,  -2,  10],
        [-20, -50, -2, -2, -2, -2, -50, -20],
        [100, -20, 10,  5,  5, 10, -20, 100]
    ]

    init() {
        for seq in josekiDatabase {
            josekiTrie.insert(seq)
        }
        reset()
    }

    func reset() {
        board = Array(repeating: Array(repeating: .empty, count: 8), count: 8)
        board[3][3] = .white; board[3][4] = .black
        board[4][3] = .black; board[4][4] = .white
        currentPlayer = .black
        moveHistory = []
        moveNotations = []
        isGameOver = false
        passCount = 0
        lastMove = nil
        isAIThinking = false
        isInJoseki = true
        currentJosekiName = ""
        updateState()
    }

    func updateState() {
        countPieces()
        let moves = getValidMoves(for: currentPlayer)
        validMoveSet = Set(moves.map { $0.0 * 8 + $0.1 })
        updateJoseki()

        if moves.isEmpty {
            let opponentMoves = getValidMoves(for: currentPlayer.opponent)
            if opponentMoves.isEmpty {
                isGameOver = true
            } else {
                passCount += 1
                currentPlayer = currentPlayer.opponent
                let newMoves = getValidMoves(for: currentPlayer)
                validMoveSet = Set(newMoves.map { $0.0 * 8 + $0.1 })
                updateJoseki()
                if currentPlayer == .white && !isGameOver {
                    scheduleAIMove()
                }
            }
        }
    }

    func countPieces() {
        var b = 0, w = 0
        for row in board { for cell in row {
            if cell == .black { b += 1 }
            else if cell == .white { w += 1 }
        }}
        blackCount = b; whiteCount = w
    }

    // MARK: - Move Logic

    func getValidMoves(for player: CellState) -> [(Int, Int)] {
        var moves: [(Int, Int)] = []
        for r in 0..<8 { for c in 0..<8 {
            if board[r][c] == .empty && !getFlips(row: r, col: c, player: player).isEmpty {
                moves.append((r, c))
            }
        }}
        return moves
    }

    func getFlips(row: Int, col: Int, player: CellState) -> [(Int, Int)] {
        var allFlips: [(Int, Int)] = []
        for (dr, dc) in directions {
            var flips: [(Int, Int)] = []
            var r = row + dr, c = col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 && board[r][c] == player.opponent {
                flips.append((r, c))
                r += dr; c += dc
            }
            if r >= 0 && r < 8 && c >= 0 && c < 8 && board[r][c] == player && !flips.isEmpty {
                allFlips.append(contentsOf: flips)
            }
        }
        return allFlips
    }

    @discardableResult
    func makeMove(row: Int, col: Int) -> Bool {
        guard board[row][col] == .empty else { return false }
        let flips = getFlips(row: row, col: col, player: currentPlayer)
        guard !flips.isEmpty else { return false }

        let move = Move(row: row, col: col, player: currentPlayer, flipped: flips)
        board[row][col] = currentPlayer
        for (r, c) in flips { board[r][c] = currentPlayer }
        moveHistory.append(move)
        moveNotations.append(notation(row: row, col: col))
        lastMove = (row, col)
        passCount = 0
        currentPlayer = currentPlayer.opponent
        updateState()
        return true
    }

    func undo() {
        guard let move = moveHistory.last else { return }
        moveHistory.removeLast()
        moveNotations.removeLast()

        board[move.row][move.col] = .empty
        for (r, c) in move.flipped { board[r][c] = move.player.opponent }
        currentPlayer = move.player
        lastMove = moveHistory.last.map { ($0.row, $0.col) }
        isGameOver = false
        isAIThinking = false
        updateState()
    }

    func undoToPlayerTurn() {
        // Undo AI move + player move
        if moveHistory.last?.player == .white { undo() }
        if !moveHistory.isEmpty { undo() }
    }

    func notation(row: Int, col: Int) -> String {
        let colChar = String(UnicodeScalar(97 + col)!)
        return "\(colChar)\(row + 1)"
    }

    func parseNotation(_ s: String) -> (Int, Int) {
        let col = Int(s.first!.asciiValue!) - 97
        let row = Int(String(s.dropFirst()))! - 1
        return (row, col)
    }

    // MARK: - Board Preview

    func boardAfterMove(row: Int, col: Int) -> [[CellState]] {
        var preview = board
        let flips = getFlips(row: row, col: col, player: currentPlayer)
        preview[row][col] = currentPlayer
        for (r, c) in flips { preview[r][c] = currentPlayer }
        return preview
    }

    // MARK: - Joseki

    func updateJoseki() {
        let children = josekiTrie.getChildren(after: moveNotations)
        if children.isEmpty {
            isInJoseki = false
            availableJosekiBranches = []
            return
        }

        isInJoseki = true
        var branches: [(notation: String, row: Int, col: Int, names: [String])] = []
        for (moveStr, node) in children.sorted(by: { $0.key < $1.key }) {
            let (r, c) = parseNotation(moveStr)
            // Only show valid moves
            if !getFlips(row: r, col: c, player: currentPlayer).isEmpty {
                branches.append((notation: moveStr, row: r, col: c, names: node.passingNames))
            }
        }
        availableJosekiBranches = branches

        if branches.isEmpty {
            isInJoseki = false
        }

        // Update current joseki name
        if let node = josekiTrie.getNode(after: moveNotations) {
            if !node.josekiNames.isEmpty {
                currentJosekiName = node.josekiNames.first!
            } else if !node.passingNames.isEmpty {
                currentJosekiName = node.passingNames.first!
            }
        }
    }

    func playJosekiMove(notation: String) {
        let (r, c) = parseNotation(notation)
        makeMove(row: r, col: c)

        // If it's now AI's turn and still in joseki, auto-play
        if currentPlayer == .white && isInJoseki && !isGameOver {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.autoPlayJosekiOrAI()
            }
        }
    }

    func scheduleAIMove() {
        guard currentPlayer == .white && !isGameOver else { return }
        if isInJoseki {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.autoPlayJosekiOrAI()
            }
        } else {
            isAIThinking = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let move = self.bestAIMove()
                DispatchQueue.main.async {
                    self.isAIThinking = false
                    if let (r, c) = move {
                        self.makeMove(row: r, col: c)
                    }
                }
            }
        }
    }

    func autoPlayJosekiOrAI() {
        guard currentPlayer == .white && !isGameOver else { return }
        if isInJoseki && !availableJosekiBranches.isEmpty {
            let branch = availableJosekiBranches[0]
            makeMove(row: branch.row, col: branch.col)
        } else {
            scheduleAIMove()
        }
    }

    // MARK: - AI (Minimax + Alpha-Beta)

    func bestAIMove() -> (Int, Int)? {
        let moves = getValidMoves(for: .white)
        if moves.isEmpty { return nil }

        let depth = Int(aiDifficulty)
        var bestScore = Int.min
        var bestMove = moves[0]

        var boardCopy = board
        for (r, c) in moves {
            let flips = getFlips(row: r, col: c, player: .white)
            board[r][c] = .white
            for (fr, fc) in flips { board[fr][fc] = .white }

            let score = minimax(depth: depth - 1, alpha: Int.min, beta: Int.max, maximizing: false)

            board[r][c] = .empty
            for (fr, fc) in flips { board[fr][fc] = .black }
            board = boardCopy

            if score > bestScore {
                bestScore = score
                bestMove = (r, c)
            }
        }
        return bestMove
    }

    func minimax(depth: Int, alpha: Int, beta: Int, maximizing: Bool) -> Int {
        if depth == 0 || isTerminal() {
            return evaluate()
        }

        let player: CellState = maximizing ? .white : .black
        let moves = getValidMoves(for: player)

        if moves.isEmpty {
            let opponentMoves = getValidMoves(for: player.opponent)
            if opponentMoves.isEmpty { return evaluate() }
            return minimax(depth: depth - 1, alpha: alpha, beta: beta, maximizing: !maximizing)
        }

        var a = alpha, b = beta
        let boardBackup = board

        if maximizing {
            var maxScore = Int.min
            for (r, c) in moves {
                let flips = getFlips(row: r, col: c, player: player)
                board[r][c] = player
                for (fr, fc) in flips { board[fr][fc] = player }

                let score = minimax(depth: depth - 1, alpha: a, beta: b, maximizing: false)

                board = boardBackup

                maxScore = max(maxScore, score)
                a = max(a, score)
                if b <= a { break }
            }
            return maxScore
        } else {
            var minScore = Int.max
            for (r, c) in moves {
                let flips = getFlips(row: r, col: c, player: player)
                board[r][c] = player
                for (fr, fc) in flips { board[fr][fc] = player }

                let score = minimax(depth: depth - 1, alpha: a, beta: b, maximizing: true)

                board = boardBackup

                minScore = min(minScore, score)
                b = min(b, score)
                if b <= a { break }
            }
            return minScore
        }
    }

    func evaluate() -> Int {
        var score = 0
        let totalPieces = blackCount + whiteCount
        let isEndgame = totalPieces > 52

        for r in 0..<8 { for c in 0..<8 {
            let w = positionWeights[r][c]
            if board[r][c] == .white { score += w }
            else if board[r][c] == .black { score -= w }
        }}

        if !isEndgame {
            let whiteMobility = getValidMoves(for: .white).count
            let blackMobility = getValidMoves(for: .black).count
            score += (whiteMobility - blackMobility) * 10
        } else {
            var wc = 0, bc = 0
            for row in board { for cell in row {
                if cell == .white { wc += 1 }
                else if cell == .black { bc += 1 }
            }}
            score += (wc - bc) * 5
        }

        return score
    }

    func isTerminal() -> Bool {
        return getValidMoves(for: .white).isEmpty && getValidMoves(for: .black).isEmpty
    }
}
