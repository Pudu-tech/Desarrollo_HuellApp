"""
Endpoints de administración de colegios en HuellAPP.

Funciones disponibles:
- listar colegios;
- obtener colegio por UUID;
- crear colegio;
- modificar colegio;
- desactivar colegio.

SECURITY:
- Todos los endpoints utilizan permisos RBAC.
- created_by y updated_by provienen del usuario autenticado.
- No se confía en identificadores relacionados sin validarlos.
- Las operaciones sensibles quedan registradas en auditoría.
- No existe eliminación física de colegios desde esta API.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.colegios import (
    ColegioCreate,
    ColegioListItem,
    ColegioUpdate,
)
from app.services.audit import write_audit_log


router = APIRouter(
    prefix="/colegios",
    tags=["Colegios"],
)


# ============================================================
# CAMPOS CONSULTADOS
# ============================================================

COLEGIO_SELECT = """
id,
rbd,
nombre,
descripcion,
tipo_dependencia_id,
direccion,
numero,
complemento,
comuna_id,
region_id,
codigo_postal,
telefono,
email,
sitio_web,
nombre_contacto,
telefono_contacto,
email_contacto,
activo
"""


# ============================================================
# FUNCIONES INTERNAS
# ============================================================


def _colegio_a_auditoria(
    colegio: ColegioListItem,
) -> dict:
    """
    Convierte un colegio a un diccionario seguro para auditoría.

    Los UUID se convierten a texto para asegurar que los valores
    sean serializables correctamente como JSONB.
    """

    return {
        "id": str(colegio.id),
        "rbd": colegio.rbd,
        "nombre": colegio.nombre,
        "descripcion": colegio.descripcion,
        "tipo_dependencia_id": (
            str(colegio.tipo_dependencia_id)
            if colegio.tipo_dependencia_id
            else None
        ),
        "direccion": colegio.direccion,
        "numero": colegio.numero,
        "complemento": colegio.complemento,
        "comuna_id": str(colegio.comuna_id),
        "region_id": str(colegio.region_id),
        "codigo_postal": colegio.codigo_postal,
        "telefono": colegio.telefono,
        "email": (
            str(colegio.email)
            if colegio.email
            else None
        ),
        "sitio_web": colegio.sitio_web,
        "nombre_contacto": colegio.nombre_contacto,
        "telefono_contacto": colegio.telefono_contacto,
        "email_contacto": (
            str(colegio.email_contacto)
            if colegio.email_contacto
            else None
        ),
        "activo": colegio.activo,
    }


def _payload_a_dict(
    payload: ColegioCreate | ColegioUpdate,
) -> dict:
    """
    Convierte un modelo Pydantic en datos compatibles con Supabase.

    exclude_unset permite que PATCH modifique solamente
    los campos enviados por el cliente.
    """

    return payload.model_dump(
        exclude_unset=True,
        mode="json",
    )


def _validar_relaciones_colegio(
    supabase,
    *,
    region_id: UUID,
    comuna_id: UUID,
    tipo_dependencia_id: UUID | None,
) -> None:
    """
    Valida las relaciones del colegio.

    Reglas:
    - la región debe existir y estar activa;
    - la comuna debe existir y estar activa;
    - la comuna debe pertenecer a la región;
    - el tipo de dependencia, si existe, debe estar activo.
    """

    # --------------------------------------------------------
    # REGIÓN
    # --------------------------------------------------------

    region_response = (
        supabase.table("regiones")
        .select("id,activo")
        .eq("id", str(region_id))
        .maybe_single()
        .execute()
    )

    if (
        not region_response.data
        or region_response.data["activo"] is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La región seleccionada no existe o está inactiva.",
        )

    # --------------------------------------------------------
    # COMUNA
    # --------------------------------------------------------

    comuna_response = (
        supabase.table("comunas")
        .select("id,region_id,activo")
        .eq("id", str(comuna_id))
        .maybe_single()
        .execute()
    )

    if (
        not comuna_response.data
        or comuna_response.data["activo"] is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La comuna seleccionada no existe o está inactiva.",
        )

    # --------------------------------------------------------
    # COHERENCIA COMUNA / REGIÓN
    # --------------------------------------------------------

    if (
        str(comuna_response.data["region_id"])
        != str(region_id)
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "La comuna seleccionada no pertenece "
                "a la región indicada."
            ),
        )

    # --------------------------------------------------------
    # TIPO DE DEPENDENCIA
    # --------------------------------------------------------

    if tipo_dependencia_id is not None:
        dependencia_response = (
            supabase.table("tipos_dependencia")
            .select("id,activo")
            .eq("id", str(tipo_dependencia_id))
            .maybe_single()
            .execute()
        )

        if (
            not dependencia_response.data
            or dependencia_response.data["activo"] is not True
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "El tipo de dependencia seleccionado "
                    "no existe o está inactivo."
                ),
            )


# ============================================================
# LISTAR COLEGIOS
# ============================================================


@router.get(
    "",
    response_model=list[ColegioListItem],
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_SCHOOLS.",
        },
        500: {
            "description": "Error interno al obtener colegios.",
        },
    },
)
async def listar_colegios(
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_SCHOOLS")
    ),
) -> list[ColegioListItem]:
    """
    Lista colegios no eliminados lógicamente.

    Se incluyen colegios activos e inactivos para permitir
    su administración y trazabilidad.
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .is_("deleted_at", "null")
            .order("nombre")
            .execute()
        )

        return [
            ColegioListItem.model_validate(item)
            for item in (response.data or [])
        ]

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener los colegios.",
        )


