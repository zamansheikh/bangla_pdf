# Real documents

Drop actual PDFs here and `test/real_documents_test.dart` will run against
them. The directory is empty in the repository: these are other people's
documents, often large, and redistributing them is not this package's business.

What they are for is the one thing generated fixtures cannot prove — that the
extractor behaves on files it did not produce. It must never invent text, and
must say plainly when a document has none.

Verified against three PDFs from a Bangladeshi government primary-education
site (a class 3–5 assessment register, a class 1–2 assessment form, and a
learner progress report — 52 pages, 10.6 MB in total). Every one turned out to
be a pure scan: no fonts, one image per page, zero extractable text. All 52
pages were reported as `BanglaTextEncoding.none` with confidence 0 and
`hasImages` true, and the OCR hook was offered every page.
