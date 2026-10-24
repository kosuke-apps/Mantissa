/// A position in a `MathEditor`: which line, which structure slots lead to the sequence, and where in that sequence.
///
/// `path` lists the steps from the line down: each step enters slot `slot` of the node at index `index` of the
/// sequence reached so far. An empty path means the cursor is in the line itself.
public struct MathCursor: Hashable, Sendable, Codable {
  public struct Step: Hashable, Sendable, Codable {
    public var index: Int
    public var slot: Int

    public init(index: Int, slot: Int) {
      self.index = index
      self.slot = slot
    }
  }

  public var line: Int
  public var path: [Step]
  /// The cursor sits before the node at this index of the sequence (after the last node when it equals the count).
  public var offset: Int

  public init(line: Int = 0, path: [Step] = [], offset: Int = 0) {
    self.line = line
    self.path = path
    self.offset = offset
  }
}

/// The model behind the maths keyboard: what has been typed, as lines of structured formulas, and the cursor in them.
///
/// Every key is a method: typing a character, a fraction, a power, a root, parentheses or a function; moving the cursor
/// left and right through the structure; deleting; starting a new line (one equation per line for a system). It has no
/// user interface and no dependence on the rest of the engine except `text`, which writes the lines in the form the
/// parser reads.
public struct MathEditor: Equatable, Sendable {
  public private(set) var lines: [[MathNode]]
  public private(set) var cursor: MathCursor

  public init() {
    lines = [[]]
    cursor = MathCursor()
  }

  /// An editor holding `lines`, with the cursor at the end of the last one.
  public init(lines: [[MathNode]]) {
    self.lines = lines.isEmpty ? [[]] : lines
    cursor = MathCursor(line: self.lines.count - 1, path: [], offset: self.lines[self.lines.count - 1].count)
  }

  public var isEmpty: Bool { lines.allSatisfy { $0.isEmpty } }

  /// Whether the cursor points at a real place. Always true unless there is a bug; the tests check it after every key.
  public var isValid: Bool {
    guard lines.indices.contains(cursor.line) else { return false }
    var sequence = lines[cursor.line]
    for step in cursor.path {
      guard sequence.indices.contains(step.index), step.slot < sequence[step.index].slotCount else { return false }
      sequence = sequence[step.index].slot(step.slot)
    }
    return (0...sequence.count).contains(cursor.offset)
  }

  // MARK: Reading and editing the sequence at the cursor

  private static func sequence(in root: [MathNode], path: ArraySlice<MathCursor.Step>) -> [MathNode] {
    guard let step = path.first else { return root }
    return sequence(in: root[step.index].slot(step.slot), path: path.dropFirst())
  }

  private static func update<T>(
    _ root: inout [MathNode], path: ArraySlice<MathCursor.Step>, _ body: (inout [MathNode]) -> T
  ) -> T {
    guard let step = path.first else { return body(&root) }
    let node = root[step.index]
    var inner = node.slot(step.slot)
    let result = update(&inner, path: path.dropFirst(), body)
    root[step.index] = node.replacingSlot(step.slot, with: inner)
    return result
  }

  private var currentSequence: [MathNode] {
    Self.sequence(in: lines[cursor.line], path: cursor.path[...])
  }

  /// The node that holds the sequence the cursor is in, or `nil` when the cursor is in the line itself.
  private var container: MathNode? {
    guard let step = cursor.path.last else { return nil }
    return Self.sequence(in: lines[cursor.line], path: cursor.path.dropLast())[step.index]
  }

  /// Runs `body` on the sequence at the cursor, with the cursor's offset, and keeps whatever `body` changes.
  @discardableResult
  mutating func edit<T>(_ body: (inout [MathNode], inout Int) -> T) -> T {
    var offset = cursor.offset
    let result = Self.update(&lines[cursor.line], path: cursor.path[...]) { sequence in body(&sequence, &offset) }
    cursor.offset = offset
    return result
  }

