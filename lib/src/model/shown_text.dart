/// Whitespace in shown text. The canvas is the truth for this rule.
///
/// On the web, several spaces in a row collapse into one (CSS `white-space: normal`) and spaces at the
/// start and end of a line are not shown; Flutter used to show everything as is ("1  Maya"). The rule
/// is the same for every reader: in SHOWN text, runs of whitespace are one space, and there is none at
/// the start or end of the string.
///
/// "Whitespace" here is exactly the four characters of `x-style.layout.shownText.collapsible`
/// (schema 9.18.0, reference implementation `shownTextOf`): U+0020, U+0009, U+000A, U+000D. A line
/// break is a space too: text has no line breaks, and a separate paragraph is a separate widget.
/// A no-break space (U+00A0, U+202F) and other characters are NOT whitespace here: they glue
/// "120 JOD" together, and collapsing them would break money.
///
/// Applied to the string AFTER substitution (literal, binding, template) and translation choice, only
/// for display (labels, hints and a field's error included). What goes to the host (actions, params,
/// writes) and the values of input fields are exempt (`exempt` in the contract), and the label of a
/// progress bar or ring ("3 / 4") writes its own spaces on purpose and does not pass through here.
library;

/// Mirror of `x-style.layout.shownText` (without the address of the `cases` table); checked against
/// the artifact.
const Map<String, Object> kShownTextRules = {
  'collapsible': ['U+0020', 'U+0009', 'U+000A', 'U+000D'],
  'runs': 'collapse-to-one-space',
  'edges': 'trim',
  'preserved': ['U+00A0'],
  'of': 'the-ready-string-after-template-and-translation',
  'appliesTo': [
    'Text',
    'Button.label',
    'Badge.label',
    'ListTile',
    'AppBar.title',
    'NavItem.label',
    'field-labels',
    'field-placeholders',
    'field-helpers',
    'field-errors',
    'accessible-names',
  ],
  'exempt': ['progress-label', 'input-value', 'host-payload'],
  'silent': 'isSilentText-is-wider-the-shown-text-of-a-silent-string-stays-silent',
  'canvas': 'css-white-space-normal-no-pre-on-human-text',
};

final RegExp _shownWhitespace = RegExp(r'[ \t\n\r]+');

/// A string for display: runs of whitespace become one space, and the edges are trimmed.
String collapseShownWhitespace(String text) {
  if (text.isEmpty) return text;
  return text.replaceAll(_shownWhitespace, ' ').replaceAll(RegExp(r'^ | $'), '');
}

/// The same over the runs of composed text: a space at the join of runs (the end of one, the start of
/// the next) is also single. Runs that are empty after trimming are dropped.
List<T> collapseShownRuns<T>(List<T> runs, String Function(T run) textOf, T Function(T run, String text) withText) {
  final result = <T>[];
  var previousEndsWithSpace = true; // start of the string: no space before
  for (final run in runs) {
    var text = textOf(run).replaceAll(_shownWhitespace, ' ');
    if (previousEndsWithSpace && text.startsWith(' ')) text = text.substring(1);
    if (text.isEmpty) continue;
    previousEndsWithSpace = text.endsWith(' ');
    result.add(withText(run, text));
  }
  // End of the string: the trailing space of the last run is not shown.
  while (result.isNotEmpty) {
    final last = textOf(result.last);
    if (!last.endsWith(' ')) break;
    final trimmed = last.substring(0, last.length - 1);
    if (trimmed.isEmpty) {
      result.removeLast();
    } else {
      result[result.length - 1] = withText(result.last, trimmed);
      break;
    }
  }
  return result;
}
