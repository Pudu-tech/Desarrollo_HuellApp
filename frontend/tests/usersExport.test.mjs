import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import ts from 'typescript'

const compile = path => ts.transpileModule(fs.readFileSync(new URL(path, import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.ESNext } }).outputText
const sortUrl = `data:text/javascript;base64,${Buffer.from(compile('../src/utils/listSort.ts')).toString('base64')}`
const source = compile('../src/utils/usersExport.ts').replace("'./listSort'", JSON.stringify(sortUrl))
const { usersExportTable } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('Exporta solo las seis columnas visibles, preserva textos y el orden sin mutar', () => {
  const users = [
    { rut: '001-9', nombres: 'Óscar', apellido_paterno: 'Ñúñez', apellido_materno: '', email: '=texto', telefono: '+56900000000', roles: { nombre: 'Monitor' }, activo: false, secret: 'omitido' },
    { rut: '002-7', nombres: 'Ana', apellido_paterno: 'Prueba', apellido_materno: '', email: 'ana@example.org', telefono: null, roles: { nombre: 'Directiva' }, activo: true },
  ]
  const before = structuredClone(users)
  const table = usersExportTable(users, '2026-11-15T12:00:00Z', 'asc')
  assert.deepEqual(table.columns, ['RUT','Nombre','Correo','Teléfono','Rol','Estado'])
  assert.deepEqual(table.rows[0], ['002-7','Ana Prueba','ana@example.org','-','Directiva','Activo'])
  assert.equal(table.rows[1][2], '=texto')
  assert.equal(table.rows[1][3], '+56900000000')
  assert.equal(table.rows[1][5], 'Inactivo')
  assert.equal(table.rows.flat().includes('omitido'), false)
  assert.equal(usersExportTable(users, table.generatedAt, 'desc').rows[0][0], '001-9')
  assert.deepEqual(users, before)
})
