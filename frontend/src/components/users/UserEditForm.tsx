/**
 * HuellAPP
 * Formulario funcional de edición de usuarios.
 *
 * Permite:
 * - editar datos básicos;
 * - cambiar rol;
 * - activar/desactivar;
 * - eliminar usuario.
 *
 * Cada operación utiliza su endpoint específico.
 */

import {
  useEffect,
  useState,
  type FormEvent,
} from 'react'

import type {
  UserListItem,
  UserRoleCode,
  UserUpdatePayload,
} from '../../types/users'


interface UserEditFormProps {
  user: UserListItem

  allowedRoles: UserRoleCode[]

  onUpdateBasicData: (
    userId: string,
    payload: UserUpdatePayload,
  ) => Promise<UserListItem>

  onUpdateRole: (
    userId: string,
    roleCode: UserRoleCode,
  ) => Promise<UserListItem>

  onToggleStatus: (
    user: UserListItem,
  ) => Promise<UserListItem>

  onDelete: (
    user: UserListItem,
  ) => Promise<void>

  onCancel: () => void
}


interface EditFormState {
  rut: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string
  telefono: string
  role_code: UserRoleCode
}


function createFormState(
  user: UserListItem,
): EditFormState {
  return {
    rut: user.rut,
    nombres: user.nombres,
    apellido_paterno:
      user.apellido_paterno,
    apellido_materno:
      user.apellido_materno,
    telefono:
      user.telefono ?? '',
    role_code:
      user.roles.codigo,
  }
}