  /// Puts the cursor at the start (or end) of slot `slot` of the node at `index` in the current sequence.
  private mutating func enter(index: Int, slot: Int, atEnd: Bool = false) {
    cursor.path.append(MathCursor.Step(index: index, slot: slot))
    cursor.offset = atEnd ? currentSequence.count : 0
  }

  // MARK: Typing

  /// Types one character. `(` opens parentheses (with the cursor inside), `)` closes them, that is, steps out of the
  /// parentheses, function or bars the cursor is in; anything else is inserted as a symbol.
  public mutating func insert(_ text: String) {
    switch text {
    case "(": insertGroup()
    case ")": closeEnclosing()
    default: insertNode(.symbol(text))
    }
  }

  /// Puts one symbol at the cursor exactly as it is. For `(` and `)` that means a single bracket, not a pair with the cursor
  /// inside: the brackets are then matched when the formula is read, which lets them go round what is already typed.
  public mutating func insertLiteral(_ text: String) { insertNode(.symbol(text)) }

  private mutating func insertNode(_ node: MathNode) {
    edit { sequence, offset in
      sequence.insert(node, at: offset)
      offset += 1
    }
  }

  /// Inserts a structure at the cursor and moves into slot `slot` of it.
  private mutating func insertStructure(_ node: MathNode, enteringSlot slot: Int = 0) {
    let index = edit { sequence, offset -> Int in
      sequence.insert(node, at: offset)
      return offset
    }
    enter(index: index, slot: slot)
  }

  public mutating func insertGroup() { insertStructure(.group([])) }
  public mutating func insertAbsolute() { insertStructure(.absolute([])) }

  /// A function such as `sin`, `ln` or `log`, with the cursor in its argument.
  public mutating func insertFunction(_ name: String) { insertStructure(.function(name: name, argument: [])) }

  /// `log` with a base written small below it; the cursor starts in the base.
  public mutating func insertLogarithm() { insertStructure(.logarithm(base: [], argument: [])) }

  /// ∫, Σ, lim or d/dx, with the cursor in its expression; the variable (and, for a sum, its ends) are already filled in.
  public mutating func insertCalculus(_ kind: CalculusKind) {
    insertStructure(.calculus(kind, kind.initialSlots))
  }

  /// A square root, or an n-th root when `withIndex` is true (the cursor then starts in the index).
  public mutating func insertRadical(withIndex: Bool = false) {
    insertStructure(.radical(index: withIndex ? [] : nil, radicand: []))
  }

  /// An exponent for what comes just before the cursor; the cursor moves into it.
  public mutating func insertPower() { insertStructure(.superscript([])) }

  /// A fraction. What comes just before the cursor (a number, a variable, a parenthesised group, a function, with any
  /// exponent or factorial it carries) becomes the numerator and the cursor moves to the denominator; with nothing
  /// before it the cursor starts in an empty numerator.
  public mutating func insertFraction() {
    let (index, hasNumerator) = edit { sequence, offset -> (Int, Bool) in
      let start = Self.operandStart(in: sequence, before: offset)
      let numerator = Array(sequence[start..<offset])
      sequence.replaceSubrange(start..<offset, with: [.fraction(numerator: numerator, denominator: [])])
      offset = start
      return (start, !numerator.isEmpty)
    }
    enter(index: index, slot: hasNumerator ? 1 : 0)
  }

  /// The index where the operand just before `offset` starts, or `offset` itself when there is none.
  static func operandStart(in sequence: [MathNode], before offset: Int) -> Int {
    func isPostfix(_ node: MathNode) -> Bool {
      if case .superscript = node { return true }
      return ["!", "%", "°"].contains(node.symbolCharacter.map(String.init) ?? "")
    }
    var start = offset
    while start > 0, isPostfix(sequence[start - 1]) { start -= 1 }
    guard start > 0 else { return offset }
    let base = sequence[start - 1]
    guard let character = base.symbolCharacter else { return start - 1 }  // a structure is one operand
    if character.isNumber || character == "." {
      var first = start - 1
      while first > 0, let previous = sequence[first - 1].symbolCharacter, previous.isNumber || previous == "." {
        first -= 1
      }
      return first
    }
    return character.isLetter ? start - 1 : offset  // a variable or constant; an operator has no operand
  }

