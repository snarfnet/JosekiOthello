import Foundation

struct JosekiSequence {
    let name: String
    let moves: [String]
    let description: String
}

let josekiDatabase: [JosekiSequence] = [
    // 斜め取り (Diagonal) - f5 d6
    JosekiSequence(
        name: "虎定石",
        moves: ["f5", "d6", "c3", "d3", "c4", "f4", "c5", "b3", "c2"],
        description: "バランス重視の安定型。中央を固めて隅を狙う"
    ),
    JosekiSequence(
        name: "うさぎ定石",
        moves: ["f5", "d6", "c4", "d3", "c2", "c3", "d2"],
        description: "序盤から攻めの姿勢。上辺を取りに行く"
    ),
    JosekiSequence(
        name: "牛定石",
        moves: ["f5", "d6", "c5", "f4", "e3", "f6", "g5"],
        description: "右辺に展開する正統派。相手の手を制限する"
    ),
    JosekiSequence(
        name: "蛇定石",
        moves: ["f5", "d6", "c6", "d3", "f4", "c5"],
        description: "変則的な下辺展開。意表を突く手筋"
    ),
    JosekiSequence(
        name: "ねずみ定石",
        moves: ["f5", "d6", "c4", "d3", "c5", "f4"],
        description: "中央を厚くする堅実な展開"
    ),
    JosekiSequence(
        name: "猫定石",
        moves: ["f5", "d6", "c4", "d3", "c2", "b3", "c5"],
        description: "左辺に壁を作る守備的戦法"
    ),
    JosekiSequence(
        name: "虎裏定石",
        moves: ["f5", "d6", "c3", "d3", "c4", "f4", "f6", "e3"],
        description: "虎定石の変化形。右側に展開を広げる"
    ),

    // 縦取り (Perpendicular) - f5 f6
    JosekiSequence(
        name: "ローズ定石",
        moves: ["f5", "f6", "e6", "d6", "c5", "f4", "e3"],
        description: "縦取りの代表格。左下から中央を支配する"
    ),
    JosekiSequence(
        name: "酉定石",
        moves: ["f5", "f6", "e6", "f4", "e3", "d6", "c5"],
        description: "縦取りの変化。中央で主導権を握る"
    ),
    JosekiSequence(
        name: "縦取り虎",
        moves: ["f5", "f6", "e6", "d6", "c4", "d3", "c3"],
        description: "縦取りから虎系に合流する展開"
    ),

    // 並び取り (Parallel) - f5 f4
    JosekiSequence(
        name: "コンポス定石",
        moves: ["f5", "f4", "e3", "f6", "e6", "g5"],
        description: "並び取りの基本形。右辺を厚くする"
    ),
    JosekiSequence(
        name: "並び取り裏",
        moves: ["f5", "f4", "e3", "d6", "c5", "d3"],
        description: "並び取りから左辺展開。意外性のある手順"
    ),
]

// Trie for efficient joseki lookup
class JosekiTrie {
    class Node {
        var children: [String: Node] = [:]
        var josekiNames: [String] = []
        var passingNames: [String] = []
    }

    let root = Node()

    func insert(_ seq: JosekiSequence) {
        var node = root
        for move in seq.moves {
            if node.children[move] == nil {
                node.children[move] = Node()
            }
            node = node.children[move]!
            node.passingNames.append(seq.name)
        }
        node.josekiNames.append(seq.name)
    }

    func getChildren(after moves: [String]) -> [String: Node] {
        var node = root
        for move in moves {
            guard let next = node.children[move] else { return [:] }
            node = next
        }
        return node.children
    }

    func getNode(after moves: [String]) -> Node? {
        var node = root
        for move in moves {
            guard let next = node.children[move] else { return nil }
            node = next
        }
        return node
    }
}
