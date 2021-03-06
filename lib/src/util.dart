library arcade_utils;

import 'dart:math';

// board dimensions
const board_y = 24;
const board_x = 10;

// values used to for empty and shadowed pixels
const empty_value = 0;
const shadow_value = -1;
const predict_value = -2;

// ai's search tree depth
const int default_max_tree_depth = 2;

// rate at which the game progresses
const ms_inc = 50;

// anything smaller might as well be handled with an animation frame
const min_tick_ms = 20;

// initial default speed for the game
const default_game_tick_ms = 400;

// initial default speed for the ai actions
const default_auto_tick_ms = 320;

enum GameInput {
  reset,

  dropPiece,
  rotatePiece,
  movePieceLeft,
  movePieceRight,
  movePieceDown,

  togglePause,
  increaseSpeed,
  decreaseSpeed,
}

// maps the score fore completing the given number of lines
int scoreForLines(int lineCount) {
  switch (lineCount) {
    case 1:
      return 40;
    case 2:
      return 100;
    case 3:
      return 300;
    case 4:
      return 1200;
  }
  return 0;
}

// used to generate new piece indexes in the queue
final _rand = Random();
int randomPieceIndex([_]) => _rand.nextInt(pieces.length);
List<int> freshQueue() => List<int>.generate(4, randomPieceIndex);

// assuming the board is valid with the piece at a given x find
// how far the piece can be dropped while still being valid
int maxValidY(int x, int y, int r, int i, List<List<int>> b) {
  var dy = 0;
  while (isValid(x, y + dy + 1, r, i, b)) {
    dy++;
  }
  return y + dy;
}

// counts the consecutive empty rows from the top of the board
int headspace(List<List<int>> b) {
  var r = 0;
  for (var y = 0; y < board_y; y++) {
    for (var x = 0; x < board_x; x++) {
      if (!pixelIsEmpty(x, y, b)) {
        return r;
      }
    }
    r++;
  }
  return r;
}

// counts the number of empty pixels with no way to fill them from above
int voids(List<List<int>> b) {
  final clearAbove = List<bool>.filled(board_x, true);
  var v = 0;
  for (var y = 0; y < board_y; y++) {
    for (var x = 0; x < board_x; x++) {
      if (pixelIsEmpty(x, y, b)) {
        if (!clearAbove[x]) {
          v++;
        }
      } else {
        clearAbove[x] = false;
      }
    }
  }
  return v;
}

// true if a piece is 100% on the board and doesn't intersect non-empty board pixels
bool isValid(int x, int y, int r, int i, List<List<int>> b) {
  final p = rotatedPiece(r, i);
  for (var py = 0; py < p.length; py++) {
    for (var px = 0; px < p[py].length; px++) {
      // board coord of this pixel of the piece
      final bx = px + x;
      final by = py + y;
      if (!pixelIsEmpty(px, py, p)) {
        if (!xOnBoard(bx) || !yOnBoard(by)) {
          // all pixels from the piece must be within the board
          return false;
        } else if (!pixelIsEmpty(bx, by, b)) {
          // piece must not collide with non-empty pixels on the board
          return false;
        }
      }
    }
  }
  return true;
}

bool pixelIsEmpty(int x, int y, List<List<int>> m) => m[y][x] == 0;

bool yOnBoard(int y) => y >= 0 && y < board_y;

bool xOnBoard(int x) => x >= 0 && x < board_x;

// returns the row indexes that are complete and can be scored and removed;
List<int> lineClears(List<List<int>> b) {
  final l = <int>[];
  for (var y = 0; y < board_y; y++) {
    var clearLine = true;
    for (var x = 0; x < board_x; x++) {
      if (pixelIsEmpty(x, y, b)) {
        clearLine = false;
      }
    }
    if (clearLine) {
      l.add(y);
    }
  }
  return l;
}

// returns a copy of the board with pixels in given lines set to empty_value
List<List<int>> boardWithLinesEmptied(List<List<int>> b, List<int> l) {
  final n = boardCopy(b);
  for (var y = l.length - 1; y >= 0; y--) {
    for (var x = 0; x < board_x; x++) {
      n[l[y]][x] = empty_value;
    }
  }
  return n;
}

// returns a copy of the board with given lines squashed (replaced from above)
List<List<int>> boardWithLinesSquashed(List<List<int>> b, List<int> l) {
  final n = boardCopy(b);
  for (var y = l.length - 1; y >= 0; y--) {
    n.removeAt(l[y]);
  }
  for (final _ in l) {
    n.insert(0, List<int>.filled(board_x, empty_value));
  }
  return n;
}

