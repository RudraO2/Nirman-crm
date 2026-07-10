// Story 8.7 — regression + parity tests for the exceljs import parser.
// Run: npm test   (node --import tsx --test)
//
// The golden values in __fixtures__/expected.json were frozen from a parity run
// that asserted the OLD `xlsx` parser and the NEW `exceljs` parser produced
// byte-for-byte identical ParseResults on every fixture (see __fixtures__/parity.ts,
// removed with the xlsx dependency). These tests lock that behavior in without
// keeping the vulnerable package around.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import ExcelJS from 'exceljs'
import { buildParseResult } from './parse-core'
import { readSheetGrid } from './xlsx-read'
import type { ParseResult } from './types'

const HERE = dirname(fileURLToPath(import.meta.url))
const FX = join(HERE, '__fixtures__')
const golden: Record<string, ParseResult> = JSON.parse(
  readFileSync(join(FX, 'expected.json'), 'utf8')
)

// ── Fixture parity: exceljs parse must equal the frozen xlsx golden (AC-3, AC-7) ──
for (const [file, expected] of Object.entries(golden)) {
  test(`parse ${file} matches golden xlsx output`, async () => {
    const buffer = readFileSync(join(FX, file))
    const result = buildParseResult(await readSheetGrid(buffer))
    assert.deepStrictEqual(result, expected)
  })
}

// ── Error contract preserved exactly (AC-4) ──
test('buildParseResult throws "Excel file is empty" on empty grid', () => {
  assert.throws(() => buildParseResult([]), /^Error: Excel file is empty$/)
})

test('buildParseResult throws "Excel file has no column headers" when header row is blank', () => {
  assert.throws(
    () => buildParseResult([['', '  ', '']]),
    /^Error: Excel file has no column headers$/
  )
})

test('readSheetGrid throws "Excel file has no sheets" on a workbook with no worksheet', async () => {
  const wb = new ExcelJS.Workbook()
  const buf = await wb.xlsx.writeBuffer()
  await assert.rejects(
    () => readSheetGrid(Buffer.from(buf as ArrayBuffer)),
    /^Error: Excel file has no sheets$/
  )
})

test('readSheetGrid gives a clean error for a non-xlsx / legacy .xls / corrupt file', async () => {
  // Not a zip/OOXML container — represents a legacy .xls or garbage upload.
  const bogus = Buffer.from('this is not a spreadsheet', 'utf8')
  await assert.rejects(
    () => readSheetGrid(bogus),
    /Please upload a valid \.xlsx spreadsheet/
  )
})

// ── Export round-trip: exceljs write path mirrors export/download/route.ts (AC-5) ──
test('export workbook round-trips: watermark + A1:Q1 merge + headers + rows', async () => {
  const COLS = [
    'Name', 'Phone', 'Status', 'Source', 'Property Type', 'Location',
    'Budget Min', 'Budget Max', 'Ticket Size', 'Remarks', 'Interest Type',
    'Is Incomplete', 'Visit Date', 'Next Followup At', 'Created At',
    'Assigned Employee', 'Last 3 Timeline Events',
  ]
  const watermark = 'Exported by admin on 2026-07-10 12:00:00 Asia/Kolkata'
  const dataRows: unknown[][] = [
    ['Alice', '9876543210', 'warm', 'Website', 'Apartment', 'Pune',
     5000000, 6000000, '2BHK', 'note', 'buy', false,
     null, null, '2026-07-01', 'Sangeeta', 'called; visited'],
  ]

  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Leads')
  ws.addRow([watermark])
  ws.mergeCells(1, 1, 1, COLS.length)
  ws.addRow(COLS)
  ws.addRows(dataRows)
  const buf = await wb.xlsx.writeBuffer()

  const wb2 = new ExcelJS.Workbook()
  await wb2.xlsx.load(buf as ArrayBuffer)
  const ws2 = wb2.getWorksheet('Leads')
  assert.ok(ws2, 'Leads sheet exists')
  assert.equal(ws2!.getCell('A1').text, watermark)
  // A1:Q1 merge — Q1 is part of the same merged range as A1
  assert.ok(ws2!.getCell('Q1').isMerged, 'Q1 is merged')
  assert.equal(ws2!.getCell('A1').master.address, ws2!.getCell('Q1').master.address)
  // header row
  assert.deepStrictEqual(
    COLS.map((_, i) => ws2!.getRow(2).getCell(i + 1).text),
    COLS
  )
  // data row
  assert.equal(ws2!.getRow(3).getCell(1).text, 'Alice')
  assert.equal(ws2!.getRow(3).getCell(2).text, '9876543210')
})
