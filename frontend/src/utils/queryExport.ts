/** Contrato común: solo celdas proyectadas, sin objetos internos de la API. */
export type ExportFormat = 'xlsx' | 'pdf'
export interface ExportTable {
  title: string
  generatedAt: string
  order: string
  columns: string[]
  rows: string[][]
}

const teal = '246474'
const timestamp = (value: string) => new Date(value).toLocaleString('es-CL', { timeZone: 'America/Santiago' })

export async function createXlsx(table: ExportTable): Promise<Blob> {
  const { default: ExcelJS } = await import('exceljs')
  const book = new ExcelJS.Workbook()
  const sheet = book.addWorksheet(table.title)
  sheet.columns = table.columns.map((header, i) => ({ header, key: String(i), width: [18, 36, 38, 20, 22, 16][i] ?? 25 }))
  // Strings explícitos: ExcelJS nunca recibe objetos formula/hyperlink de texto libre.
  for (const values of table.rows) sheet.addRow(values.map(String))
  sheet.eachRow((row, index) => {
    row.height = index === 1 ? 30 : 32
    row.eachCell({ includeEmpty: true }, cell => {
      cell.numFmt = '@'
      cell.font = { name: 'Arial', size: 11, color: { argb: index === 1 ? 'FF' + teal : 'FF2D3142' }, bold: index === 1 }
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: index === 1 ? 'FFF1F7F7' : 'FFFFFFFF' } }
      cell.alignment = { vertical: 'middle', wrapText: true }
      cell.border = { bottom: { style: 'thin', color: { argb: 'FFD9E6E9' } } }
      if (index > 1 && ['Activo', 'Inactivo'].includes(String(cell.value))) {
        cell.font = { name: 'Arial', size: 11, color: { argb: cell.value === 'Activo' ? 'FF067647' : 'FFB42318' } }
      }
    })
    if (index > 1) row.height = Math.max(32, ...table.rows[index - 2].map((value, i) => Math.ceil(value.length / (sheet.getColumn(i + 1).width ?? 25)) * 16))
  })
  sheet.views = [{ state: 'frozen', ySplit: 1 }]
  sheet.autoFilter = { from: 'A1', to: { row: 1, column: table.columns.length } }
  const info = book.addWorksheet('Consulta')
  info.columns = [{ width: 25 }, { width: 70 }]
  info.addRows([['Vista', table.title], ['Corte del servidor', timestamp(table.generatedAt)], ['Zona horaria', 'America/Santiago'], ['Orden', table.order], ['Registros', table.rows.length]])
  const buffer = await book.xlsx.writeBuffer()
  return new Blob([new Uint8Array(buffer)], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
}

async function fontData(path: string) {
  const response = await fetch(import.meta.env.BASE_URL + 'fonts/' + path)
  if (!response.ok) throw new Error('No fue posible cargar la tipografía del PDF. Vuelve a intentarlo.')
  const bytes = new Uint8Array(await response.arrayBuffer())
  let binary = ''
  for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192))
  return btoa(binary)
}

export async function createPdf(table: ExportTable): Promise<Blob> {
  const [{ jsPDF }, { autoTable }, regular, bold] = await Promise.all([
    import('jspdf'), import('jspdf-autotable'), fontData('NotoSans-Regular.ttf'), fontData('NotoSans-Bold.ttf'),
  ])
  const doc = new jsPDF({ orientation: 'landscape', format: 'a4' })
  doc.addFileToVFS('NotoSans-Regular.ttf', regular)
  doc.addFont('NotoSans-Regular.ttf', 'NotoSans', 'normal')
  doc.addFileToVFS('NotoSans-Bold.ttf', bold)
  doc.addFont('NotoSans-Bold.ttf', 'NotoSans', 'bold')
  doc.setFont('NotoSans', 'bold').setFontSize(17).setTextColor('#' + teal)
  doc.text(table.title, 14, 18)
  doc.setFont('NotoSans', 'normal').setFontSize(9)
  doc.text(`Corte: ${timestamp(table.generatedAt)} · America/Santiago · ${table.rows.length} registros`, 14, 25)
  doc.text(`Orden: ${table.order}`, 14, 31)
  autoTable(doc, {
    head: [table.columns], body: table.rows, startY: 37, margin: { top: 15, bottom: 16, left: 14, right: 14 },
    styles: { font: 'NotoSans', fontSize: 9, cellPadding: 3, overflow: 'linebreak', textColor: '#2D3142', lineColor: '#D9E6E9', lineWidth: 0.15 },
    headStyles: { fillColor: '#F1F7F7', textColor: '#' + teal, fontStyle: 'bold' },
    alternateRowStyles: { fillColor: '#FFFFFF' }, rowPageBreak: 'avoid', showHead: 'everyPage',
    didParseCell: ({ cell, section }) => {
      if (section === 'body' && ['Activo', 'Inactivo'].includes(cell.text.join(''))) cell.styles.textColor = cell.text[0] === 'Activo' ? '#067647' : '#B42318'
    },
  })
  const pages = doc.getNumberOfPages()
  for (let page = 1; page <= pages; page++) {
    doc.setPage(page).setFont('NotoSans', 'normal').setFontSize(8).setTextColor('#5F6E75')
    doc.text(`HuellApp · ${table.title} · Página ${page} de ${pages}`, 14, 202)
  }
  return doc.output('blob')
}

export async function downloadTable(table: ExportTable, format: ExportFormat) {
  if (!table.rows.length) throw new Error('No hay resultados para exportar.')
  const blob = await (format === 'xlsx' ? createXlsx(table) : createPdf(table))
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `huellapp_usuarios_${table.generatedAt.replace(/[^0-9]/g, '').slice(0, 14)}.${format}`
  document.body.append(anchor)
  anchor.click()
  anchor.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 1000)
}