// returns a copy of b1 with non-empty pixels from b2 added to it
List<List<int>> merged(List<List<int>> b1, List<List<int>> b2) {
  final b = <List<int>>[];
  for (var y = 0; y < board_y; y++) {
    b.add(<int>[]);
    for (var x = 0; x < board_x; x++) {
      b[y].add(!pixelIsEmpty(x, y, b2) ? b2[y][x] : b1[y][x]);
    }
  }
  return b;
}

bool sameArrays(List<List<int>> b1, List<List<int>> b2) {
  for (var y = 0; y < board_y; y++) {
    for (var x = 0; x < board_x; x++) {
      if (b1[y][x] != b2[y][x]) {
        return false;
      }
    }
  }
  return true;
}

bool sameLists(List<int> l1, List<int> l2) {
  if (l1.length != l2.length) {
    return false;
  }
  for (var i = 0; i < l1.length; i++) {
    if (l1[i] != l2[i]) {
      return false;
    }
  }
  return true;
}

// returns a board sized 2d array with a piece's pixels set within it
List<List<int>> pieceMask(int x, int y, int r, int i) => boardWithPiece(x, y, r, i, emptyBoard());

// returns a copy of the given board with a piece's pixels added
List<List<int>> boardWithPiece(int x, int y, int r, int i, List<List<int>> b) {
  final n = boardCopy(b);
  final p = rotatedPiece(r, i);
  for (var py = 0; py < p.length; py++) {
    for (var px = 0; px < p[py].length; px++) {
      // board coord of this piece pixel
      final by = py + y;
      final bx = px + x;
      if (!pixelIsEmpty(px, py, p) && xOnBoard(bx) && yOnBoard(by)) {
        n[by][bx] = p[py][px];
      }
    }
  }
  return n;
}

List<List<int>> emptyBoard() {
  final b = <List<int>>[];
  for (var y = 0; y < board_y; y++) {
    b.add(List<int>.filled(board_x, empty_value));
  }
  return b;
}

// returns a board sized 2d array identical to the one provided, all non-empty
// pixels will be replaced with the mask if given
List<List<int>> boardCopy(List<List<int>> b, {int mask}) {
  final n = <List<int>>[];
  for (var y = 0; y < board_y; y++) {
    n.add(<int>[]);
    for (var x = 0; x < board_x; x++) {
      if (pixelIsEmpty(x, y, b)) {
        n[y].add(empty_value);
      } else {
        n[y].add(mask ?? b[y][x]);
      }
    }
  }
  return n;
}

// yield the difference a piece would make to the topology of a board if placed at the given x with the given rotation
int topoDelta(int x, int r, int i, List<int> t) {
  var d = 0;
  final pt = pieceTopo(i, r);
  final ptm = pieceTopoMask(i, r);

  // piece must sit above the pixels on the board, shifting all piece y's up that amount
  var sit = 0;
  for (var i = 0; i < pt.length; i++) {
    // iterate over the piece part of the topo map
    final bx = x + i;
    if (xOnBoard(bx) && ptm[i]) {
      final thisSit = t[bx] - pt[i];
      if (thisSit > sit) {
        sit = thisSit;
      }
    }
  }
  for (var i = 0; i < pt.length; i++) {
    final bx = x + i;
    final di = xOnBoard(bx) && ptm[i] ? (pt[i] + sit - t[bx]).abs() : 0;
    d += di;
  }
  return d;
}

List<int> boardTopology(List<List<int>> b) {
  final e = <int>[];
  var lowestPoint = 0;
  for (var x = 0; x < board_x; x++) {
    var y = 0;
    while (y + 1 < board_y && pixelIsEmpty(x, y + 1, b)) {
      y++;
    }
    if (y > lowestPoint) {
      lowestPoint = y;
    }
    e.add(y);
  }
  for (var x = 0; x < board_x; x++) {
    e[x] = lowestPoint - e[x];
  }
  return e;
}

// pretty print a 2d array to the console
void printArray(List<List<int>> a, {String label}) {
  print('------------ ${label ?? ""}');
  if (a[0].length <= 10) {
    var xAxis = '';
    for (var x = 0; x < a[0].length; x++) {
      xAxis += ' $x ';
    }
    print(xAxis);
  }
  for (var y = 0; y < a.length; y++) {
    var line = '';
    for (var x = 0; x < a[y].length; x++) {
      line += '${pixelIsEmpty(x, y, a) ? "[ ]" : "[x]"}';
    }
    print('$line $y');
  }
}

// returns a 2d array representing a piece rotated clockwise r times
List<List<int>> rotatedPiece(int r, int i) {
  var piece = pieces[i];
  for (var j = 0; j < r; j++) {
    piece = rotateCW(piece);
  }
  return piece;
}

