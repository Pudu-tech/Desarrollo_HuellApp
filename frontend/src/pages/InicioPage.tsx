import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { getAsignacionesResumen } from '../services/asignacionesService'
import { recursoRequest } from '../services/recursosService'
import type { ParticipacionPropia } from '../services/participacionesService'
import { useVisibleRefresh } from '../hooks/useVisibleRefresh'
import LoadingIndicator from '../components/LoadingIndicator'
import '../styles/inicio.css'

type Activity = { id: string; fecha: string; hora: string; nombre: string; lugar: string; estado: string; admiteRespuesta?: boolean; asistencia: Record<string, number> }
const today = () => new Intl.DateTimeFormat('sv-SE', { timeZone: 'America/Santiago' }).format(new Date())
const key = (d: Date) => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`
const labels: Record<string,string> = { PENDIENTE:'Pendiente', CONFIRMADA:'Confirmada', REALIZADA:'Realizada', CANCELADA:'Cancelada', NO_REALIZADA:'No realizada', ACEPTADA:'Aceptada', RECHAZADA:'Rechazada', PRESENTE:'Presente', AUSENTE:'Ausente', JUSTIFICADA:'Justificada', NO_REQUERIDA:'No requerida' }
export default function InicioPage() {
 const { user } = useAuth()
 const personal = user?.role_code === 'MONITOR'
 const [items,setItems] = useState<Activity[] | null>(null)
 const [error,setError] = useState('')
 const [selected,setSelected] = useState(today)
 const [month,setMonth] = useState(() => new Date(`${today().slice(0,7)}-01T12:00:00`))
 async function read(fresh=false): Promise<Activity[]> {
  if(personal) { const rows=await recursoRequest<ParticipacionPropia[]>('/mi-participacion','GET',undefined,fresh); return rows.map(r=>({id:r.asignacion_id,fecha:r.fecha,hora:r.hora_inicio.slice(0,5),nombre:r.actividad,lugar:r.colegio||r.lugar||'Por definir',estado:r.estado,admiteRespuesta:r.admite_respuesta,asistencia:{}})) }
  const data=await getAsignacionesResumen(fresh)
  return data.items.map(r=>({id:r.id,fecha:r.fecha,hora:r.hora_inicio.slice(0,5),nombre:data.catalogos.tipos_actividad.find(t=>t.id===r.tipo_actividad_id)?.nombre||'Actividad',lugar:data.catalogos.colegios.find(c=>c.id===r.colegio_id)?.nombre||r.lugar||'Por definir',estado:data.catalogos.estados.find(e=>e.id===r.estado_id)?.codigo||'PENDIENTE',asistencia:r.asistencia_resumen||{}}))
 }
 useEffect(()=>{let active=true; read().then(rows=>{if(active){setItems(rows);setError('')}}).catch(e=>{if(active)setError(e.message)});return()=>{active=false}
 // La sección se vuelve a montar al cambiar de usuario.
 // eslint-disable-next-line react-hooks/exhaustive-deps
 },[user?.id,personal])
 useVisibleRefresh(async active=>{try{const rows=await read(true);if(active()){setItems(rows);setError('')}}catch{/* Conserva los datos durante fallos transitorios. */}},items!==null,30000)
 const upcoming=(items||[]).filter(r=>r.fecha>=today()&&!['RECHAZADA','CANCELADA','NO_REALIZADA',...(personal?[]:['REALIZADA'])].includes(r.estado)).sort((a,b)=>`${a.fecha}${a.hora}`.localeCompare(`${b.fecha}${b.hora}`))
 const visible=(items||[]).filter(r=>r.fecha.startsWith(key(month).slice(0,7)))
 const move=(amount:number)=>{const next=new Date(month.getFullYear(),month.getMonth()+amount,1,12);setMonth(next);setSelected(key(next))}
 const activity=(r:Activity)=><Link className="home-activity" key={r.id} to={`${personal?'/app/monitor/asignaciones':'/app/asignaciones'}/${r.id}`}><span className="home-date">{r.fecha.slice(8)} / {r.fecha.slice(5,7)}<small>{r.hora}</small></span><span><strong>{r.nombre}</strong><small>{r.lugar}</small></span><span className="home-tag">{labels[r.estado]||r.estado}</span></Link>
 const dayItems=visible.filter(r=>r.fecha===selected)
 const statsLinks=personal?['/app/monitor/asignaciones?orden=proximas','/app/monitor/asignaciones?pendientes=1','/app/monitor/asignaciones']:['/app/asignaciones', '/app/asignaciones?proximas=1&desde='+today(), '/app/asignaciones?estado=REALIZADA', '/app/asignaciones?estado=PENDIENTE']
 const stats=personal?[['Próximas actividades',upcoming.length],['Por responder',(items||[]).filter(r=>r.estado==='PENDIENTE'&&r.admiteRespuesta).length],['Aceptadas este mes',visible.filter(r=>r.estado==='ACEPTADA').length]]:[['Asignaciones registradas',items?.length||0],['Próximas actividades',upcoming.length],['Realizadas',(items||[]).filter(r=>r.estado==='REALIZADA').length],['Por confirmar',(items||[]).filter(r=>r.estado==='PENDIENTE').length]]
 return <section className="home-dashboard"><header className="home-heading"><div><span className="home-eyebrow">Tu espacio en HuellApp</span><h2>Hola, {user?.nombres||'bienvenido'}</h2><p>{personal?'Tu agenda y tus próximas actividades, en un solo lugar.':'Una mirada a las actividades y la asistencia del equipo.'}</p></div><span className="home-today">{new Intl.DateTimeFormat('es-CL',{dateStyle:'long',timeZone:'America/Santiago'}).format(new Date())}</span></header>
 {error&&<div role="alert" className="home-error">{error} <button onClick={()=>void read(true).then(rows=>{setItems(rows);setError('')}).catch(e=>setError(e.message))}>Reintentar</button></div>}
 {!items?!error&&<LoadingIndicator/>:<><div className="home-stats">{stats.map(([label,value],i)=><Link to={statsLinks[i]} key={label}><span>{label}</span><strong>{value}</strong></Link>)}</div><div className="home-columns">
 {personal?<article className="home-card"><div className="home-calendar-header"><h3>{new Intl.DateTimeFormat('es-CL',{month:'long',year:'numeric'}).format(month)}</h3><div><button aria-label="Mes anterior" onClick={()=>move(-1)}>‹</button><button onClick={()=>{const now=today();setMonth(new Date(`${now.slice(0,7)}-01T12:00:00`));setSelected(now)}}>Hoy</button><button aria-label="Mes siguiente" onClick={()=>move(1)}>›</button></div></div><div className="home-calendar">{['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'].map(d=><span className="home-weekday" key={d}>{d}</span>)}{Array.from({length:(month.getDay()+6)%7},(_,i)=><span key={`empty${i}`}/>)}{Array.from({length:new Date(month.getFullYear(),month.getMonth()+1,0).getDate()},(_,i)=>{const date=key(new Date(month.getFullYear(),month.getMonth(),i+1,12));const count=visible.filter(r=>r.fecha===date).length;return <button key={date} aria-pressed={selected===date} aria-label={`${date}, ${count} asignaciones`} className={`home-day ${date===today()?'is-today':''} ${date===selected?'is-selected':''}`} onClick={()=>setSelected(date)}><strong>{i+1}</strong>{count>0&&<span className="home-marker">{count}<span className="home-day-word"> actividad{count>1?'es':''}</span></span>}</button>})}</div><p className="home-muted">Selecciona un día marcado para consultar tus asignaciones.</p><h3>{new Intl.DateTimeFormat('es-CL',{day:'numeric',month:'long'}).format(new Date(`${selected}T12:00:00`))}</h3>{dayItems.length?dayItems.map(activity):<p className="home-muted">No tienes actividades para este día.</p>}</article>:<article className="home-card"><h3>Estado de las asignaciones</h3><p className="home-muted">Todas las asignaciones visibles del equipo.</p>{['PENDIENTE','CONFIRMADA','REALIZADA','CANCELADA','NO_REALIZADA'].map((state,i)=>{const count=items.filter(r=>r.estado===state).length;return <Link to={`/app/asignaciones?estado=${state}`} className="home-chart" key={state}><div><span>{labels[state]}</span><strong>{count}</strong></div><div className="home-track"><span style={{width:`${items.length?count/items.length*100:0}%`,background:['#e5b765','#76a997','#28616a','#d07b66','#97a0ae'][i]}}/></div></Link>})}</article>}
 <article className="home-card"><h3>{personal?'Lo que viene':'Asistencia del equipo'}</h3>{personal?<><p className="home-muted">Tus próximas actividades, ordenadas por fecha.</p>{upcoming.length?upcoming.slice(0,5).map(activity):<p className="home-muted">Tu agenda está despejada. Aquí aparecerán tus próximas asignaciones.</p>}<Link className="home-more" to="/app/monitor/asignaciones">Ver mis asignaciones →</Link></>:<>{['PRESENTE','PENDIENTE','AUSENTE','JUSTIFICADA','NO_REQUERIDA'].map(state=><Link to={`/app/asistencia?estado=${state}`} className="home-attendance" key={state}><span>{labels[state]}</span><strong>{items.reduce((sum,r)=>sum+(r.asistencia[state]||0),0)}</strong></Link>)}<Link className="home-more" to="/app/asistencia">Consultar asistencia →</Link></>}</article></div>{!personal&&<article className="home-card"><h3>Próximas actividades del equipo</h3>{upcoming.length?upcoming.slice(0,5).map(activity):<p className="home-muted">No hay próximas actividades programadas.</p>}<Link className="home-more" to="/app/asignaciones">Ver todas las asignaciones →</Link></article>}</>}
 </section>
}
