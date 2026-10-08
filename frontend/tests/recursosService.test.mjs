/**
 * HuellApp · Regresión de contratos HTTP y reglas de creación de asignaciones.
 * Ejecutar: node --experimental-vm-modules --test tests/recursosService.test.mjs
 * Simula sesión y transporte; no requiere credenciales ni una base Supabase.
 */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import ts from 'typescript'

const serviceDirectory = fileURLToPath(new URL('../src/services/', import.meta.url))

test('Quitar participante archiva solo la participación elegida mediante la API', async () => {
  const { service, requests } = await harness('asignacionesService')
  await service.removeParticipante('assignment', 'participant')
  assert.equal(requests[0].method, 'DELETE')
  assert.equal(requests[0].url, 'https://test.local/asignaciones/assignment/participantes/participant')
  assert.equal(requests[0].headers.Authorization, 'Bearer test-session')
})

test('Agregar participantes sucesivos no reemplaza a los existentes', async () => {
  const { service, requests } = await harness('asignacionesService')
  await service.getOpcionesParticipantes()
  await service.addParticipante('assignment', 'monitor-2', 'relator')
  await service.addParticipante('assignment', 'monitor-3', 'relator')
  assert.equal(requests[0].url, 'https://test.local/catalogos/asignaciones/gestion-participantes')
  for (const [index, usuario] of [[1, 'monitor-2'], [2, 'monitor-3']]) {
    assert.equal(requests[index].method, 'POST')
    assert.equal(requests[index].url, 'https://test.local/asignaciones/assignment/participantes')
    assert.deepEqual(JSON.parse(requests[index].body), { usuario_id: usuario, tipo_participacion_id: 'relator' })
  }
})

test('Reasignación usa el participante anterior y envía solo el usuario nuevo', async () => {
  const { service, requests } = await harness('asignacionesService')
  await service.getMonitoresReasignacion()
  await service.reassignParticipante('assignment', 'old-participant', 'new-monitor')
  assert.equal(requests[0].url, 'https://test.local/catalogos/asignaciones/reasignacion/participantes')
  assert.equal(requests[1].method, 'POST')
  assert.equal(requests[1].url, 'https://test.local/asignaciones/assignment/participantes/old-participant/reasignar')
  assert.deepEqual(JSON.parse(requests[1].body), { nuevo_usuario_id: 'new-monitor' })
})

test('Eliminar asignación usa DELETE autenticado y acepta 204 sin cuerpo', async () => {
  const { service, requests } = await harness('asignacionesService', { status: 204 })
  await service.deleteAsignacion('assignment')
  assert.equal(requests[0].method, 'DELETE')
  assert.equal(requests[0].url, 'https://test.local/asignaciones/assignment')
})

test('Edición envía PATCH y consulta catálogos bajo permisos de edición', async () => {
  const { service, requests } = await harness('asignacionesService')
  await service.updateAsignacion('assignment', { fecha: '2026-12-01' })
  await service.getOpcionesEdicion()
  await service.getColegioEdicion('school')
  await service.getEspaciosEdicion('subject')
  assert.equal(requests[0].method, 'PATCH')
  assert.deepEqual(JSON.parse(requests[0].body), { fecha: '2026-12-01' })
  assert.equal(requests[1].url, 'https://test.local/catalogos/asignaciones/edicion')
  assert.equal(requests[2].url, 'https://test.local/catalogos/asignaciones/edicion/colegios/school')
  assert.equal(requests[3].url, 'https://test.local/catalogos/asignaciones/edicion/ramos/subject/espacios')
})

test('PATCH de observación no reenvía contexto ni participantes; hora equivalente no cuenta como cambio', async () => {
  const { service } = await harness('../components/asignaciones/asignacionEdicion')
  const original = { ...meeting(), hora_inicio: '09:00:00', hora_fin: '10:00:00', observacion: null }
  const changes = service.cambiosEdicion(original, { ...original, hora_inicio: '09:00', observacion: 'Nueva observación' })
  assert.deepEqual(JSON.parse(JSON.stringify(changes)), { observacion: 'Nueva observación' })
  const moved = service.cambiosEdicion(original, { ...original, colegio_id: 'other', curso_colegio_id: null, sala_id: null, contactos: [{ contacto_colegio_id: 'new' }] })
  assert.deepEqual(JSON.parse(JSON.stringify(moved)), { colegio_id: 'other', curso_colegio_id: null, sala_id: null, contactos: [{ contacto_colegio_id: 'new' }] })
})

