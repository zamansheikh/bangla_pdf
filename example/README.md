# Bangla PDF Example

This example demonstrates how to use the **bangla_pdf** package to generate PDFs with mixed Bangla and English text.

## Getting Started

1. Ensure you have Flutter installed and set up.
2. Navigate to the example directory:
   ```bash
   cd example
   ```
3. Get dependencies:
   ```bash
   flutter pub get
   ```
4. Run the example app:
   ```bash
   flutter run
   ```

## Features Demonstrated

The example showcases all the key widgets provided by the bangla_pdf package:

### 1. **Text Widget** - Simple Text with Auto-Detection
Automatically detects and renders mixed Bangla and English text with appropriate fonts.

```dart
Text(
  'Hello বাংলাদেশ World!',
  fontSize: 20,
);
```

### 2. **Header Widget** - Bold Headers
Displays bold, large text perfect for titles and headings.

```dart
Header('আমরা বাংলাদেশ ভালোবাসি');
```

### 3. **Paragraph Widget** - Text Blocks
Formats text in paragraph form with appropriate spacing.

```dart
Paragraph('This is a paragraph with mixed text: আমি প্রোগ্রামিং পছন্দ করি।');
```

### 4. **Table Widget** - Data Tables
Renders tables with mixed Bangla and English content in cells.

```dart
Table(
  data: [
    ['Name', 'Country'],
    ['Zaman', 'বাংলাদেশ'],
  ],
);
```

### 5. **BulletList Widget** - Bullet Points
Creates bullet lists with mixed language support.

```dart
BulletList(
  items: [
    'First item',
    'দ্বিতীয় আইটেম',
    'Mixed বাংলা এবং English',
  ],
);
```

## Code Example

See `lib/services/demo_pdf.dart` for a complete working example of all widgets in action.

## Key Features

- ✅ **No Initialization Required** - Default font is embedded and loads automatically
- ✅ **Auto-Detection** - Automatically detects and applies correct fonts to Bangla text
- ✅ **Custom Fonts** - Support for custom Bangla fonts via the `banglaFont` parameter
- ✅ **Native Feel** - Uses standard widget names like `Text`, `Table`, etc.
- ✅ **Mixed Text Support** - Seamlessly handles mixed Bangla and English in any widget

## More Information

For more details about the bangla_pdf package, visit:
- [Package Documentation](https://pub.dev/packages/bangla_pdf)
- [GitHub Repository](https://github.com/zamansheikh/bangla_pdf)
