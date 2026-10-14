"""Perfil propio: identidad del token, foto privada y escritura auditada."""
import base64
import binascii
import re
from uuid import uuid4
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from app.core.security import get_current_user
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser

router=APIRouter(prefix='/mi-perfil',tags=['Perfil'])
FIELDS='id,email,nombres,apellido_paterno,apellido_materno,telefono,foto_perfil_path'
class ProfileUpdate(BaseModel):
    model_config=ConfigDict(extra='forbid')
    telefono: str | None=Field(None,max_length=30)
    foto_base64: str | None=Field(None,max_length=4194304)
    quitar_foto: bool=False
    @field_validator('telefono')
    @classmethod
    def phone(cls,value):
        if value and not re.fullmatch(r'[+0-9 ()-]{5,30}',value.strip()): raise ValueError('Ingresa un teléfono válido.')
        return value.strip() or None if value else None

def image_bytes(encoded):
    try: raw=base64.b64decode(encoded,validate=True)
    except (ValueError,binascii.Error) as exc: raise HTTPException(422,'La imagen no es válida.') from exc
    if not raw or len(raw)>3*1024*1024: raise HTTPException(422,'La foto debe pesar como máximo 3 MB.')
    if raw.startswith(b'\x89PNG\r\n\x1a\n'): return raw,'png','image/png'
    if raw.startswith(b'\xff\xd8\xff'): return raw,'jpg','image/jpeg'
    if raw.startswith(b'RIFF') and raw[8:12]==b'WEBP': return raw,'webp','image/webp'
    raise HTTPException(422,'Selecciona una foto JPG, PNG o WebP.')

def present(db,row):
    result={k:v for k,v in row.items() if k!='foto_perfil_path'}
    result['foto_url']=None
    if row.get('foto_perfil_path'):
        signed=db.storage.from_('profile-photos').create_signed_url(row['foto_perfil_path'],3600)
        result['foto_url']=signed.get('signedURL') or signed.get('signedUrl')
    return result

@router.get('')
def profile(actor:AuthenticatedUser=Depends(get_current_user)):
    db=get_supabase_client()
    try:
        rows=db.table('usuarios').select(FIELDS).eq('id',str(actor.id)).eq('activo',True).is_('deleted_at','null').execute().data or []
        if not rows: raise HTTPException(404,'No se encontró tu perfil.')
        return present(db,rows[0])
    except HTTPException: raise
    except Exception as exc: raise HTTPException(503,'No fue posible cargar tu perfil. Verifica que la migración 055 esté aplicada.') from exc

@router.patch('')
def update(payload:ProfileUpdate,actor:AuthenticatedUser=Depends(get_current_user)):
    if payload.foto_base64 and payload.quitar_foto: raise HTTPException(422,'Selecciona una foto o quita la actual, no ambas opciones.')
    db=get_supabase_client()
    path=None
    try:
        if payload.foto_base64:
            raw,ext,mime=image_bytes(payload.foto_base64)
            path=f'{actor.id}/{uuid4()}.{ext}'
            db.storage.from_('profile-photos').upload(path,raw,{'content-type':mime,'upsert':'false'})
        result=db.rpc('actualizar_perfil_propio',{'p_actor':str(actor.id),'p_telefono':payload.telefono,'p_foto':path,'p_cambiar_foto':bool(path) or payload.quitar_foto}).execute().data
    except Exception as exc:
        if path:
            try: db.storage.from_('profile-photos').remove([path])
            except Exception: pass
        if isinstance(exc,HTTPException): raise
        raise HTTPException(503,'No fue posible guardar tu perfil. Reintenta.') from exc
    # La escritura ya terminó; si falla la URL temporal, no informa falsamente que falló el guardado.
    row={k:result.get(k) for k in FIELDS.split(',')}
    try: return present(db,row)
    except Exception:
        response={k:v for k,v in row.items() if k!='foto_perfil_path'}
        response['foto_url']=None
        return response