test('Respuesta propia usa sesión y no permite enviar actor ni canal desde la interfaz', async () => {
  const { service, requests } = await harness('participacionesService')
  await service.getMiParticipacion('assignment/id')
  await service.responderMiParticipacion('assignment', { accion: 'REJECT', motivo: 'No disponible' })
  assert.equal(requests[0].url, 'https://test.local/mi-participacion/assignment%2Fid')
  assert.deepEqual(JSON.parse(requests[1].body), { accion: 'REJECT', motivo: 'No disponible' })
  assert.equal(requests[1].headers.Authorization, 'Bearer test-session')
})

test('El correo consulta sin responder y mantiene el token fuera de la URL de la API', async () => {
  const { service, requests } = await harness('participacionesService')
  await service.consultarInvitacion('personal-token')
  assert.equal(requests[0].url, 'https://test.local/invitaciones/consultar')
  assert.equal(requests[0].headers.Authorization, undefined)
  assert.equal(requests[0].referrerPolicy, 'no-referrer')
  assert.deepEqual(JSON.parse(requests[0].body), { token: 'personal-token' })
  await service.responderInvitacion('personal-token', { accion: 'ACCEPT', motivo: null })
  assert.equal(requests[1].url, 'https://test.local/invitaciones/responder')
  assert.deepEqual(JSON.parse(requests[1].body), { token: 'personal-token', accion: 'ACCEPT', motivo: null })
})

test('Catálogo académico envía niveles compartidos, padre fijo y operaciones auditables a la API', async () => {
  const { service, requests } = await harness('catalogoAcademicoService')
  await service.getCatalogoAcademico()
  await service.createRecursoAcademico('asignaturas', { nombre: 'Matemática', descripcion: null, nivel_ids: ['primero', 'segundo'] })
  await service.updateRecursoAcademico('encuentro', 'space/id', { nombre: 'Encuentro 1', descripcion: null, ramo_id: 'subject', orden: 1 })
  await service.setRecursoAcademicoActivo('asignaturas', 'subject', false)
  await service.setRecursoAcademicoActivo('reflexion', 'space', true)
  assert.equal(requests[0].url, 'https://test.local/catalogo-academico')
  assert.deepEqual(JSON.parse(requests[1].body).nivel_ids, ['primero', 'segundo'])
  assert.equal(requests[2].method, 'PUT')
  assert.equal(requests[2].url, 'https://test.local/catalogo-academico/encuentro/space%2Fid')
  assert.equal(JSON.parse(requests[2].body).ramo_id, 'subject')
  assert.equal(requests[3].url, 'https://test.local/catalogo-academico/asignaturas/subject/deactivate')
  assert.equal(requests[4].url, 'https://test.local/catalogo-academico/reflexion/space/activate')
})

test('El catálogo utiliza eliminación lógica HTTP 204 sin leer un cuerpo vacío', async () => {
  const { service, requests } = await harness('catalogoAcademicoService', { response: { ok: true, status: 204, json: () => { throw new Error('No hay cuerpo') } } })
  await service.deleteRecursoAcademico('asignaturas', 'subject')
  assert.equal(requests[0].method, 'DELETE')
  assert.equal(requests[0].url, 'https://test.local/catalogo-academico/asignaturas/subject')
})

/** Carga los servicios reales, reemplazando solamente Auth y fetch. */
async function harness(name, { session = { access_token: 'test-session' }, response = { ok: true, status: 200, json: async () => ({ id: 'resource' }) } } = {}) {
  const requests = []
  const clone = () => ({ ...response, clone })
  const context = vm.createContext({ Headers, fetch: async (url, options) => { requests.push({ url, ...options }); return clone() } })
  const cache = new Map()
  const auth = new vm.SyntheticModule(['supabase'], function () {
    this.setExport('supabase', { auth: { getSession: async () => ({ data: { session }, error: null }) } })
  }, { context })
  function load(filename) {
    if (cache.has(filename)) return cache.get(filename)
    const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
    }).outputText
    const module = new vm.SourceTextModule(source, {
      context, identifier: filename,
      initializeImportMeta: (meta) => { meta.env = { VITE_API_URL: 'https://test.local/' } },
    })
    cache.set(filename, module)
    return module
  }
  const module = load(path.join(serviceDirectory, `${name}.ts`))
  await module.link((specifier, parent) => specifier === './supabase'
    ? auth : load(path.resolve(path.dirname(parent.identifier), `${specifier}.ts`)))
  await module.evaluate()
  return { service: module.namespace, requests }
}

