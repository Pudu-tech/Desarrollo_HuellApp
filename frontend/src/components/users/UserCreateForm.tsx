/**
 * HuellAPP
 * Formulario estructural para creación de usuarios.
 *
 * El diseño visual es deliberadamente básico.
 * La validación definitiva de negocio permanece en FastAPI.
 *
 * SECURITY
 * ------------------------------------------------------------
 * - El administrador no define la contraseña.
 * - El usuario establece su propia contraseña mediante
 *   la invitación enviada por Supabase Auth / Brevo.
 * - Las reglas de autorización definitivas permanecen
 *   en el backend.
 */

import {
  useEffect,
  useState,
  type FormEvent,
} from 'react'

import type {
  UserCreatePayload,
  UserListItem,
  UserRoleCode,
} from '../../types/users'


interface UserCreateFormProps {
  allowedRoles: UserRoleCode[]

  onCreate: (
    payload: UserCreatePayload,
  ) => Promise<UserListItem>

  onCreated: (
    user: UserListItem,
  ) => void

  onCancel: () => void
}


/**
 * Construye el estado inicial del formulario.
 */
function createInitialForm(
  allowedRoles: UserRoleCode[],
): UserCreatePayload {
  return {
    rut: '',
    nombres: '',
    apellido_paterno: '',
    apellido_materno: '',
    email: '',
    telefono: null,
    role_code:
      allowedRoles[0] ?? 'MONITOR',
  }
}


/**
 * Presenta la creación sin permitir que el administrador elija contraseñas.
 * La invitación se tramita por el servicio existente, sin cambios de correo.
 */
function UserCreateForm({
  allowedRoles,
  onCreate,
  onCreated,
  onCancel,
}: UserCreateFormProps) {
  const [form, setForm] =
    useState<UserCreatePayload>(() =>
      createInitialForm(allowedRoles),
    )

  const [loading, setLoading] =
    useState(false)

  const [error, setError] =
    useState<string | null>(null)


  /**
   * Mantiene seleccionado únicamente un rol
   * disponible para el actor actual.
   */
  useEffect(() => {
    if (allowedRoles.length === 0) {
      return
    }

    if (
      allowedRoles.includes(
        form.role_code,
      )
    ) {
      return
    }

    const fallbackRole =
      allowedRoles[0]

    if (!fallbackRole) {
      return
    }

    setForm((current) => ({
      ...current,
      role_code: fallbackRole,
    }))
  }, [
    allowedRoles,
    form.role_code,
  ])


  /**
   * Actualiza un campo individual del formulario.
   *
   * Al modificar un valor se elimina el error anterior,
   * permitiendo al usuario corregirlo sin mantener
   * mensajes obsoletos en pantalla.
   */
  const updateField = <
    K extends keyof UserCreatePayload,
  >(
    field: K,
    value: UserCreatePayload[K],
  ) => {
    setError(null)

    setForm((current) => ({
      ...current,
      [field]: value,
    }))
  }


  /**
   * Envía la creación del usuario al backend.
   *
   * Los mensajes funcionales entregados por FastAPI,
   * por ejemplo RUT o correo duplicado, se muestran
   * directamente al usuario.
   */
/**
 * Valida el formulario y delega la creación al callback existente.
 */
  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()

    if (loading) {
      return
    }

    if (allowedRoles.length === 0) {
      setError(
        'No existen roles disponibles para asignar.',
      )

      return
    }

    setError(null)
    setLoading(true)

    try {
      const createdUser = await onCreate({
        ...form,
        rut: form.rut.trim(),
        nombres: form.nombres.trim(),
        apellido_paterno:
          form.apellido_paterno.trim(),
        apellido_materno:
          form.apellido_materno.trim(),
        email: form.email.trim(),
        telefono:
          form.telefono?.trim() || null,
      })

      onCreated(createdUser)

    } catch (submitError) {
      if (submitError instanceof Error) {
        setError(submitError.message)
      } else {
        setError(
          'No fue posible crear el usuario.',
        )
      }

    } finally {
      setLoading(false)
    }
  }


  return (
    <form className="users-create-form" onSubmit={handleSubmit}>
      <h3>Crear nuevo usuario</h3>
      <p className="users-form-intro">Completa los datos para enviar la invitación al nuevo usuario.</p>


      <div>
        <label htmlFor="user-rut">
          RUT
        </label>

        <input
          id="user-rut"
          name="rut"
          type="text"
          autoComplete="off"
          placeholder="12345678-9"
          value={form.rut}
          onChange={(event) => {
            updateField(
              'rut',
              event.target.value,
            )
          }}
          disabled={loading}
          required
        />
      </div>


      <div>
        <label htmlFor="user-nombres">
          Nombres
        </label>

        <input
          id="user-nombres"
          name="nombres"
          type="text"
          autoComplete="given-name"
          value={form.nombres}
          onChange={(event) => {
            updateField(
              'nombres',
              event.target.value,
            )
          }}
          disabled={loading}
          required
        />
      </div>


      <div>
        <label htmlFor="user-apellido-paterno">
          Apellido paterno
        </label>

        <input
          id="user-apellido-paterno"
          name="apellidoPaterno"
          type="text"
          autoComplete="family-name"
          value={form.apellido_paterno}
          onChange={(event) => {
            updateField(
              'apellido_paterno',
              event.target.value,
            )
          }}
          disabled={loading}
          required
        />
      </div>


      <div>
        <label htmlFor="user-apellido-materno">
          Apellido materno
        </label>

        <input
          id="user-apellido-materno"
          name="apellidoMaterno"
          type="text"
          value={form.apellido_materno}
          onChange={(event) => {
            updateField(
              'apellido_materno',
              event.target.value,
            )
          }}
          disabled={loading}
          required
        />
      </div>


      <div>
        <label htmlFor="user-email">
          Correo electrónico
        </label>

        <input
          id="user-email"
          name="email"
          type="email"
          autoComplete="email"
          value={form.email}
          onChange={(event) => {
            updateField(
              'email',
              event.target.value,
            )
          }}
          disabled={loading}
          required
        />
      </div>


      <div>
        <label htmlFor="user-phone">
          Teléfono
        </label>

        <input
          id="user-phone"
          name="telefono"
          type="tel"
          autoComplete="tel"
          value={form.telefono ?? ''}
          onChange={(event) => {
            updateField(
              'telefono',
              event.target.value,
            )
          }}
          disabled={loading}
        />
      </div>


      <div>
        <label htmlFor="user-role">
          Rol
        </label>

        <select
          id="user-role"
          name="role"
          value={form.role_code}
          onChange={(event) => {
            const selectedRole =
              event.target.value as UserRoleCode

            updateField(
              'role_code',
              selectedRole,
            )
          }}
          disabled={
            loading
            || allowedRoles.length === 0
          }
          required
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
      </div>


      {/* ======================================================
          ACCIONES
          ====================================================== */}

      <div className="users-form-actions">
        <button
          className="users-primary"
          type="submit"
          disabled={
            loading
            || allowedRoles.length === 0
          }
        >
          {loading
            ? 'Creando usuario...'
            : 'Crear usuario'}
        </button>

        <button
          type="button"
          className="users-secondary"
          onClick={onCancel}
          disabled={loading}
        >
          Cancelar
        </button>
      </div>


      {/* ======================================================
          ERROR POST-CREACIÓN
          ====================================================== */}

      {error && (
        <p
          className="users-message users-message--error"
          role="alert"
          aria-live="assertive"
        >
          {error}
        </p>
      )}
    </form>
  )
}


export default UserCreateForm