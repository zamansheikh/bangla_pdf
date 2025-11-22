import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Service class for generating Bangla PDFs.
class BanglaPdfService {
  BanglaPdfService._();

  /// Generates a sample PDF document demonstrating all Bangla widgets.
  ///
  /// Features included:
  /// - Text
  /// - RichText
  /// - Header
  /// - Paragraph
  /// - BulletList
  /// - Table
  ///
  /// Returns a [pw.Document] that can be saved or previewed.
  static Future<pw.Document> generateSamplePdf() async {
    final pdf = pw.Document();

    // Sample table data for Table
    final tableData = [
      ['পণ্য', 'পরিমাণ', 'মূল্য', 'মোট'], // Header
      ['কফি', '2', '\$10', '\$20'],
      ['চা', '1', '\$15', '\$15'],
      ['বিস্কুট', '3', '\$5', '\$15'],
      ['মোট', '', '', '\$50'], // Footer
    ];

    // Add a page to the PDF
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            /// Custom text using BanglaFontManager directly
            Text(
              'বাংলা',
              style: pw.TextStyle(
                fontSize: 24,
                font: BanglaFontManager().defaultFont,
              ),
            ),

            /// Simple Bangla text
            Text(
              'বাংলা সাধারণ টেক্সট',
              fontSize: 20,
            ),

            pw.SizedBox(height: 20),

            /// Bangla rich text with multiple fonts and styles
            RichText(
              spans: [
                TextSpan(
                  'বাংলা বোল্ড ',
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 20,
                  color: PdfColors.red,
                ),
                TextSpan(
                  'এবং ইটালিক',
                  fontSize: 18,
                  color: PdfColors.blue,
                ),
              ],
            ),

            pw.SizedBox(height: 20),

            /// Bangla header
            Header('বাংলা শিরোনাম'),
            pw.SizedBox(height: 10),

            /// Bangla paragraph
            Paragraph('বাংলা অনুচ্ছেদ এখানে লেখা হবে।'),

            pw.SizedBox(height: 20),

            /// Another rich text example
            RichText(
              spans: [
                TextSpan('বাংলা বোল্ড ', fontWeight: pw.FontWeight.bold),
                TextSpan(
                  'এবং ইটালিক',
                ),
              ],
            ),

            /// Bangla bullet list
            Header('বাংলা বুলেট লিস্ট'),
            pw.SizedBox(height: 10),
            BulletList(
              items: [
                'প্রথম আইটেম',
                'দ্বিতীয় আইটেম',
                'তৃতীয় আইটেম',
              ],
            ),

            pw.SizedBox(height: 20),

            /// Bangla table
            Header('বাংলা টেবিল'),
            pw.SizedBox(height: 10),
            Table(
              data: tableData,
              fontSize: 16,
              headerColor: PdfColors.blue,
              borderColor: PdfColors.grey200,
              cellAlignment: pw.Alignment.center,
              cellPadding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 6,
              ),
            ),
          ],
        ),
      ),
    );

    return pdf;
  }
}