test('Cursos filtra por colegio y fija el colegio de creación desde el contexto', async () => {
  const { service, requests } = await harness('cursosService')
  await service.listCursos('school/context')
  await service.createCurso('school-context', { nivel_curso_id: 'level', seccion: 'A', anio: 2026, colegio_id: 'wrong' })
  assert.equal(requests[0].url, 'https://test.local/cursos?colegio_id=school%2Fcontext')
  assert.deepEqual(JSON.parse(requests[1].body), { nivel_curso_id: 'level', seccion: 'A', anio: 2026, colegio_id: 'school-context' })
  assert.equal(requests[1].headers.Authorization, 'Bearer test-session')
})

test('Cursos reutiliza PATCH de edición y rutas de cambio de estado', async () => {
  const { service, requests } = await harness('cursosService')
  await service.updateCurso('course', { seccion: 'B' })
  await service.setCursoActivo('course', false)
  await service.setCursoActivo('course', true)
  await service.getNivelesCurso()
  assert.deepEqual(JSON.parse(requests[0].body), { seccion: 'B' })
  assert.deepEqual(requests.slice(0, 3).map((item) => item.method), ['PATCH', 'PATCH', 'PATCH'])
  assert.equal(requests[1].url, 'https://test.local/cursos/course/deactivate')
  assert.equal(requests[2].url, 'https://test.local/cursos/course/activate')
  assert.equal(requests[3].url, 'https://test.local/catalogos/niveles-curso')
})

test('Salas conserva campos opcionales null y respuestas de estado confirmadas', async () => {
  const { service, requests } = await harness('salasService')
  await service.listSalas('school')
  const saved = await service.createSala('school', { nombre: 'Sala', descripcion: null, capacidad: null, ubicacion: null })
  await service.updateSala('room', { capacidad: null })
  await service.setSalaActivo('room', true)
  await service.setSalaActivo('room', false)
  assert.equal(saved.id, 'resource')
  assert.equal(requests[0].url, 'https://test.local/salas?colegio_id=school')
  assert.equal(JSON.parse(requests[1].body).colegio_id, 'school')
  assert.deepEqual(JSON.parse(requests[2].body), { capacidad: null })
  assert.equal(requests[3].url, 'https://test.local/salas/room/activate')
  assert.equal(requests[4].url, 'https://test.local/salas/room/deactivate')
})

test('DELETE 204 no intenta leer JSON y no envía un borrado directo a Supabase', async () => {
  for (const [name, remove] of [['cursosService', 'deleteCurso'], ['salasService', 'deleteSala']]) {
    const { service, requests } = await harness(name, { response: { ok: true, status: 204, json: () => { throw new Error('No hay JSON en 204') } } })
    assert.equal(await service[remove]('id/to-delete'), undefined)
    assert.equal(requests[0].method, 'DELETE')
    assert.ok(requests[0].url.endsWith('/id%2Fto-delete'))
  }
})

test('Conflictos del backend y errores Pydantic se conservan para la interfaz', async () => {
  for (const [detail, expected] of [['Tiene asignaciones futuras.', 'Tiene asignaciones futuras.'], [[{ msg: 'Sección inválida' }], 'Sección inválida']]) {
    const { service } = await harness('salasService', { response: { ok: false, status: 409, json: async () => ({ detail }) } })
    await assert.rejects(() => service.deleteSala('room'), { message: expected })
  }
})

test('Una sesión ausente no genera solicitudes de escritura', async () => {
  const { service, requests } = await harness('cursosService', { session: null })
  await assert.rejects(() => service.deleteCurso('course'), /Inicia sesión/)
  assert.equal(requests.length, 0)
})

