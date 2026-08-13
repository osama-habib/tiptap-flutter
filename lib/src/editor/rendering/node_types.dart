// Constants for ProseMirror node types, mark types, and their attribute keys.
//
// These are a rendering-layer concern, kept separate from the protocol
// constants: they name the document-model vocabulary the renderer dispatches
// on, not the message envelope. The values match the names the engine's
// schema inspector and state serializer emit for the StarterKit + Image build.
//
// These classes are declared abstract with a private constructor so they group
// string constants under a typed name without being instantiable.

/// ProseMirror node type names, as they appear in the `type` field of an
/// annotated node emitted by the engine's serializer.
///
/// The set matches the fixed StarterKit + Image extension build. Unknown
/// types fall through to a debug placeholder, so this list need not be
/// exhaustive for the renderer to remain safe.
abstract class NodeType {
  NodeType._();

  /// The document root node. Always the top of the annotated tree.
  static const String doc = 'doc';

  static const String paragraph = 'paragraph';
  static const String heading = 'heading';
  static const String bulletList = 'bulletList';
  static const String orderedList = 'orderedList';
  static const String listItem = 'listItem';
  static const String blockquote = 'blockquote';
  static const String codeBlock = 'codeBlock';
  static const String horizontalRule = 'horizontalRule';
  static const String image = 'image';

  /// A leaf text node. Carries `text` and optional `marks`, no children.
  static const String text = 'text';

  /// A hard line break within inline content, rendered as a newline.
  static const String hardBreak = 'hardBreak';

  /// A table. Contains only [tableRow] children.
  static const String table = 'table';

  /// A row within a [table]. Contains [tableCell] and [tableHeader] children.
  static const String tableRow = 'tableRow';

  /// A body cell within a [tableRow].
  ///
  /// A cell holds *block* content — paragraphs, not inline text — so its
  /// children go through the normal node dispatch rather than being built as
  /// a single text span.
  static const String tableCell = 'tableCell';

  /// A header cell within a [tableRow]. Structurally identical to
  /// [tableCell]; the difference is presentational.
  static const String tableHeader = 'tableHeader';
}

/// ProseMirror mark type names, as they appear in the `type` field of a mark
/// on a text node.
///
/// Any mark type outside this set is ignored by the renderer rather than
/// causing an error.
abstract class MarkType {
  MarkType._();

  static const String bold = 'bold';
  static const String italic = 'italic';
  static const String strike = 'strike';
  static const String underline = 'underline';
  static const String code = 'code';
  static const String link = 'link';
}

/// Attribute keys read from a node's `attrs` map during rendering.
abstract class NodeAttr {
  NodeAttr._();

  /// Heading level (1â€“6).
  static const String level = 'level';

  /// Ordered-list starting number.
  static const String start = 'start';

  /// Code-block language identifier.
  static const String language = 'language';

  /// Image source: a URL or a base64 data URI.
  static const String src = 'src';

  /// Image alternative text.
  static const String alt = 'alt';

  /// Image title, rendered as a caption.
  static const String title = 'title';

  /// Stable node identifier, from the UniqueID extension.
  ///
  /// The renderer does not use it, but it is named here because it is the
  /// handle a host uses to address one block — scoping an edit to a selection,
  /// or reconciling a change against a single clause.
  static const String id = 'id';

  /// Block alignment: `left`, `center`, `right`, or `justify`.
  static const String textAlign = 'textAlign';

  /// Block writing direction: `ltr` or `rtl`. Absent means inherit.
  static const String dir = 'dir';

  /// Whether the block's direction was set explicitly by the author.
  ///
  /// Carried for round-trip fidelity only. Rendering does not branch on it:
  /// an explicit `rtl` renders right-to-left whether or not it was locked.
  static const String dirLocked = 'dirLocked';

  /// Number of columns a table cell spans.
  static const String colspan = 'colspan';

  /// Number of rows a table cell spans.
  static const String rowspan = 'rowspan';

  /// Per-column widths on a table cell, in logical pixels.
  ///
  /// Emitted by the engine as a list because a merged cell spans several
  /// columns and carries a width for each.
  static const String colwidth = 'colwidth';
}

/// Attribute keys read from a mark's `attrs` map during rendering.
abstract class MarkAttr {
  MarkAttr._();

  /// Link destination URL, carried on a `link` mark.
  static const String href = 'href';
}