function UserEditForm({
  user,
  allowedRoles,
  onUpdateBasicData,
  onUpdateRole,
  onToggleStatus,
  onDelete,
  onCancel,
}: UserEditFormProps) {
  const [form, setForm] =
    useState<EditFormState>(() =>
      createFormState(user),
    )

  const [currentUser, setCurrentUser] =
    useState<UserListItem>(user)

  const [loadingAction, setLoadingAction] =
    useState<
      | 'basic'
      | 'role'
      | 'status'
      | 'delete'
      | null
    >(null)

  const [error, setError] =
    useState<string | null>(null)

  const [success, setSuccess] =
    useState<string | null>(null)


  useEffect(() => {
    setCurrentUser(user)
    setForm(createFormState(user))
    setError(null)
    setSuccess(null)
  }, [user])


  const isLoading =
    loadingAction !== null


  /**
   * Actualiza campos simples del formulario.
   */
  const updateField = <
    K extends keyof EditFormState,
  >(
    field: K,
    value: EditFormState[K],
  ) => {
    setError(null)
    setSuccess(null)

    setForm((current) => ({
      ...current,
      [field]: value,
    }))
  }


  /**
   * Guarda únicamente los datos básicos.
   */
  const handleSaveBasicData = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()

    if (isLoading) {
      return
    }

    setError(null)
    setSuccess(null)
    setLoadingAction('basic')

    try {
      const updatedUser =
        await onUpdateBasicData(
          currentUser.id,
          {
            rut: form.rut.trim(),
            nombres:
              form.nombres.trim(),
            apellido_paterno:
              form.apellido_paterno.trim(),
            apellido_materno:
              form.apellido_materno.trim(),
            telefono:
              form.telefono.trim()
              || null,
          },
        )

      setCurrentUser(updatedUser)

      setForm((current) => ({
        ...current,
        rut: updatedUser.rut,
        nombres:
          updatedUser.nombres,
        apellido_paterno:
          updatedUser.apellido_paterno,
        apellido_materno:
          updatedUser.apellido_materno,
        telefono:
          updatedUser.telefono ?? '',
      }))

      setSuccess(
        'Datos del usuario actualizados correctamente.',
      )

    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : 'No fue posible actualizar el usuario.',
      )

    } finally {
      setLoadingAction(null)
    }
  }


  /**
   * Cambia el rol utilizando el endpoint específico.
   */
  const handleChangeRole = async () => {
    if (isLoading) {
      return
    }

    if (
      form.role_code
      === currentUser.roles.codigo
    ) {
      setError(
        'El usuario ya posee el rol seleccionado.',
      )

      return
    }

    setError(null)
    setSuccess(null)
    setLoadingAction('role')

    try {
      const updatedUser =
        await onUpdateRole(
          currentUser.id,
          form.role_code,
        )

      setCurrentUser(updatedUser)

      setForm((current) => ({
        ...current,
        role_code:
          updatedUser.roles.codigo,
      }))

      setSuccess(
        'Rol actualizado correctamente.',
      )

    } catch (roleError) {
      setError(
        roleError instanceof Error
          ? roleError.message
          : 'No fue posible cambiar el rol.',
      )

    } finally {
      setLoadingAction(null)
    }
  }


  /**
   * Activa o desactiva según el estado actual.
   */
  const handleToggleStatus = async () => {
    if (isLoading) {
      return
    }

    setError(null)
    setSuccess(null)
    setLoadingAction('status')

    try {
      const updatedUser =
        await onToggleStatus(
          currentUser,
        )

      setCurrentUser(updatedUser)

      setSuccess(
        updatedUser.activo
          ? 'Usuario activado correctamente.'
          : 'Usuario desactivado correctamente.',
      )

    } catch (statusError) {
      setError(
        statusError instanceof Error
          ? statusError.message
          : 'No fue posible cambiar el estado.',
      )

    } finally {
      setLoadingAction(null)
    }
  }


  /**
   * Confirma y ejecuta el borrado lógico.
   */
  const handleDelete = async () => {
    if (isLoading) {
      return
    }

    const fullName =
      `${currentUser.nombres} `
      + `${currentUser.apellido_paterno}`

    const confirmed = window.confirm(
      `¿Estás seguro de que deseas eliminar a ${fullName}?\n\n`
      + 'El usuario dejará de aparecer en HuellAPP.',
    )

    if (!confirmed) {
      return
    }

    setError(null)
    setSuccess(null)
    setLoadingAction('delete')

    try {
      await onDelete(currentUser)

    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : 'No fue posible eliminar el usuario.',
      )

      setLoadingAction(null)
    }
  }


  return (
    <section>
      <h3>
        Editar usuario
      </h3>

      <p>
        {currentUser.nombres}{' '}
        {currentUser.apellido_paterno}{' '}
        {currentUser.apellido_materno}
      </p>


      {/* ======================================================
          DATOS BÁSICOS
          ====================================================== */}

      <form onSubmit={handleSaveBasicData}>
        <div>
          <label htmlFor="edit-user-rut">
            RUT
          </label>

          <input
            id="edit-user-rut"
            type="text"
            value={form.rut}
            onChange={(event) => {
              updateField(
                'rut',
                event.target.value,
              )
            }}
            disabled={isLoading}
            required
          />
        </div>


        <div>
          <label htmlFor="edit-user-names">
            Nombres
          </label>

          <input
            id="edit-user-names"
            type="text"
            value={form.nombres}
            onChange={(event) => {
              updateField(
                'nombres',
                event.target.value,
              )
            }}
            disabled={isLoading}
            required
          />
        </div>


        <div>
          <label htmlFor="edit-user-lastname-1">
            Apellido paterno
          </label>

          <input
            id="edit-user-lastname-1"
            type="text"
            value={
              form.apellido_paterno
            }
            onChange={(event) => {
              updateField(
                'apellido_paterno',
                event.target.value,
              )
            }}
            disabled={isLoading}
            required
          />
        </div>


        <div>
          <label htmlFor="edit-user-lastname-2">
            Apellido materno
          </label>

          <input
            id="edit-user-lastname-2"
            type="text"
            value={
              form.apellido_materno
            }
            onChange={(event) => {
              updateField(
                'apellido_materno',
                event.target.value,
              )
            }}
            disabled={isLoading}
            required
          />
        </div>


        <div>
          <label htmlFor="edit-user-email">
            Correo electrónico
          </label>

          <input
            id="edit-user-email"
            type="email"
            value={currentUser.email}
            disabled
          />

          <small>
            El correo no se modifica desde
            este formulario.
          </small>
        </div>


        <div>
          <label htmlFor="edit-user-phone">
            Teléfono
          </label>

          <input
            id="edit-user-phone"
            type="tel"
            value={form.telefono}
            onChange={(event) => {
              updateField(
                'telefono',
                event.target.value,
              )
            }}
            disabled={isLoading}
          />
        </div>


        <button
          type="submit"
          disabled={isLoading}
        >
          {loadingAction === 'basic'
            ? 'Guardando...'
            : 'Guardar cambios'}
        </button>
      </form>


      <hr />


      {/* ======================================================
          ROL
          ====================================================== */}

      <div>
        <h4>
          Rol
        </h4>

        <select
          value={form.role_code}
          onChange={(event) => {
            const selectedRole =
              event.target
                .value as UserRoleCode

            updateField(
              'role_code',
              selectedRole,
            )
          }}
          disabled={isLoading}
        >
          {allowedRoles.map((role) => (
            <option
              key={role}
              value={role}
            >
              {role}
            </option>
          ))}
        </select>

        <button
          type="button"
          onClick={() => {
            void handleChangeRole()
          }}
          disabled={isLoading}
        >
          {loadingAction === 'role'
            ? 'Actualizando rol...'
            : 'Cambiar rol'}
        </button>
      </div>


      <hr />


      {/* ======================================================
          ESTADO
          ====================================================== */}

      <div>
        <h4>
          Estado
        </h4>

        <p>
          Estado actual:{' '}
          <strong>
            {currentUser.activo
              ? 'Activo'
              : 'Inactivo'}
          </strong>
        </p>

        <button
          type="button"
          onClick={() => {
            void handleToggleStatus()
          }}
          disabled={isLoading}
        >
          {loadingAction === 'status'
            ? 'Procesando...'
            : currentUser.activo
              ? 'Desactivar usuario'
              : 'Activar usuario'}
        </button>
      </div>


      <hr />


      {/* ======================================================
          ELIMINACIÓN
          ====================================================== */}

      <div>
        <h4>
          Eliminar usuario
        </h4>

        <p>
          Esta acción eliminará al usuario
          del mantenedor de HuellAPP.
        </p>

        <button
          type="button"
          onClick={() => {
            void handleDelete()
          }}
          disabled={isLoading}
        >
          {loadingAction === 'delete'
            ? 'Eliminando...'
            : 'Eliminar usuario'}
        </button>
      </div>


      {/* ======================================================
          MENSAJES
          ====================================================== */}

      {success && (
        <p
          role="status"
          aria-live="polite"
        >
          {success}
        </p>
      )}

      {error && (
        <p
          role="alert"
          aria-live="assertive"
        >
          {error}
        </p>
      )}


      <div>
        <button
          type="button"
          onClick={onCancel}
          disabled={isLoading}
        >
          Cerrar edición
        </button>
      </div>
    </section>
  )
}


export default UserEditForm