# ============================================================
# OBTENER COLEGIO
# ============================================================


@router.get(
    "/{colegio_id}",
    response_model=ColegioListItem,
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_SCHOOLS.",
        },
        404: {
            "description": "Colegio no encontrado.",
        },
        500: {
            "description": "Error interno al obtener el colegio.",
        },
    },
)
async def obtener_colegio(
    colegio_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_SCHOOLS")
    ),
) -> ColegioListItem:
    """
    Obtiene un colegio no eliminado lógicamente por UUID.
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .eq("id", str(colegio_id))
            .is_("deleted_at", "null")
            .maybe_single()
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        return ColegioListItem.model_validate(
            response.data
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener el colegio.",
        )


# ============================================================
# CREAR COLEGIO
# ============================================================


@router.post(
    "",
    response_model=ColegioListItem,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {
            "description": "Datos o relaciones inválidas.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso CREATE_SCHOOL.",
        },
        409: {
            "description": "El RBD ya se encuentra registrado.",
        },
        500: {
            "description": "Error interno al crear el colegio.",
        },
    },
)
async def crear_colegio(
    request: Request,
    payload: ColegioCreate,
    current_user: AuthenticatedUser = Depends(
        require_permission("CREATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Crea un colegio.

    Validaciones:
    - RBD único cuando se informa;
    - región válida y activa;
    - comuna válida y activa;
    - comuna perteneciente a la región;
    - dependencia válida y activa cuando se informa.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. VALIDAR RBD
        # --------------------------------------------------------

        if payload.rbd is not None:
            rbd_response = (
                supabase.table("colegios")
                .select("id")
                .eq("rbd", payload.rbd)
                .limit(1)
                .execute()
            )

            if rbd_response.data:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El RBD ya se encuentra registrado.",
                )

        # --------------------------------------------------------
        # 2. VALIDAR RELACIONES
        # --------------------------------------------------------

        _validar_relaciones_colegio(
            supabase,
            region_id=payload.region_id,
            comuna_id=payload.comuna_id,
            tipo_dependencia_id=payload.tipo_dependencia_id,
        )

        # --------------------------------------------------------
        # 3. CREAR COLEGIO
        # --------------------------------------------------------

        insert_data = _payload_a_dict(payload)

        insert_data["activo"] = True
        insert_data["created_by"] = str(current_user.id)
        insert_data["updated_by"] = str(current_user.id)

        insert_response = (
            supabase.table("colegios")
            .insert(insert_data)
            .execute()
        )

        if not insert_response.data:
            raise RuntimeError(
                "No se creó el colegio."
            )

        colegio_id = insert_response.data[0]["id"]

        # --------------------------------------------------------
        # 4. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        created_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .eq("id", colegio_id)
            .single()
            .execute()
        )

        colegio = ColegioListItem.model_validate(
            created_response.data
        )

        # --------------------------------------------------------
        # 5. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="CREATE_SCHOOL",
            entity_type="SCHOOL",
            entity_id=colegio.id,
            old_values=None,
            new_values=_colegio_a_auditoria(colegio),
            description="Creación de colegio.",
        )

        return colegio

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible crear el colegio.",
        )


# ============================================================
# ACTUALIZAR COLEGIO
# ============================================================


@router.patch(
    "/{colegio_id}",
    response_model=ColegioListItem,
    responses={
        400: {
            "description": "Datos inválidos o sin cambios.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso UPDATE_SCHOOL.",
        },
        404: {
            "description": "Colegio no encontrado.",
        },
        409: {
            "description": "El RBD ya se encuentra registrado.",
        },
        500: {
            "description": "Error interno al actualizar el colegio.",
        },
    },
)
async def actualizar_colegio(
    request: Request,
    colegio_id: UUID,
    payload: ColegioUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("UPDATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Modifica los datos de un colegio existente.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER ESTADO ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT + ",deleted_at")
            .eq("id", str(colegio_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        colegio_actual = ColegioListItem.model_validate(
            current_response.data
        )

        # --------------------------------------------------------
        # 2. OBTENER CAMPOS ENVIADOS
        # --------------------------------------------------------

        update_data = _payload_a_dict(payload)

        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se enviaron campos para actualizar.",
            )

        # --------------------------------------------------------
        # 3. VALIDAR RBD SI CAMBIA
        # --------------------------------------------------------

        if (
            "rbd" in update_data
            and update_data["rbd"] is not None
            and update_data["rbd"] != colegio_actual.rbd
        ):
            rbd_response = (
                supabase.table("colegios")
                .select("id")
                .eq("rbd", update_data["rbd"])
                .neq("id", str(colegio_id))
                .limit(1)
                .execute()
            )

            if rbd_response.data:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El RBD ya se encuentra registrado.",
                )

        # --------------------------------------------------------
        # 4. VALIDAR RELACIONES SOLO CUANDO CAMBIAN
        # --------------------------------------------------------

        campos_relacionados = {
            "region_id",
            "comuna_id",
            "tipo_dependencia_id",
        }

        if campos_relacionados.intersection(update_data):
            region_final = UUID(
                str(
                    update_data.get(
                        "region_id",
                        colegio_actual.region_id,
                    )
                )
            )

            comuna_final = UUID(
                str(
                    update_data.get(
                        "comuna_id",
                        colegio_actual.comuna_id,
                    )
                )
            )

            dependencia_final_raw = update_data.get(
                "tipo_dependencia_id",
                colegio_actual.tipo_dependencia_id,
            )

            dependencia_final = (
                UUID(str(dependencia_final_raw))
                if dependencia_final_raw is not None
                else None
            )

            _validar_relaciones_colegio(
                supabase,
                region_id=region_final,
                comuna_id=comuna_final,
                tipo_dependencia_id=dependencia_final,
            )

        # --------------------------------------------------------
        # 5. ACTUALIZAR
        # --------------------------------------------------------

        update_data["updated_by"] = str(current_user.id)

        update_response = (
            supabase.table("colegios")
            .update(update_data)
            .eq("id", str(colegio_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible actualizar el colegio."
            )

        # --------------------------------------------------------
        # 6. CONSULTAR ESTADO POSTERIOR
        # --------------------------------------------------------

        updated_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .eq("id", str(colegio_id))
            .single()
            .execute()
        )

        colegio_actualizado = ColegioListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 7. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="UPDATE_SCHOOL",
            entity_type="SCHOOL",
            entity_id=colegio_actualizado.id,
            old_values=_colegio_a_auditoria(
                colegio_actual
            ),
            new_values=_colegio_a_auditoria(
                colegio_actualizado
            ),
            description="Actualización de colegio.",
        )

        return colegio_actualizado

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible actualizar el colegio.",
        )

# ============================================================
# ACTIVAR COLEGIO
# ============================================================


@router.patch(
    "/{colegio_id}/activate",
    response_model=ColegioListItem,
    responses={
        400: {
            "description": "El colegio ya se encuentra activo.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso ACTIVATE_SCHOOL.",
        },
        404: {
            "description": "Colegio no encontrado.",
        },
        500: {
            "description": "Error interno al activar el colegio.",
        },
    },
)
async def activar_colegio(
    request: Request,
    colegio_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("ACTIVATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Reactiva un colegio previamente desactivado.

    La operación no modifica otros datos del colegio.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER COLEGIO ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT + ",deleted_at")
            .eq("id", str(colegio_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        colegio_actual = ColegioListItem.model_validate(
            current_response.data
        )

        # --------------------------------------------------------
        # 2. VALIDAR ESTADO
        # --------------------------------------------------------

        if colegio_actual.activo is True:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El colegio ya se encuentra activo.",
            )

        # --------------------------------------------------------
        # 3. ACTIVAR
        # --------------------------------------------------------

        update_response = (
            supabase.table("colegios")
            .update(
                {
                    "activo": True,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(colegio_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible activar el colegio."
            )

        # --------------------------------------------------------
        # 4. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        updated_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .eq("id", str(colegio_id))
            .single()
            .execute()
        )

        colegio_actualizado = ColegioListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 5. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="ACTIVATE_SCHOOL",
            entity_type="SCHOOL",
            entity_id=colegio_actualizado.id,
            old_values={
                "activo": False,
            },
            new_values={
                "activo": True,
            },
            description="Activación de colegio.",
        )

        return colegio_actualizado

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible activar el colegio.",
        )




# ============================================================
# DESACTIVAR COLEGIO
# ============================================================


@router.patch(
    "/{colegio_id}/deactivate",
    response_model=ColegioListItem,
    responses={
        400: {
            "description": "El colegio ya se encuentra inactivo.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso DEACTIVATE_SCHOOL.",
        },
        404: {
            "description": "Colegio no encontrado.",
        },
        500: {
            "description": "Error interno al desactivar el colegio.",
        },
    },
)
async def desactivar_colegio(
    request: Request,
    colegio_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("DEACTIVATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Desactiva un colegio.

    La operación no elimina físicamente el registro.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER COLEGIO ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT + ",deleted_at")
            .eq("id", str(colegio_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        colegio_actual = ColegioListItem.model_validate(
            current_response.data
        )

        if colegio_actual.activo is False:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El colegio ya se encuentra inactivo.",
            )

        # --------------------------------------------------------
        # 2. DESACTIVAR
        # --------------------------------------------------------

        update_response = (
            supabase.table("colegios")
            .update(
                {
                    "activo": False,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(colegio_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible desactivar el colegio."
            )

        # --------------------------------------------------------
        # 3. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        updated_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .eq("id", str(colegio_id))
            .single()
            .execute()
        )

        colegio_actualizado = ColegioListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 4. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="DEACTIVATE_SCHOOL",
            entity_type="SCHOOL",
            entity_id=colegio_actualizado.id,
            old_values={
                "activo": True,
            },
            new_values={
                "activo": False,
            },
            description="Desactivación de colegio.",
        )

        return colegio_actualizado

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible desactivar el colegio.",
        )