/// A drop-in replacement for `package:pdf/widgets.dart` that renders Bangla
/// correctly.
///
/// Change one import and nothing else:
///
/// ```diff
/// - import 'package:pdf/widgets.dart' as pw;
/// + import 'package:bangla_pdf/widgets.dart' as pw;
/// ```
///
/// Every symbol `package:pdf` exports is re-exported here unchanged, except
/// the widgets that render text. Those are replaced by versions that take
/// exactly the same parameters and shape Bangla with the font's own OpenType
/// tables:
///
/// [Text], [RichText], [TextSpan], [Header], [Paragraph], [Bullet],
/// [TableHelper], [Watermark], [TableOfContent], [ChartLegend], [FixedAxis],
/// [TextField] and [ChoiceField].
///
/// A string with no Bengali in it is handed straight to `package:pdf`, so a
/// document with no Bangla renders exactly as it would without this package.
///
/// Configure the typeface and shaping mode through `BanglaPdf` in
/// `package:bangla_pdf/bangla_pdf.dart`; nothing here needs initialising.
library;

export 'package:bangla_pdf/src/compat/widgets.dart';
export 'package:pdf/widgets.dart'
    hide
        Bullet,
        ChartLegend,
        ChoiceField,
        FixedAxis,
        Header,
        Paragraph,
        RichText,
        TableHelper,
        TableOfContent,
        Text,
        TextField,
        TextSpan,
        Watermark;
