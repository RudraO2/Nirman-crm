// Dev tool: generates the committed .xlsx import fixtures for Story 8.7.
// Run: node src/app/(app)/import/__fixtures__/gen.mjs
// Each fixture exercises a distinct branch of the Story 6.1 import parser.
// `num: true` writes that column's data cells as real numeric cells (not text),
// to test the raw:false / cell.text stringification parity.
import ExcelJS from 'exceljs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const DIR = dirname(fileURLToPath(import.meta.url))

/** @type {{file:string, headers:(string)[], rows:(unknown[])[]}[]} */
const FIXTURES = [
  {
    // All headers auto-map via synonyms; distinct phones.
    file: 'basic-synonyms.xlsx',
    headers: ['Customer Name', 'Mobile', 'Project', 'BHK', 'City', 'Budget', 'Source', 'Notes', 'Property Type'],
    rows: [
      ['Alice Rao', '9876543210', 'Skyline', '2BHK', 'Pune', '50L-60L', 'Website', 'hot lead', 'Apartment'],
      ['Bob Shah', '9876500001', 'Skyline', '3BHK', 'Mumbai', '1Cr', 'Referral', '', 'Villa'],
    ],
  },
  {
    // One header ("Enquiry Ref") matches nothing -> mapping null (manual map needed).
    file: 'unmatched-column.xlsx',
    headers: ['Name', 'Phone', 'Enquiry Ref'],
    rows: [
      ['Carol', '9811100011', 'REF-1'],
      ['Dave', '9811100012', 'REF-2'],
    ],
  },
  {
    // Duplicate phone values within the file -> intraFileDupes > 0.
    file: 'intra-dupes.xlsx',
    headers: ['Name', 'Phone'],
    rows: [
      ['Eve', '9800000001'],
      ['Eve2', '9800000001'],
      ['Frank', '9800000002'],
      ['Frank2', '9800000002'],
      ['Grace', '9800000003'],
    ],
  },
  {
    // Some rows have a blank phone -> missingPhoneCount > 0.
    file: 'missing-phone.xlsx',
    headers: ['Name', 'Phone'],
    rows: [
      ['Heidi', '9700000001'],
      ['Ivan', ''],
      ['Judy', '9700000003'],
      ['Ken', ''],
    ],
  },
  {
    // Phone stored as NUMERIC cells -> tests cell.text vs xlsx raw:false parity.
    file: 'numeric-phone.xlsx',
    headers: ['Name', 'Phone', 'Budget'],
    rows: [
      ['Laura', 9876543210, 5000000],
      ['Mike', 9876543211, 7500000.5],
    ],
    num: { Phone: true, Budget: true },
  },
  {
    // Multiple unknown/extra columns alongside matched ones.
    file: 'extra-columns.xlsx',
    headers: ['Name', 'Phone', 'Foo', 'Bar Baz'],
    rows: [
      ['Nina', '9600000001', 'a', 'b'],
      ['Oscar', '9600000002', 'c', 'd'],
    ],
  },
  {
    // Empty header cell in the middle -> filtered out; exercises the
    // filtered-header-index behavior (preserved exactly from Story 6.1).
    file: 'empty-header.xlsx',
    headers: ['Name', '', 'Phone'],
    rows: [
      ['Peggy', 'ignored-mid', '9500000001'],
      ['Quinn', 'ignored-mid2', '9500000002'],
    ],
  },
  {
    // 15 data rows -> preview truncates to 10, totalRows = 15.
    file: 'many-rows.xlsx',
    headers: ['Name', 'Phone'],
    rows: Array.from({ length: 15 }, (_, i) => [`Person ${i + 1}`, `94000000${String(i + 1).padStart(2, '0')}`]),
  },
]

for (const fx of FIXTURES) {
  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Sheet1')
  ws.addRow(fx.headers)
  for (const row of fx.rows) ws.addRow(row)
  await wb.xlsx.writeFile(join(DIR, fx.file))
  console.log('wrote', fx.file)
}
console.log('done')