/** Payload escolar mínimo; los UUID de pruebas solo circulan por el transporte simulado. */
const meeting = () => ({
  tipo_actividad_id: 'activity', colegio_id: 'school', curso_colegio_id: null, sala_id: null,
  ramo_id: null, espacio_reflexion_id: null, espacio_encuentro_id: null,
  fecha: '2026-10-07', hora_inicio: '09:00', hora_fin: '10:00', lugar: null, observacion: null,
  participantes: [{ usuario_id: 'user', tipo_participacion_id: 'participation' }],
  contactos: [{ contacto_colegio_id: 'contact' }],
})

test('Asignaciones reutiliza POST, GET y las opciones dependientes del backend', async () => {
  const { service, requests } = await harness('asignacionesService')
  await service.listAsignaciones()
  await service.getAsignacion('assignment/id')
  await service.createAsignacion(meeting())
  await service.getOpcionesColegio('school/id')
  await service.getOpcionesEspacios('subject/id')
  assert.equal(requests[0].url, 'https://test.local/asignaciones')
  assert.equal(requests[1].url, 'https://test.local/asignaciones/assignment%2Fid')
  assert.equal(requests[2].method, 'POST')
  assert.deepEqual(JSON.parse(requests[2].body), meeting())
  assert.equal(requests[3].url, 'https://test.local/catalogos/asignaciones/colegios/school%2Fid')
  assert.equal(requests[4].url, 'https://test.local/catalogos/asignaciones/ramos/subject%2Fid/espacios')
  assert.equal(JSON.parse(requests[2].body).estado_id, undefined)
  assert.equal(JSON.parse(requests[2].body).actor_user_id, undefined)
})

test('Los cinco tipos de actividad aceptan sus combinaciones válidas', async () => {
  const { service } = await harness('../components/asignaciones/asignacionForm')
  assert.equal(service.validarAsignacion(meeting(), 'REUNION'), null)
  for (const [codigo, espacio] of [['ESPACIO_REFLEXION', 'espacio_reflexion_id'], ['ESPACIO_ENCUENTRO', 'espacio_encuentro_id']]) {
    assert.equal(service.validarAsignacion({ ...meeting(), curso_colegio_id: 'course', sala_id: 'room', ramo_id: 'subject', [espacio]: 'space' }, codigo), null)
  }
  for (const codigo of ['CAPACITACION', 'EVENTO_CASA_CENTRAL']) {
    assert.equal(service.validarAsignacion({ ...meeting(), colegio_id: null, contactos: [], lugar: 'Casa Central' }, codigo), null)
  }
})

test('Las reglas bloquean participantes duplicados, contactos excesivos y horarios inválidos', async () => {
  const { service } = await harness('../components/asignaciones/asignacionForm')
  assert.match(service.validarAsignacion({ ...meeting(), participantes: [] }, 'REUNION'), /participante/)
  assert.match(service.validarAsignacion({ ...meeting(), participantes: [meeting().participantes[0], meeting().participantes[0]] }, 'REUNION'), /repetir/)
  assert.equal(service.validarAsignacion({ ...meeting(), contactos: [1, 2, 3, 4].map((n) => ({ contacto_colegio_id: `${n}` })) }, 'REUNION'), null)
  assert.match(service.validarAsignacion({ ...meeting(), hora_fin: '08:00' }, 'REUNION'), /posterior/)
  assert.match(service.validarAsignacion({ ...meeting(), contactos: [] }, 'REUNION'), /contacto/)
})

test('Los campos de otros tipos de actividad no pueden mezclarse en el payload', async () => {
  const { service } = await harness('../components/asignaciones/asignacionForm')
  assert.match(service.validarAsignacion({ ...meeting(), lugar: 'Lugar' }, 'REUNION'), /lugar independiente/)
  assert.match(service.validarAsignacion({ ...meeting(), ramo_id: 'subject' }, 'REUNION'), /ramo/)
  assert.match(service.validarAsignacion({ ...meeting(), lugar: 'Lugar' }, 'CAPACITACION'), /contexto escolar/)
  assert.match(service.validarAsignacion({ ...meeting(), curso_colegio_id: 'course', sala_id: 'room', ramo_id: 'subject', espacio_encuentro_id: 'space' }, 'ESPACIO_REFLEXION'), /reflexión/)
})
