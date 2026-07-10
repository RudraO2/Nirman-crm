// The ONLY Excel-library-specific code on the import path.
// Loads a workbook with exceljs and emits a dense 2-D grid of formatted cell
// text, equivalent to the old
//   XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '', raw: false })
// so that the pure buildParseResult() downstream is byte-for-byte identical to
// the Story 6.1 behavior. exceljs replaces the vulnerable `xlsx` package
// (GHSA-4r6h-8v6p-xvw6 prototype pollution, GHSA-5pgg-2g8v-p4x9 ReDoS).

import ExcelJS from 'exceljs'

/**
 * Read the first worksheet of an .xlsx buffer into a dense grid of strings.
 * Row 0 = first sheet row. Every row is padded to the sheet's max column count,
 * with empty cells as '' — matching xlsx's `defval: ''`. Cell text uses the
 * formatted representation (`cell.text`), matching xlsx's `raw: false`.
 *
 * Throws `Excel file has no sheets` when the workbook has no worksheet, matching
 * the Story 6.1 error contract.
 */
export async function readSheetGrid(buffer: Buffer): Promise<string[][]> {
  const workbook = new ExcelJS.Workbook()
  try {
    // exceljs vendors its own empty `interface Buffer extends ArrayBuffer` which
    // clashes with @types/node's generic `Buffer<ArrayBufferLike>`; structurally
    // it is just an ArrayBuffer, so cast through it. `load` accepts it at runtime.
    await workbook.xlsx.load(buffer as unknown as ArrayBuffer)
  } catch {
    // Legacy .xls (BIFF/OLE) and corrupt files fail here — exceljs reads only
    // the OOXML .xlsx (zip) format, unlike the old `xlsx` package which also
    // parsed .xls. Surface a clean, actionable message instead of a raw
    // zip/parser stack trace.
    throw new Error('Could not read the file. Please upload a valid .xlsx spreadsheet (legacy .xls is not supported).')
  }

  const sheet = workbook.worksheets[0]
  if (!sheet) throw new Error('Excel file has no sheets')

  const rowCount = sheet.rowCount
  const colCount = sheet.columnCount

  const grid: string[][] = []
  for (let r = 1; r <= rowCount; r++) {
    const row = sheet.getRow(r)
    const cells: string[] = []
    for (let c = 1; c <= colCount; c++) {
      const text = row.getCell(c).text
      cells.push(text == null ? '' : String(text))
    }
    grid.push(cells)
  }

  return grid
}
