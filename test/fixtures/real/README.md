# Real documents

PDFs this package did not produce, used by `test/real_documents_test.dart`.

Generated fixtures prove the pipeline is self-consistent. They cannot prove
anything about a file written by another tool, years ago, by someone with no
interest in being easy to parse — which is what users actually feed it. That is
what these are for.

The assertions are about **honesty**, not content: the expected text of an
arbitrary document is unknown, so what gets checked is that a document with no
text layer is never given one, that a document with text does not come back
empty, and that nothing throws.

## What is here

Four real government PDFs, kept under their original bytes and renamed only so
the filenames are ASCII. The first three come from a Bangladeshi
government primary-education site:

| file | original title | pages |
|---|---|---|
| `gov-assessment-register-class3-5.pdf` | তৃতীয় চতুর্থ পঞ্চম শ্রেণীর মূল্যায়ন রেজিস্ট্রার – ২০২৬ | 30 |
| `gov-assessment-form-class1-2.pdf` | প্রথম ও দ্বিতীয় শ্রেণীর মূল্যায়ন খাতার ফরম | 18 |
| `gov-learning-progress-report.pdf` | শিক্ষার্থীর শিখন অগ্রগতি রিপোর্ট | 4 |

**All three are pure scans**: no embedded fonts, one image per page, not a byte
of extractable text. That is itself the finding. Documents of this kind cannot
be read by any amount of cleverness about fonts or encodings — OCR is the only
route — and the Bijoy pipeline elsewhere in this package applies to a different
class of file than one might assume is typical of government output.

All 52 pages are reported as `BanglaTextEncoding.none` with confidence 0 and
`hasImages` true, and the OCR hook is offered every page.

The fourth is text-bearing:

| file | original title | pages |
|---|---|---|
| `nctb-assessment-guideline-2026.pdf` | প্রাথমিক স্তরের মূল্যায়ন নির্দেশিকা, ২০২৬ (NCTB) | 56 |

Exported from Word 2013 with NikoshBAN, SutonnyMJ and Vrinda, it is the reason
`test/word_export_test.dart` exists. Word's `/ToUnicode` maps for it exchange
every pair of glyphs Bengali reorders; it draws one glyph per `Tj`, and one text
object per glyph on justified lines; its WinAnsi NikoshBAN subset has no Bengali
cmap entries left; and its SutonnyMJ runs use alternate Bijoy codes. poppler
reads a quarter of its words as malformed; this package reads one in fourteen
thousand. Pages 12–15 are scans stamped with a page number, and are offered to
the OCR hook.

Still missing: a document written *entirely* in Bijoy, the kind where copying
gives `Avgvi ‡mvbvi evsjv` throughout. This one's Bijoy runs are real, but they
are a minority of its text.

## Adding your own

Drop any PDF in this directory and `flutter test` picks it up; the tests skip
when it is empty. Nothing here reaches pub.dev — `.pubignore` excludes
`test/fixtures/` from the published archive.
