import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
import ts from 'typescript'
import ExcelJS from 'exceljs'
const require = createRequire(import.meta.url)
const source = ts.transpileModule(fs.readFileSync(new URL('../src/utils/queryExport.ts', import.meta.url), 'utf8'), {compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText
  .replace("'exceljs'",JSON.stringify(pathToFileURL(require.resolve('exceljs')).href))
const {createXlsx,downloadTable}=await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const table={title:'Usuarios',generatedAt:'2026-11-15T12:00:00Z',order:'Nombre ascendente',columns:['RUT','Nombre','Correo','Teléfono','Rol','Estado'],rows:[['001-9','Ana Ñúñez','=SUM(A1:A2)','+56900000000','Monitor','Activo']]}

test('Usuarios conserva seis columnas, nombre de descarga y textos después de generalizar',async()=>{
 const book=new ExcelJS.Workbook();await book.xlsx.load(await (await createXlsx(table)).arrayBuffer())
 const sheet=book.getWorksheet('Usuarios');assert.equal(sheet.columnCount,6);assert.equal(sheet.getCell('A2').value,'001-9');assert.equal(sheet.getCell('C2').type,ExcelJS.ValueType.String);assert.equal(sheet.getCell('D2').value,'+56900000000')
 const anchor={click(){},remove(){}};globalThis.document={createElement:()=>anchor,body:{append(){}}};globalThis.window={setTimeout:fn=>fn()}
 try{await downloadTable(table,'xlsx');assert.match(anchor.download,/^huellapp_usuarios_.*\.xlsx$/)}finally{delete globalThis.document;delete globalThis.window}
})
test('Instancias agrega siete columnas, filtros, anchos y altura para nombres múltiples',async()=>{
 const data={...table,title:'Instancias',filters:'Desde 2026-11-01 hasta 2026-11-30',columnWidths:[28,30,38,16,22,20,32],columns:['Actividad','Colegio / Lugar','Asignada a','Fecha','Horario','Estado','Asistencia'],rows:[['Capacitación','Casa Central','Ana\nPedro\nLuis','01/11/2026','08:00 – 08:45','Pendiente','3 pendiente']]}
 const book=new ExcelJS.Workbook();await book.xlsx.load(await (await createXlsx(data)).arrayBuffer());const sheet=book.getWorksheet('Instancias');assert.equal(sheet.columnCount,7);assert.equal(sheet.getCell('C2').value,'Ana\nPedro\nLuis');assert.ok(sheet.getRow(2).height>=48);assert.equal(sheet.getColumn(3).width,38);assert.equal(book.getWorksheet('Consulta').getRow(6).getCell(2).value,data.filters)
})