  private mutating func closeEnclosing() {
    guard let step = cursor.path.last, let node = container else { return }
    switch node {
    case .group, .function, .absolute:
      cursor.path.removeLast()
      cursor.offset = step.index + 1
    case .logarithm where step.slot == 1:  // a closing parenthesis ends the argument, not the base
      cursor.path.removeLast()
      cursor.offset = step.index + 1
    default: break
    }
  }

  // MARK: Moving

  /// Puts the cursor at `target`, if that is a place in the formula (a line, a chain of slots and an offset that all exist).
  /// Returns false and changes nothing otherwise.
  @discardableResult
  public mutating func moveCursor(to target: MathCursor) -> Bool {
    let before = cursor
    cursor = target
    if isValid { return true }
    cursor = before
    return false
  }

  /// One step to the right. Through a structure the cursor visits every slot in turn (numerator, then denominator),
  /// and at the end of a line it goes on to the next line.
  public mutating func moveRight() {
    let sequence = currentSequence
    if cursor.offset < sequence.count {
      if sequence[cursor.offset].isStructure {
        enter(index: cursor.offset, slot: 0)
      } else {
        cursor.offset += 1
      }
      return
    }
    if let step = cursor.path.last, let node = container {
      if step.slot + 1 < node.slotCount {
        cursor.path[cursor.path.count - 1].slot += 1
        cursor.offset = 0
      } else {
        cursor.path.removeLast()
        cursor.offset = step.index + 1
      }
      return
    }
    if cursor.line + 1 < lines.count {
      cursor.line += 1
      cursor.offset = 0
    }
  }

  /// One step to the left; the mirror image of `moveRight`.
  public mutating func moveLeft() {
    let sequence = currentSequence
    if cursor.offset > 0 {
      let node = sequence[cursor.offset - 1]
      if node.isStructure {
        enter(index: cursor.offset - 1, slot: node.slotCount - 1, atEnd: true)
      } else {
        cursor.offset -= 1
      }
      return
    }
    if let step = cursor.path.last, let node = container {
      if step.slot > 0 {
        cursor.path[cursor.path.count - 1].slot -= 1
        cursor.offset = node.slot(step.slot - 1).count
      } else {
        cursor.path.removeLast()
        cursor.offset = step.index
      }
      return
    }
    if cursor.line > 0 {
      cursor.line -= 1
      cursor.offset = lines[cursor.line].count
    }
  }

  // MARK: Deleting and lines

  /// Deletes backwards. A symbol goes; a structure with something in it is entered from its end, so that its contents are
  /// deleted first; an empty structure goes whole. At the start of a slot the cursor steps left, and when the whole
  /// structure is empty the structure is removed.
  public mutating func backspace() {
    if cursor.offset > 0 {
      let node = currentSequence[cursor.offset - 1]
      if node.isStructure && !node.isEmptyStructure {
        enter(index: cursor.offset - 1, slot: node.slotCount - 1, atEnd: true)
      } else {
        edit { sequence, offset in
          sequence.remove(at: offset - 1)
          offset -= 1
        }
      }
      return
    }
    if let step = cursor.path.last, let node = container {
      if node.isEmptyStructure {
        cursor.path.removeLast()
        edit { sequence, _ in sequence.remove(at: step.index) }
        cursor.offset = step.index
      } else {
        moveLeft()
      }
      return
    }
    if cursor.line > 0 && lines[cursor.line].isEmpty {
      lines.remove(at: cursor.line)
      cursor.line -= 1
      cursor.offset = lines[cursor.line].count
    }
  }

  /// Starts a new line after the current one, for the next equation of a system.
  public mutating func newLine() {
    lines.insert([], at: cursor.line + 1)
    cursor = MathCursor(line: cursor.line + 1)
  }

  /// Empties everything.
  public mutating func clear() {
    self = MathEditor()
  }
}
