/**
 * HuellApp
 * Formulario funcional de edición de usuarios.
 *
 * Permite:
 * - editar datos básicos;
 * - cambiar correo electrónico;
 * - cambiar rol;
 * - activar/desactivar;
 * - eliminar usuario.
 *
 * Cada operación utiliza su endpoint específico.
 * La confirmación utiliza el formato común aprobado para toda la aplicación.
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
import { useConfirmation } from '../../hooks/useConfirmation'
import { useAuth } from '../../contexts/AuthContext'
import { resendPasswordInvitation } from '../../services/usersService'


interface UserEditFormProps {
  user: UserListItem

  allowedRoles: UserRoleCode[]

  onUpdateBasicData: (
    userId: string,
    payload: UserUpdatePayload,
  ) => Promise<UserListItem>

  onUpdateEmail: (
    userId: string,
    email: string,
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


/**
 * Convierte el usuario recibido al estado editable de datos y rol.
 */
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


/**
 * Presenta las secciones de datos, correo, rol, estado y eliminación.
 * Cada sección utiliza su operación independiente para no mezclar efectos.
 */
function UserEditForm({
  user,
  allowedRoles,
  onUpdateBasicData,
  onUpdateEmail,
  onUpdateRole,
  onToggleStatus,
  onDelete,
  onCancel,
}: UserEditFormProps) {
  const { confirm, confirmationDialog } = useConfirmation()
  const { user: actor } = useAuth()
  const [form, setForm] =
    useState<EditFormState>(() =>
      createFormState(user),
    )

  const [currentUser, setCurrentUser] =
    useState<UserListItem>(user)

  const [showEmailEditor, setShowEmailEditor] =
    useState(false)

  const [newEmail, setNewEmail] =
    useState('')

  const [confirmEmail, setConfirmEmail] =
    useState('')

  const [loadingAction, setLoadingAction] =
    useState<
      | 'basic'
      | 'email'
      | 'role'
      | 'status'
      | 'delete'
      | 'invitation'
      | null
    >(null)

  const [error, setError] =
    useState<string | null>(null)

  const [success, setSuccess] =
    useState<string | null>(null)


  useEffect(() => {
    let active = true
    void Promise.resolve().then(() => {
      if (!active) return
      setCurrentUser(user)
      setForm(createFormState(user))
      setShowEmailEditor(false)
      setNewEmail('')
      setConfirmEmail('')
      setError(null)
      setSuccess(null)
    })
    return () => { active = false }
  }, [user])


  const isLoading =
    loadingAction !== null

  async function sendInvitation() {
    if (!await confirm({ title: 'Enviar nueva invitación', confirmLabel: 'Enviar correo',
      message: `Se enviará a ${currentUser.email} un enlace para establecer o restablecer su contraseña.` })) return
    setLoadingAction('invitation'); setError(null); setSuccess(null)
    try { await resendPasswordInvitation(currentUser.id); setSuccess('Correo de recuperación solicitado. El usuario debe abrir el enlace nuevo.') }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible enviar la invitación.') }
    finally { setLoadingAction(null) }
  }


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
 * Guarda los datos básicos sin modificar correo, rol ni estado.
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
 * Muestra el editor independiente de correo.
 */
  const handleOpenEmailEditor = () => {
    if (isLoading) {
      return
    }

    setNewEmail('')
    setConfirmEmail('')
    setError(null)
    setSuccess(null)
    setShowEmailEditor(true)
  }


/**
 * Descarta el correo temporal sin enviar cambios.
 */
  const handleCancelEmailChange = () => {
    if (isLoading) {
      return
    }

    setNewEmail('')
    setConfirmEmail('')
    setError(null)
    setShowEmailEditor(false)
  }


/**
 * Solicita cambio de correo conservando el UUID y la contraseña.
 */
  const handleChangeEmail = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()

    if (isLoading) {
      return
    }

    const normalizedEmail =
      newEmail.trim().toLowerCase()

    const normalizedConfirmation =
      confirmEmail.trim().toLowerCase()

    if (!normalizedEmail) {
      setError(
        'Debes ingresar el nuevo correo electrónico.',
      )
      return
    }

    if (
      normalizedEmail
      === currentUser.email.trim().toLowerCase()
    ) {
      setError(
        'El nuevo correo debe ser diferente al correo actual.',
      )
      return
    }

    if (
      normalizedEmail
      !== normalizedConfirmation
    ) {
      setError(
        'Los correos ingresados no coinciden.',
      )
      return
    }

    setError(null)
    setSuccess(null)
    setLoadingAction('email')

    try {
      const updatedUser =
        await onUpdateEmail(
          currentUser.id,
          normalizedEmail,
        )

      setCurrentUser(updatedUser)
      setNewEmail('')
      setConfirmEmail('')
      setShowEmailEditor(false)

      setSuccess(
        'Correo electrónico actualizado correctamente.',
      )

    } catch (emailError) {
      setError(
        emailError instanceof Error
          ? emailError.message
          : 'No fue posible cambiar el correo.',
      )

    } finally {
      setLoadingAction(null)
    }
  }


