import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import ts from 'typescript'
const compile = path => ts.transpileModule(fs.readFileSync(new URL(path, import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.ESNext } }).outputText
const sortUrl = `data:text/javascript;base64,${Buffer.from(compile('../src/utils/listSort.ts')).toString('base64')}`
const source = compile('../src/utils/assignmentsExport.ts').replace("'./listSort'", JSON.stringify(sortUrl))
const { assignmentView, assignmentsExportTable, assignmentAttendanceText, mergeAssignmentCatalogs, mergeAssignmentSnapshot } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const catalogs = { tipos_actividad: [{ id:'t', codigo:'CAPACITACION', nombre:'Capacitación' }], estados: [{id:'p',codigo:'PENDIENTE',nombre:'Pendiente'},{id:'r',codigo:'REALIZADA',nombre:'Realizada'}], colegios:[{id:'c',nombre:'Colegio de prueba'}] }
const filters = {search:'',tipoId:'',estadoId:'',colegioId:'',desde:'',hasta:'',upcomingOnly:false}
const sort = {key:'fecha',direction:'asc'}
const row = (id,fecha,extra={}) => ({id,fecha,hora_inicio:'08:00:00',hora_fin:'08:45:00',tipo_actividad_id:'t',estado_id:'p',colegio_id:'c',asignados_a:['Ana Ñúñez','Luis'],...extra})
const rows = [row('oct','2026-10-31'),row('first','2026-11-01'),row('last','2026-11-30',{colegio_id:null,lugar:'Casa Central',asignados_a:[],asistencia_resumen:{PENDIENTE:2}}),row('dec','2026-12-01')]

test('Noviembre inclusivo: mismas siete columnas, orden y valores del listado',()=>{
 const table=assignmentsExportTable(rows,catalogs,{...filters,desde:'2026-11-01',hasta:'2026-11-30'},sort,'2026-11-15T12:00:00Z')
 assert.equal(table.rows.length,2);assert.equal(table.fileName,'instancias');assert.equal(table.columns.length,7)
 assert.deepEqual(table.rows[0],['Capacitación','Colegio de prueba','Ana Ñúñez\nLuis','01/11/2026','08:00 – 08:45','Pendiente','Sin registros'])
 assert.equal(table.rows[1][1],'Casa Central');assert.equal(table.rows[1][2],'Sin participantes');assert.equal(table.rows[1][6],'2 pendiente')
 assert.match(table.filters,/2026-11-01/);assert.match(table.filters,/2026-11-30/)
})
test('Búsqueda combinada, tipo, colegio y estado conservan el selector existente',()=>{
 assert.deepEqual(assignmentView(rows,catalogs,{...filters,search:'  capacitación ',tipoId:'t',colegioId:'c',estadoId:'p'},sort).ordered.map(r=>r.id),['oct','first','dec'])
 assert.deepEqual(assignmentView(rows,catalogs,{...filters,search:'casa'},sort).ordered.map(r=>r.id),['last'])
 assert.equal(assignmentView(rows,catalogs,{...filters,search:'no existe'},sort).ordered.length,0)
})
test('Por reasignar y Solo próximas mantienen reglas distintas de realizada',()=>{
 const input=[row('rejected','2026-11-01',{por_reasignar:true}),row('done','2026-11-02',{estado_id:'r'}),row('pending','2026-11-03')]
 assert.deepEqual(assignmentView(input,catalogs,{...filters,estadoId:'POR_REASIGNAR'},sort).ordered.map(r=>r.id),['rejected'])
 assert.deepEqual(assignmentView(input,catalogs,{...filters,estadoId:'p'},sort).ordered.map(r=>r.id),['pending'])
 assert.deepEqual(assignmentView(input,catalogs,{...filters,upcomingOnly:true},sort).ordered.map(r=>r.id),['rejected','pending'])
 assert.equal(assignmentsExportTable(input,catalogs,{...filters,estadoId:'POR_REASIGNAR'},sort,'2026-11-15T12:00:00Z').rows[0][5],'Por reasignar')
})
test('Los cuatro órdenes y ambos sentidos coinciden entre selector y archivo sin mutar',()=>{
 const before=structuredClone(rows)
 for(const key of ['fecha','actividad','colegio','participantes'])for(const direction of ['asc','desc']){
  const ordered=assignmentView(rows,catalogs,filters,{key,direction}).ordered
  const table=assignmentsExportTable(rows,catalogs,filters,{key,direction},'2026-11-15T12:00:00Z')
  assert.deepEqual(table.rows.map(r=>r[3]),ordered.map(r=>r.fecha.split('-').reverse().join('/')))
 }
 assert.deepEqual(rows,before)
})
test('La actualización del corte conserva otros meses y retira filas eliminadas del contexto',()=>{
 const f={...filters,desde:'2026-11-01',hasta:'2026-11-30'}
 const merged=mergeAssignmentSnapshot(rows,[row('first','2026-11-01',{asignados_a:['Cambio']})],f)
 assert.deepEqual(merged.map(r=>r.id),['oct','dec','first']);assert.equal(merged[2].asignados_a[0],'Cambio')
})
test('Etiquetas nuevas no borran catálogos previos, sin registros y fechas inválidas',()=>{
 const merged=mergeAssignmentCatalogs(catalogs,{tipos_actividad:[{id:'t',codigo:'CAPACITACION',nombre:'Nombre actualizado'}],estados:[],colegios:[]})
 assert.equal(merged.tipos_actividad[0].nombre,'Nombre actualizado');assert.equal(merged.colegios.length,1)
 assert.equal(assignmentAttendanceText(row('x','2026-11-01',{asistencia_resumen:{PENDIENTE:0,NO_REQUERIDA:1}})),'1 no requerida')
 assert.throws(()=>assignmentsExportTable(rows,catalogs,{...filters,desde:'2026-12-01',hasta:'2026-11-01'},sort,''),/fecha desde/)
})
