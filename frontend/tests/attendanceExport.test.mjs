import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import ts from 'typescript'
const compile = path => ts.transpileModule(fs.readFileSync(new URL(path, import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.ESNext } }).outputText
const sortUrl = `data:text/javascript;base64,${Buffer.from(compile('../src/utils/listSort.ts')).toString('base64')}`
const source = compile('../src/utils/attendanceExport.ts').replace("'./listSort'", JSON.stringify(sortUrl))
const { attendanceView, attendanceOf, attendancePerson, attendanceState, attendanceExportTable, mergeAttendanceSnapshot } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const filters = {assignment:null,search:'',status:'',from:'',until:''}
const sort = {key:'fecha',direction:'asc'}
const row = (id,fecha,extra={}) => ({id,asignacion_id:'a',usuario_id:'u',estado:{codigo:'ACEPTADA'},usuario:{nombres:'Ana',apellido_paterno:'Ñúñez',apellido_materno:null},asistencia:[{estado:'PRESENTE',direccion_detectada:'Dirección de prueba',latitud:-33,longitud:-70,precision_gps:12.4,motivo:'Texto\ncon salto',motivo_regularizacion:'Revisado'}],asignacion:{fecha,hora_inicio:'08:00:00',hora_fin:'09:00:00',lugar:'Sala',colegio:null,actividad:{nombre:'Reflexión'}},...extra})
const rows = [row('oct','2026-10-31'),row('first','2026-11-01'),row('last','2026-11-30'),row('dec','2026-12-01')]
const table = (input=rows,f=filters,s=sort,personal=false) => attendanceExportTable(input,f,s,'2026-11-15T12:00:00Z',personal)

test('Noviembre inclusivo mantiene siete columnas y excluye acciones/campos internos',()=>{
 const result=table(rows,{...filters,from:'2026-11-01',until:'2026-11-30'})
 assert.equal(result.rows.length,2);assert.equal(result.columns.length,7);assert.equal(result.fileName,'asistencias')
 assert.deepEqual(result.rows[0].slice(0,6),['01/11/2026','Reflexión','Sala','Ana Ñúñez','ACEPTADA','PRESENTE'])
 assert.equal(result.columns.at(-1),'Ubicación / motivo');assert.match(result.rows[0][6],/https:\/\/www.google.com\/maps\?q=-33,-70/)
 assert.match(result.rows[0][6],/±12 m/);assert.match(result.rows[0][6],/Regularización: Revisado/)
 assert.match(result.filters,/2026-11-30/);assert.ok(!result.columns.includes('Acciones'))
})
test('Combina instancia, fechas, estado y búsqueda de participante/colegio/actividad',()=>{
 assert.equal(table(rows,{...filters,assignment:'a',status:'PRESENTE',search:'ñúÑez',from:'2026-11-01',until:'2026-11-30'}).rows.length,2)
 for(const search of ['sala','REFLEXIÓN'])assert.equal(table(rows,{...filters,search}).rows.length,4)
 assert.equal(table(rows,{...filters,assignment:'otra'}).rows.length,0)
 assert.equal(table(rows,{...filters,status:'AUSENTE'}).rows.length,0)
 const school=row('s','2026-11-01');school.asignacion.colegio={nombre:'Colegio de prueba'}
 assert.equal(table([school],{...filters,search:'colegio'}).rows[0][2],'Colegio de prueba')
})
test('Cuatro órdenes en ambos sentidos coinciden con pantalla sin mutar datos',()=>{
 const input=[row('a','2026-11-30'),row('b','2026-11-01',{usuario:{nombres:'Bruno'},asignacion:{fecha:'2026-11-01',hora_inicio:'10:00:00',lugar:'Casa',actividad:{nombre:'Capacitación'}}})]
 const original=structuredClone(input)
 for(const key of ['fecha','actividad','colegio','nombre'])for(const direction of ['asc','desc']){
  const s={key,direction};assert.deepEqual(table(input,filters,s).rows.map(r=>r[0]),attendanceView(input,filters,s).ordered.map(r=>r.asignacion.fecha.split('-').reverse().join('/')))
 }
 assert.deepEqual(input,original)
})
test('Vista personal se identifica en archivo y metadatos, sin cambiar el conjunto recibido',()=>{
 const result=table([rows[0]],filters,sort,true)
 assert.equal(result.title,'Mis asistencias');assert.equal(result.fileName,'mis_asistencias');assert.match(result.filters,/Mis asistencias/);assert.equal(result.rows.length,1)
})
test('Normaliza objeto/lista/vacío y conserva la diferencia entre participación y asistencia',()=>{
 const rejected=row('r','2026-11-01',{estado:{codigo:'RECHAZADA'},asistencia:{estado:'NO_REQUERIDA'}})
 assert.equal(attendanceOf(rejected).estado,'NO_REQUERIDA');assert.equal(attendanceState(rejected),'No requerida')
 assert.deepEqual(table([rejected],{...filters,status:'NO_REQUERIDA'}).rows[0].slice(4,6),['RECHAZADA','No requerida'])
 const empty=row('e','2026-11-01',{asistencia:[],usuario:{nombres:'=HYPERLINK("x")'}})
 assert.equal(attendanceState(empty),'Sin registro');assert.equal(table([empty]).rows[0][6],'');assert.equal(attendancePerson(empty),'=HYPERLINK("x")')
 assert.equal(table([rejected]).rows[0][6],'')
})
test('No inventa precisión y conserva coordenadas cero, motivos y vacíos',()=>{
 const item=row('x','2026-11-01',{asistencia:{estado:'AUSENTE',latitud:0,longitud:0,precision_gps:null,motivo:'=1+1'}})
 assert.match(table([item]).rows[0][6],/q=0,0\nPrecisión: No informada\n=1\+1/)
})
test('Actualiza el contexto consultado y conserva otros meses e instancias sin duplicados',()=>{
 const other=row('other','2026-11-01',{asignacion_id:'otra'})
 const result=mergeAttendanceSnapshot([...rows,other],[row('first','2026-11-01')],{...filters,assignment:'a',from:'2026-11-01',until:'2026-11-30'})
 assert.deepEqual(result.map(r=>r.id),['oct','dec','other','first'])
 assert.deepEqual(mergeAttendanceSnapshot(rows,[],filters),[])
})
test('Rango inválido se rechaza y conjunto vacío se entrega al control compartido',()=>{
 assert.throws(()=>table(rows,{...filters,from:'2026-12-01',until:'2026-11-01'}),/fecha desde/)
 assert.equal(table([]).rows.length,0)
})