/**
 * Solicita el cambio de rol sin tocar otros datos.
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
 * Confirma la activación o desactivación reversible.
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
 * Solicita confirmación y delega la eliminación al flujo existente.
 */
  const handleDelete = async () => {
    if (isLoading) {
      return
    }

    const fullName =
      `${currentUser.nombres} `
      + `${currentUser.apellido_paterno}`

    const confirmed = await confirm({ title: '¿Eliminar usuario?',
      message: <>Vas a eliminar a <strong>{fullName}</strong>. El usuario dejará de aparecer en HuellApp.</>,
      confirmLabel: 'Sí, eliminar usuario' })

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
    <section className="users-editor">
      {confirmationDialog}
      {['SUPERADMIN', 'DIRECTIVA'].includes(actor?.role_code ?? '') && !(actor?.role_code === 'DIRECTIVA' && currentUser.roles.codigo === 'SUPERADMIN') &&
        <div className="users-form-section"><h4>Acceso y contraseña</h4><p>Envía un enlace nuevo si la invitación anterior venció o falló.</p>
          <button type="button" className="users-secondary" disabled={isLoading || !currentUser.activo} onClick={() => void sendInvitation()}>{loadingAction === 'invitation' ? 'Enviando…' : 'Enviar nueva invitación'}</button></div>}
      <h3>
        Editar usuario
      </h3>

      <p className="users-form-intro">
        {currentUser.nombres}{' '}
        {currentUser.apellido_paterno}{' '}
        {currentUser.apellido_materno}
      </p>


      {/* DATOS BÁSICOS */}

      <form className="users-basic-form" onSubmit={handleSaveBasicData}>
        <h4>Información personal</h4>
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
            value={form.apellido_paterno}
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
            value={form.apellido_materno}
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
          className="users-primary users-basic-save"
          type="submit"
          disabled={isLoading}
        >
          {loadingAction === 'basic'
            ? 'Guardando...'
            : 'Guardar cambios'}
        </button>
      </form>


      <hr />


      {/* CORREO ELECTRÓNICO */}

      <div className="users-edit-section users-email-section">
        <h4>
          Correo electrónico
        </h4>

        <p>
          Correo actual:{' '}
          <strong>
            {currentUser.email}
          </strong>
        </p>

        {!showEmailEditor && (
          <button
            type="button"
            className="users-secondary"
            onClick={handleOpenEmailEditor}
            disabled={isLoading}
          >
            Cambiar correo
          </button>
        )}

        {showEmailEditor && (
          <form className="users-email-form" onSubmit={handleChangeEmail}>
            <div>
              <label htmlFor="edit-user-new-email">
                Nuevo correo
              </label>

              <input
                id="edit-user-new-email"
                type="email"
                value={newEmail}
                onChange={(event) => {
                  setNewEmail(
                    event.target.value,
                  )
                  setError(null)
                  setSuccess(null)
                }}
                disabled={isLoading}
                autoComplete="off"
                required
              />
            </div>

            <div>
              <label htmlFor="edit-user-confirm-email">
                Confirmar nuevo correo
              </label>

              <input
                id="edit-user-confirm-email"
                type="email"
                value={confirmEmail}
                onChange={(event) => {
                  setConfirmEmail(
                    event.target.value,
                  )
                  setError(null)
                  setSuccess(null)
                }}
                disabled={isLoading}
                autoComplete="off"
                required
              />
            </div>

            <button
              className="users-primary"
              type="submit"
              disabled={isLoading}
            >
              {loadingAction === 'email'
                ? 'Cambiando correo...'
                : 'Guardar nuevo correo'}
            </button>

            {' '}

            <button
              className="users-secondary"
              type="button"
              onClick={handleCancelEmailChange}
              disabled={isLoading}
            >
              Cancelar
            </button>
          </form>
        )}
      </div>


      <hr />


      {/* ROL */}

      <div className="users-edit-section users-role-section">
        <h4>
          Rol
        </h4>

        <select
          value={form.role_code}
          onChange={(event) => {
            const selectedRole =
              event.target.value as UserRoleCode

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
          className="users-secondary"
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


      {/* ESTADO */}

      <div className="users-edit-section users-status-section">
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
          className="users-secondary"
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


      {/* ELIMINACIÓN */}

      <div className="users-edit-section users-delete-section">
        <h4>
          Eliminar usuario
        </h4>

        <p>
          Esta acción eliminará al usuario
          del mantenedor de HuellApp.
        </p>

        <button
          type="button"
          className="users-danger"
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


      {/* MENSAJES */}

      {success && (
        <p
          className="users-message users-message--success"
          role="status"
          aria-live="polite"
        >
          {success}
        </p>
      )}

      {error && (
        <p
          className="users-message users-message--error"
          role="alert"
          aria-live="assertive"
        >
          {error}
        </p>
      )}


      <div className="users-editor-footer">
        <button
          className="users-secondary"
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
