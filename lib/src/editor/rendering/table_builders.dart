// Table node widget builders for the document renderer.
//
// This is a part of the `document_renderer` library (see document_renderer.dart).
// It holds the builders for the four table node types the engine's TableKit
// build emits: table, tableRow, tableCell, and tableHeader.
//
// Two structural facts drive the shape of this file:
//
//   1. A cell holds *block* content, not inline content. A cell's children are
//      paragraphs, so they are built through the normal node dispatch
//      (childBuilder) rather than as a single text span the way paragraph and
//      heading are.
//   2. Flutter's Table takes rows of equal cell counts, and TableRow cannot be
//      produced by the registry's generic Widget-returning builder signature.
//      So `table` builds its rows itself, and the row/cell builders exist for
//      the case where one is dispatched on its own — a malformed document, or
//      a host rendering a fragment.
//
// A part file shares the imports declared in the parent library file.

part of 'document_renderer.dart';

/// Border colour for table cells.
///
/// A single flat grey rather than a themed colour: this renderer has no
/// BuildContext at builder level, and a hard-coded neutral reads acceptably on
/// both light and dark backgrounds.
const _tableBorderColor = Color(0xFFD4D4D8);

const _tableCellPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);

/// Background for header cells, distinguishing them from body cells.
const _tableHeaderBackground = Color(0xFFF4F4F5);

// -----------------------------------------------------------------------------
// Table
// -----------------------------------------------------------------------------

Widget _buildTable(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final rows = node.content ?? const [];
  if (rows.isEmpty) return const SizedBox.shrink();

  /// Flutter's Table requires every row to have the same number of children.
  /// A document with merged cells (colspan) has rows of differing lengths, so
  /// short rows are padded with empty cells to the widest row's count.
  /// Without this, Table throws rather than rendering a slightly-wrong table.
  final columnCount = rows
      .map((row) => _cellCountOf(row))
      .fold<int>(0, (widest, count) => count > widest ? count : widest);

  if (columnCount == 0) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Table(
      border: TableBorder.all(color: _tableBorderColor, width: 1),

      /// Content-sized columns: a legal table's first column is usually a
      /// short label and the rest are prose, so sizing every column equally
      /// would waste the label column's width.
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final row in rows)
          TableRow(
            children: _paddedCells(row, columnCount, childBuilder),
          ),
      ],
    ),
  );
}

/// Number of cells in a row, counting a merged cell once per column it spans.
int _cellCountOf(AnnotatedNode row) {
  final cells = row.content ?? const [];
  var count = 0;
  for (final cell in cells) {
    final colspan = cell.attrs?[NodeAttr.colspan];
    count += colspan is int && colspan > 0 ? colspan : 1;
  }
  return count;
}

/// Build a row's cells, padding to [columnCount] so Flutter's Table gets
/// uniform rows.
///
/// A cell with colspan > 1 is rendered once and followed by empty filler
/// cells. This is a deliberate approximation: Flutter's Table has no column
/// spanning, so the alternative to filler cells is not rendering the table at
/// all. The text lands in the right row, only the merge is lost visually.
List<Widget> _paddedCells(
  AnnotatedNode row,
  int columnCount,
  Widget Function(AnnotatedNode) childBuilder,
) {
  final cells = <Widget>[];

  for (final cell in row.content ?? const []) {
    cells.add(childBuilder(cell));

    final colspan = cell.attrs?[NodeAttr.colspan];
    if (colspan is int && colspan > 1) {
      cells.addAll(
        List.filled(colspan - 1, const _EmptyTableCell()),
      );
    }
  }

  while (cells.length < columnCount) {
    cells.add(const _EmptyTableCell());
  }

  /// A row longer than the widest count should be impossible, but trimming
  /// keeps Table from throwing on a malformed document.
  return cells.length > columnCount ? cells.sublist(0, columnCount) : cells;
}

// -----------------------------------------------------------------------------
// Table row
// -----------------------------------------------------------------------------

/// Rows are normally consumed by [_buildTable], which needs [TableRow]
/// objects rather than widgets. This builder covers a row dispatched outside a
/// table — a malformed document or a rendered fragment — by laying its cells
/// out in a Row so the content is still visible.
Widget _buildTableRow(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final cells = node.content ?? const [];
  if (cells.isEmpty) return const SizedBox.shrink();

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final cell in cells) Expanded(child: childBuilder(cell))],
  );
}

// -----------------------------------------------------------------------------
// Table cells
// -----------------------------------------------------------------------------

Widget _buildTableCell(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  return _tableCellContent(node, childBuilder, isHeader: false);
}

Widget _buildTableHeader(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  return _tableCellContent(node, childBuilder, isHeader: true);
}

/// Shared cell body: block children laid out in a column, padded, with a
/// header background when applicable.
///
/// The children go through [childBuilder] rather than being built as a text
/// span, because a cell contains paragraphs. That also means each paragraph
/// inside a cell registers with the position registry on its own and keeps
/// its own alignment and direction attributes.
Widget _tableCellContent(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder, {
  required bool isHeader,
}) {
  final children = node.content ?? const [];

  return Container(
    color: isHeader ? _tableHeaderBackground : null,
    padding: _tableCellPadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (children.isEmpty)
          const SizedBox(height: 0)
        else
          for (final child in children) childBuilder(child),
      ],
    ),
  );
}

/// Filler for a column with no cell of its own — a merged cell's continuation,
/// or a short row padded to the table's width.
class _EmptyTableCell extends StatelessWidget {
  const _EmptyTableCell();

  @override
  Widget build(BuildContext context) {
    /// TableCellVerticalAlignment.top requires a fixed-height child in a row
    /// that has no intrinsic height of its own, so this is a zero-size box
    /// inside the same padding as a real cell.
    return const Padding(
      padding: _tableCellPadding,
      child: SizedBox.shrink(),
    );
  }
}