// rotates the given 2d array 90 degrees clockwise
List<List<int>> rotateCW(List<List<int>> piece) {
  final len = piece.length; // all pieces are square
  final rotation = <List<int>>[];
  for (var y = 0; y < len; y++) {
    rotation.add(<int>[]);
    for (var x = 0; x < len; x++) {
      rotation[y].add(piece[len - 1 - x][y]);
    }
  }
  return rotation;
}

// returns the starting x for a specific piece index
int initialX(int pieceIndex) {
  switch (pieceIndex) {
    case 0:
      return 4;
    default:
      return 3;
  }
}

// returns the starting y for a specific piece index
int initialY(int pieceIndex) {
  switch (pieceIndex) {
    case 1:
    case 2:
    case 3:
    case 6:
      return -1;
    default:
      return 0;
  }
}

// used when printing the queue to the console
final piece_avatars = <String>[
  '⠶',
  '⠒⠒',
  '⠴⠂',
  '⠲⠄',
  '⠧',
  '⠼',
  '⠲⠂',
];

// rotation values used while Branching to explore game space
const rs = [0, 1, 2, 3];

// x values used while Branching to explore game space
const xs = [-2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8];

// list of rotations that do not share symmetry
final piece_rs = <int>[
  1,
  2,
  2,
  2,
  4,
  4,
  4,
];

List<int> pieceTopo(int i, int r) => piece_topos[i][r];

// topo is a list of deltas in y from the bottom left corner of a piece
// as x comparison will run from left to right on the board as deltas from the 1st non-empty piece x as well
// piece topos are 2 px larger to account for optimal neighbor heights
final piece_topos = genPieceTopos();

// a topo for each rotation of each piece: topo[i][r] = List<int>
List<List<List<int>>> genPieceTopos() {
  final topos = <List<List<int>>>[];
  for (var i = 0; i < pieces.length; i++) {
    topos.add(<List<int>>[]);
    for (var r = 0; r < piece_rs[i]; r++) {
      final piece = rotatedPiece(r, i);
      topos[i].add(genPieceTopo(piece));
    }
  }
  return topos;
}

List<int> genPieceTopo(List<List<int>> piece) {
  final topo = List<int>.filled(piece.length, 0);
  final done = List<bool>.filled(piece.length, false);
  int bottomY;
  for (var y = piece.length - 1; y >= 0; y--) {
    for (var x = 0; x < piece.length; x++) {
      if (!pixelIsEmpty(x, y, piece) && !done[x]) {
        bottomY ??= y;
        topo[x] = bottomY - y;
        done[x] = true;
      }
    }
  }
  return topo;
}

List<bool> pieceTopoMask(int i, int r) => piece_topo_masks[i][r];

// topo masks are 2 px larger than the piece to compare neighboring piece hights
final piece_topo_masks = genPieceTopoMasks();

// a topo mask for each rotation of each piece: mask[i][r] = List<bool>
List<List<List<bool>>> genPieceTopoMasks() {
  final mask = <List<List<bool>>>[];
  for (var i = 0; i < pieces.length; i++) {
    mask.add(<List<bool>>[]);
    for (var r = 0; r < piece_rs[i]; r++) {
      final piece = rotatedPiece(r, i);
      mask[i].add(getPieceTopoMask(piece));
    }
  }
  return mask;
}

List<bool> getPieceTopoMask(List<List<int>> piece) {
  final mask = List<bool>.filled(piece.length, false);
  for (var y = 0; y < piece.length; y++) {
    for (var x = 0; x < piece.length; x++) {
      if (!pixelIsEmpty(x, y, piece)) {
        mask[x] = true;
      }
    }
  }
  return mask;
}

// list of 2d arrays encoding each pieces' shape and color
final pieces = <List<List<int>>>[
  [
    [1, 1],
    [1, 1]
  ],
  [
    [0, 0, 0, 0],
    [2, 2, 2, 2],
    [0, 0, 0, 0],
    [0, 0, 0, 0]
  ],
  [
    [0, 0, 0],
    [0, 3, 3],
    [3, 3, 0]
  ],
  [
    [0, 0, 0],
    [4, 4, 0],
    [0, 4, 4]
  ],
  [
    [0, 5, 0],
    [0, 5, 0],
    [0, 5, 5]
  ],
  [
    [0, 6, 0],
    [0, 6, 0],
    [6, 6, 0]
  ],
  [
    [0, 0, 0],
    [7, 7, 7],
    [0, 7, 0]
  ],
];
