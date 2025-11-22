
## 1.0.3

- **BREAKING**: Removed bundled fonts (except Kalpurush) to reduce package size.
- **BREAKING**: Removed `BanglaFontManager` initialization requirement.
- **BREAKING**: Removed `BanglaFontType` enum. Use `pw.Font` directly for custom fonts.
- **NEW**: `Text` and other widgets now accept `banglaFont` parameter for custom fonts.
- **NEW**: Default font (Kalpurush) is now embedded and loaded automatically.

## 1.0.2

- **NEW**: Added `BanglaAutoText` widget for automatic Bangla and English text mixing
- **ENHANCED**: Updated `BanglaTable` to support mixed Bangla and English content in all cells
- **NEW**: Added support for Bangla Taka symbol (৳) in text rendering
- **FIXED**: Resolved all lint errors - improved code quality and maintainability
- **IMPROVED**: Enhanced Unicode mapping for better character rendering
- **CHANGED**: Switched from Apache 2.0 to MIT License
- **DOCS**: Added comprehensive examples for all widgets with proper documentation

## 1.0.1

- Minor bug fixes and stability improvements.

## 1.0.0

- Initial release of the **Bangla PDF** package 2025-11-20.
- Added support for multiple Bangla fonts.
- Implemented font fixing for PDFs with broken fonts.
- Fixed various issues with font rendering.
