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
const row = (id,fecha,extra={}) => ({id,fecha,hora_inicio:'08:00:00',hora_fin:'08:45:00',tipo_actividad_id:'t',estado_id:'p',colegio_id:'c',asignados_a:['Ana Ñúñez','Luis'],monitores:[{id:'m1',nombre:'Ana Ñúñez'},{id:'m2',nombre:'Luis'}],coordinadores:[{id:'c1',nombre:'Elena Coordinación'}],curso_colegio_id:'course1',curso_nombre:'7° A',...extra})
const rows = [row('oct','2026-10-31'),row('first','2026-11-01'),row('last','2026-11-30',{colegio_id:null,lugar:'Casa Central',asignados_a:[],monitores:[],asistencia_resumen:{PENDIENTE:2}}),row('dec','2026-12-01')]

test('Noviembre inclusivo: mismas siete columnas, orden y valores del listado',()=>{
 const table=assignmentsExportTable(rows,catalogs,{...filters,desde:'2026-11-01',hasta:'2026-11-30'},sort,'2026-11-15T12:00:00Z')
 assert.equal(table.rows.length,2);assert.equal(table.fileName,'instancias');assert.equal(table.columns.length,7)
 assert.deepEqual(table.rows[0],['Capacitación','Colegio de prueba','Ana Ñúñez\nLuis','01/11/2026','08:00 – 08:45','Pendiente','Sin registros'])
 assert.equal(table.rows[1][1],'Casa Central');assert.equal(table.rows[1][2],'Sin monitor');assert.equal(table.rows[1][6],'2 pendiente')
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
test('Los órdenes disponibles y ambos sentidos coinciden entre selector y archivo sin mutar',()=>{
 const before=structuredClone(rows)
 for(const key of ['fecha','actividad','colegio','participantes','coordinadores','monitores'])for(const direction of ['asc','desc']){
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


test('Los filtros de coordinador, monitor y curso se combinan en pantalla y exportación',()=>{
 const input=[row('a','2026-11-01'),row('b','2026-11-02',{coordinadores:[{id:'c2',nombre:'José'}]}),row('c','2026-11-03',{monitores:[{id:'m3',nombre:'Otro'}]}),row('d','2026-11-04',{curso_colegio_id:'course2'})]
 const selected={...filters,coordinadorId:'c1',monitorId:'m1',cursoId:'course1'}
 assert.deepEqual(assignmentView(input,catalogs,selected,sort).ordered.map(r=>r.id),['a'])
 const result=assignmentsExportTable(input,catalogs,selected,{key:'coordinadores',direction:'desc'},'2026-11-17T12:00:00Z',true)
 assert.equal(result.rows.length,1);assert.equal(result.columns.length,8)
 assert.deepEqual(result.columns,['Actividad','Colegio / Lugar','Coordinador','Monitor','Fecha','Horario','Estado','Asistencia'])
 assert.equal(result.rows[0][2],'Elena Coordinación');assert.equal(result.rows[0][3],'Ana Ñúñez\nLuis')
 assert.match(result.filters,/Coordinador: Elena Coordinación/);assert.match(result.filters,/Monitor: Ana Ñúñez/);assert.match(result.filters,/Curso: 7° A/)
 assert.equal(result.order,'Coordinador descendente')
 assert.deepEqual(assignmentView(input,catalogs,{...filters,monitorId:'noexiste'},sort).ordered,[])
})
test('Columnas de Superadmin y Coordinación coinciden con su tabla sin Coordinador',()=>{
 const result=assignmentsExportTable([rows[0]],catalogs,filters,{key:'monitores',direction:'asc'},'2026-11-17T12:00:00Z',false)
 assert.equal(result.columns.length,7);assert.equal(result.columns[2],'Monitor');assert.ok(!result.columns.includes('Coordinador'))
 assert.equal(result.order,'Monitor ascendente')
})
test('Búsqueda por palabras sin tildes conserva nombres, curso, fecha y estado de develop',()=>{
 for(const search of ['coordinacion ana','7° 01/11/2026','nunez pendiente','08:00 capacitacion'])
  assert.deepEqual(assignmentView([rows[1]],catalogs,{...filters,search},sort).ordered.map(r=>r.id),['first'])
})
test('Actualizar el corte de un monitor/coordinador/curso conserva las otras selecciones',()=>{
 const otherCoordinator=row('b','2026-11-01',{coordinadores:[{id:'c2',nombre:'Otra'}]})
 const otherMonitor=row('c','2026-11-01',{monitores:[{id:'m3',nombre:'Otro'}]})
 const otherCourse=row('d','2026-11-01',{curso_colegio_id:'course2'})
 const input=[rows[1],otherCoordinator,otherMonitor,otherCourse]
 const result=mergeAssignmentSnapshot(input,[],{...filters,coordinadorId:'c1',monitorId:'m1',cursoId:'course1'})
 assert.deepEqual(result.map(r=>r.id),['b','c','d'])
})
