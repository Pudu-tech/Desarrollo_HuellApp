import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { recursoRequest } from '../services/recursosService'
import LoadingIndicator from '../components/LoadingIndicator'
import '../styles/asignaciones.css'
import '../styles/auditoria.css'

type Audit = { id:string; created_at:string; actor_name:string; actor_role:string|null; action:string; entity_type:string; entity_name:string|null; description:string|null; old_values:Record<string,unknown>|null; new_values:Record<string,unknown>|null; source:string; old_display_values?:Record<string,unknown>|null; new_display_values?:Record<string,unknown>|null }
const entities:Record<string,string>={ASSIGNMENT:'Asignaciones',ASSIGNMENT_PARTICIPANT:'Participantes',ATTENDANCE:'Asistencia',USER:'Usuarios',SCHOOL:'Colegios',ROOM:'Salas',COURSE:'Cursos',SCHOOL_CONTACT:'Contactos',SUBJECT:'Asignaturas'}
const actions:Record<string,string>={CREATE_ASSIGNMENT:'Crear asignación',UPDATE_ASSIGNMENT:'Editar asignación',DELETE_ASSIGNMENT:'Eliminar asignación',CONFIRM_ASSIGNMENT:'Confirmar asignación',CANCEL_ASSIGNMENT:'Cancelar asignación',ADD_PARTICIPANT:'Agregar participante',REMOVE_PARTICIPANT:'Quitar participante',REASSIGN_PARTICIPANT:'Cambiar participante',ACCEPT_PARTICIPATION:'Aceptar participación',REJECT_PARTICIPATION:'Rechazar participación',REOPEN_PARTICIPATION:'Reabrir participación',PARTICIPATION_RESPONSE_CHANNEL:'Respuesta por canal',REPORT_ATTENDANCE:'Registrar asistencia',MANAGE_ATTENDANCE:'Regularizar asistencia',CREATE_USER:'Crear usuario',UPDATE_USER:'Editar usuario',DELETE_USER:'Eliminar usuario',CHANGE_USER_ROLE:'Cambiar rol',CREATE_SCHOOL:'Crear colegio',UPDATE_SCHOOL:'Editar colegio',DELETE_SCHOOL:'Eliminar colegio',CREATE_ROOM:'Crear sala',UPDATE_ROOM:'Editar sala',CREATE_COURSE:'Crear curso',UPDATE_COURSE:'Editar curso'}
const fields:Record<string,string>={ramo_id:'Asignatura',sala_id:'Sala',colegio_id:'Colegio',curso_colegio_id:'Curso',tipo_actividad_id:'Tipo de actividad',espacio_reflexion_id:'Espacio de reflexión',espacio_encuentro_id:'Espacio de encuentro',created_at:'Creado el',contactos:'Contactos',participantes:'Participantes',contacto_colegio_id:'Contacto',respondido_por:'Respondido por',registrado_por:'Registrado por',regularizado_por:'Regularizado por',fecha:'Fecha',hora_inicio:'Hora de inicio',hora_fin:'Hora de término',estado:'Estado',activo:'Activo',lugar:'Lugar',observacion:'Observación',motivo:'Motivo',motivo_rechazo:'Motivo del rechazo',motivo_ausencia:'Motivo de ausencia',motivo_regularizacion:'Motivo de regularización',fecha_respuesta:'Fecha de respuesta',nombre:'Nombre',nombres:'Nombres',apellido_paterno:'Apellido paterno',apellido_materno:'Apellido materno',telefono:'Teléfono',email:'Correo',correo:'Correo',canal:'Canal',deleted_at:'Eliminado el',capacidad:'Capacidad',descripcion:'Descripción',ubicacion:'Ubicación',estado_id:'Estado',estado_participacion_id:'Respuesta',usuario_id:'Participante',rol_id:'Rol',tipo_participacion_id:'Tipo de participación'}
const day=(ago=0)=>{const d=new Date();d.setDate(d.getDate()-ago);return new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Santiago'}).format(d)}
const timestamp=(value:string)=>new Date(value).toLocaleString('es-CL',{timeZone:'America/Santiago',dateStyle:'short',timeStyle:'short'})
const friendlyDate = (v: string): string => {
 const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(v)
 const date = new Date(dateOnly ? `${v}T12:00:00-03:00` : v)
 if (Number.isNaN(date.getTime())) return v
 return new Intl.DateTimeFormat('es-CL', {
  timeZone: 'America/Santiago', dateStyle: 'long',
  ...(dateOnly ? {} : { timeStyle: 'short' as const, hour12: false }),
 }).format(date)
}
const value=(v:unknown):string=>v===null||v===undefined?'—':typeof v==='boolean'?v?'Sí':'No':typeof v==='object'?JSON.stringify(v):typeof v==='string'&&/^\d{4}-\d{2}-\d{2}(?:$|T\d{2}:\d{2})/.test(v)?friendlyDate(v):/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(String(v))?'Dato relacionado no disponible':String(v)
const sensitive=(k:string)=>/token|password|secret|credential/i.test(k)
function renderValue(v:unknown, field:string):React.ReactNode {
 if(Array.isArray(v)) return v.length ? <ul className="audit-value-list">{v.map((item,i)=><li key={i}>{renderValue(item,field==='participantes'?'participante':field==='contactos'?'contacto':field)}</li>)}</ul> : 'Sin registros'
 if(v&&typeof v==='object') {
  const obj=v as Record<string,unknown>
  if(field==='contacto') return value(obj.contacto_colegio_id)
  if(field==='participante') return <><strong>{value(obj.usuario_id)}</strong><span className="audit-muted">{value(obj.tipo_participacion_id)} · {value(obj.estado_participacion_id)}{obj.activo===false?' · Retirado':''}</span>{obj.motivo_rechazo&&<span className="audit-muted">Motivo: {value(obj.motivo_rechazo)}</span>}</>
  return <dl className="audit-value-object">{Object.entries(obj).filter(([k])=>k!=='id'&&!sensitive(k)).map(([k,item])=><div key={k}><dt>{fields[k]||k.replaceAll('_',' ')}</dt><dd>{renderValue(item,k)}</dd></div>)}</dl>
 }
 if(typeof v==='string'&&/^hora_/.test(field)&&/^\d{2}:\d{2}/.test(v)) return v.slice(0,5)
 return value(v)
}
export default function AuditoriaPage(){
 const [params,setParams]=useSearchParams()
 const [filters,setFilters]=useState({desde:params.get('asignacion')?'':day(6),hasta:day(),action:'',entity_type:'',actor_user_id:'',actor_role_id:'',search:''})
 const [applied,setApplied]=useState(filters)
 const [page,setPage]=useState(0)
 const [revision,setRevision]=useState(0)
 const [rows,setRows]=useState<Audit[]|null>(null)
 const [error,setError]=useState('')
 const [selected,setSelected]=useState<Audit|null>(null)
 const detailDialog=useRef<HTMLDialogElement>(null)
 useEffect(()=>{
  const dialog=detailDialog.current
  if(!selected||!dialog)return
  const previousOverflow=document.body.style.overflow
  dialog.showModal()
  document.body.style.overflow='hidden'
  return()=>{dialog.close();document.body.style.overflow=previousOverflow}
 },[selected])
 const [options,setOptions]=useState<{users:Array<{id:string;name:string}>;roles:Array<{id:string;codigo:string}>}>({users:[],roles:[]})
 const [optionsError,setOptionsError]=useState('')
 useEffect(()=>{let active=true;recursoRequest<typeof options>('/audit/options').then(data=>{if(active)setOptions(data)}).catch(()=>{if(active)setOptionsError('No se pudieron cargar los filtros de personas y roles.')});return()=>{active=false}},[])
 useEffect(()=>{let active=true;const query=new URLSearchParams({limit:'26',offset:String(page*25)});Object.entries(applied).forEach(([k,v])=>{if(v)query.set(k,v)});if(params.get('asignacion'))query.set('asignacion',params.get('asignacion')!);recursoRequest<Audit[]>(`/audit?${query}`,'GET',undefined,true).then(data=>{if(active){setRows(data);setError('')}}).catch(e=>{if(active){setError(e.message);setRows([])}});return()=>{active=false}},[applied,page,revision,params])
 const change=(key:keyof typeof filters,v:string)=>setFilters(f=>({...f,[key]:v}))
 const apply=()=>{setRows(null);setSelected(null);setPage(0);setApplied({...filters});setRevision(r=>r+1)}
 const changes=selected?Array.from(new Set([...Object.keys(selected.old_values||{}),...Object.keys(selected.new_values||{})])).filter(k=>!sensitive(k)&&!['id','updated_at','updated_by','created_by'].includes(k)&&JSON.stringify(selected.old_values?.[k])!==JSON.stringify(selected.new_values?.[k])):[]
 return <section className="assignments-page"><header className="assignments-heading"><div><h1>Auditoría</h1><p>Consulta quién realizó cada cambio y revisa su historial.</p></div><button className="assignments-secondary" onClick={apply}>Actualizar</button></header>
 <div className="assignments-panel"><div className="audit-heading"><h2>Historial de cambios</h2><span className="audit-tag">Solo consulta</span></div>{params.get('asignacion')&&<p className="assignments-feedback">Historial de la asignación seleccionada. <button className="assignments-secondary" onClick={()=>{setParams({});setPage(0);setRows(null)}}>Ver todas</button></p>}
 <form onSubmit={e=>{e.preventDefault();apply()}}><div className="assignments-filters"><label>Desde<input type="date" value={filters.desde} onChange={e=>change('desde',e.target.value)}/></label><label>Hasta<input type="date" min={filters.desde||undefined} value={filters.hasta} onChange={e=>change('hasta',e.target.value)}/></label><label>Módulo<select value={filters.entity_type} onChange={e=>change('entity_type',e.target.value)}><option value="">Todos los módulos</option>{Object.entries(entities).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label><label>Acción<select value={filters.action} onChange={e=>change('action',e.target.value)}><option value="">Todas las acciones</option>{Object.entries(actions).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label><label>Realizado por<select value={filters.actor_user_id} onChange={e=>change('actor_user_id',e.target.value)}><option value="">Todas las personas</option>{options.users.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label><label>Rol al realizar el cambio<select value={filters.actor_role_id} onChange={e=>change('actor_role_id',e.target.value)}><option value="">Todos los roles</option>{options.roles.map(r=><option key={r.id} value={r.id}>{r.codigo}</option>)}</select></label><label>Buscar en el historial<input placeholder="Ej.: eliminar, asignación, Ignacio…" maxLength={150} value={filters.search} onChange={e=>change('search',e.target.value)}/></label></div><div className="assignments-editor-actions"><button className="assignments-primary">Aplicar filtros</button><button type="button" className="assignments-secondary" onClick={()=>{const empty={desde:'',hasta:'',action:'',entity_type:'',actor_user_id:'',actor_role_id:'',search:''};setFilters(empty);setApplied(empty);setPage(0);setRows(null);setRevision(r=>r+1)}}>Limpiar filtros</button></div></form>{optionsError&&<p role="status">{optionsError}</p>}</div>
 {error&&<p className="assignments-error" role="alert">{error}</p>}
 <div className="assignments-panel">{!rows?<LoadingIndicator/>:!rows.length?<p>No hay registros para estos filtros.</p>:<><div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><th>Fecha y hora</th><th>Realizado por</th><th>Acción</th><th>Elemento afectado</th><th>Detalle</th></tr></thead><tbody>{rows.slice(0,25).map(r=><tr key={r.id}><td>{timestamp(r.created_at)}</td><td><strong>{r.actor_name}</strong><small className="audit-muted">{r.actor_role||'Sistema'}</small></td><td><span className="audit-tag">{actions[r.action]||r.action.replaceAll('_',' ')}</span></td><td><small className="audit-muted">{entities[r.entity_type]||r.entity_type}</small>{r.entity_name||r.description||'Registro de actividad'}</td><td><button className="assignments-secondary" onClick={()=>setSelected(r)}>Ver detalle</button></td></tr>)}</tbody></table></div><div className="audit-pagination"><button className="assignments-secondary" disabled={page===0} onClick={()=>{setRows(null);setSelected(null);setPage(p=>p-1)}}>Anterior</button><span>Página {page+1}</span><button className="assignments-secondary" disabled={rows.length<=25} onClick={()=>{setRows(null);setSelected(null);setPage(p=>p+1)}}>Siguiente</button></div></>}</div>
 {selected&&<dialog ref={detailDialog} className="assignments-panel audit-detail audit-dialog" aria-labelledby="audit-detail-title" onCancel={()=>setSelected(null)} onClick={e=>{if(e.target===e.currentTarget){const rect=e.currentTarget.getBoundingClientRect();if(e.clientX<rect.left||e.clientX>rect.right||e.clientY<rect.top||e.clientY>rect.bottom)setSelected(null)}}}><div className="audit-heading"><div><h2 id="audit-detail-title">{actions[selected.action]||selected.action.replaceAll('_',' ')}</h2><p>{friendlyDate(selected.created_at)} · {selected.actor_name}</p></div><button autoFocus type="button" className="assignments-secondary" onClick={()=>setSelected(null)}>Cerrar detalle</button></div><p>{selected.description}</p><p className="audit-muted">Canal: {selected.source==='WEB'?'Sitio web':selected.source==='EMAIL'?'Correo':selected.source}</p>{changes.length?<div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><th>Dato</th><th>Antes</th><th>Después</th></tr></thead><tbody>{changes.map(k=><tr key={k}><td>{fields[k]||k.replaceAll('_',' ')}</td><td>{renderValue((selected.old_display_values || selected.old_values)?.[k],k)}</td><td className="audit-new">{renderValue((selected.new_display_values || selected.new_values)?.[k],k)}</td></tr>)}</tbody></table></div>:<p>Este evento no contiene cambios de campos para comparar.</p>}</dialog>}
 </section>
}
