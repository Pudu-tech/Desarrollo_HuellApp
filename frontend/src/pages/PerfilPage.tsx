import { useEffect, useState } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { recursoRequest } from '../services/recursosService'
import LoadingIndicator from '../components/LoadingIndicator'
import '../styles/asignaciones.css'
import '../styles/perfil.css'
interface Profile {id:string;email:string;nombres:string;apellido_paterno:string;apellido_materno:string|null;telefono:string|null;foto_url:string|null}
export default function PerfilPage(){
 const {user}=useAuth()
 const [profile,setProfile]=useState<Profile|null>(null)
 const [phone,setPhone]=useState('')
 const [photo,setPhoto]=useState<string|null>(null)
 const [preview,setPreview]=useState<string|null>(null)
 const [remove,setRemove]=useState(false)
 const [busy,setBusy]=useState(false)
 const [reading,setReading]=useState(false)
 const [error,setError]=useState('')
 const [notice,setNotice]=useState('')
 const [revision,setRevision]=useState(0)
 useEffect(()=>{let active=true;recursoRequest<Profile>('/mi-perfil','GET',undefined,true).then(p=>{if(active){setProfile(p);setPhone(p.telefono||'');setError('')}}).catch(e=>{if(active)setError(e.message)});return()=>{active=false}},[revision])
 async function selectPhoto(file:File|undefined){
  if(!file)return
  setError('');setNotice('')
  if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>3*1024*1024){setError('Selecciona una foto JPG, PNG o WebP de hasta 3 MB.');return}
  setReading(true)
  try{
   const data=await new Promise<string>((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result));reader.onerror=()=>reject(new Error('No se pudo leer la foto.'));reader.readAsDataURL(file)})
   setPhoto(data.split(',')[1]);setPreview(data);setRemove(false)
  }catch(e){setError(e instanceof Error?e.message:'No se pudo leer la foto.')}
  finally{setReading(false)}
 }
 async function save(){
  if(busy||reading)return
  setBusy(true);setError('');setNotice('')
  try{const p=await recursoRequest<Profile>('/mi-perfil','PATCH',{telefono:phone.trim()||null,foto_base64:photo,quitar_foto:remove});setProfile(p);setPhone(p.telefono||'');setPhoto(null);setPreview(null);setRemove(false);setNotice('Tu perfil se actualizó correctamente.')}
  catch(e){setError(e instanceof Error?e.message:'No se pudo guardar tu perfil.')}
  finally{setBusy(false)}
 }
 const image=remove?null:preview||profile?.foto_url
 return <section className="assignments-page"><header className="assignments-heading"><div><h1>Mi perfil</h1><p>Personaliza tu foto y mantén actualizado tu teléfono.</p></div></header>{error&&<p className="assignments-error" role="alert">{error}{!profile&&<button className="assignments-secondary" onClick={()=>setRevision(r=>r+1)}>Reintentar</button>}</p>}{notice&&<p className="assignments-feedback" role="status">{notice}</p>}{!profile?!error&&<LoadingIndicator/>:<form className="assignments-panel profile-panel" onSubmit={e=>{e.preventDefault();void save()}}><div className="profile-identity">{image?<img src={image} className="profile-avatar" alt="Tu foto de perfil"/>:<div className="profile-avatar profile-initials" aria-label="Sin foto de perfil">{profile.nombres.charAt(0)}{profile.apellido_paterno.charAt(0)}</div>}<div><h2>{profile.nombres} {profile.apellido_paterno} {profile.apellido_materno}</h2><p>{profile.email}</p><span className="profile-role">{user?.role_code}</span></div></div><div className="profile-photo-actions"><label className="assignments-secondary">{reading?'Leyendo foto…':'Seleccionar foto'}<input className="profile-file" type="file" accept="image/jpeg,image/png,image/webp" disabled={busy||reading} onChange={e=>{void selectPhoto(e.target.files?.[0]);e.target.value=''}}/></label>{image&&<button type="button" className="assignments-secondary" disabled={busy||reading} onClick={()=>{setRemove(true);setPhoto(null);setPreview(null)}}>Quitar foto</button>}</div><p className="profile-hint">JPG, PNG o WebP · Máximo 3 MB. La foto se guarda al confirmar los cambios.</p><div className="assignments-form-grid"><label>Teléfono<input type="tel" autoComplete="tel" maxLength={30} pattern="[+0-9 ()\-]{5,30}" placeholder="Ej.: +56912345678" value={phone} disabled={busy} onChange={e=>setPhone(e.target.value)}/></label></div><p className="profile-hint">Para cambiar tu nombre, correo o rol, contacta a la administración.</p><button className="assignments-primary" disabled={busy||reading}>{busy?'Guardando…':'Guardar cambios'}</button></form>}</section>
}
