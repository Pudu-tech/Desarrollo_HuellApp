/**
 * HuellApp
 * Mantenedor de usuarios.
 *
 * Funcionalidades:
 * - listar usuarios;
 * - crear e invitar usuarios;
 * - editar datos básicos;
 * - cambiar correo electrónico;
 * - cambiar roles;
 * - activar/desactivar;
 * - eliminar mediante borrado lógico.
 */

import {
  useEffect,
  useState,
} from 'react'

import UserCreateForm from '../components/users/UserCreateForm'
import UserEditForm from '../components/users/UserEditForm'
import '../styles/usuarios.css'

import { useAuth } from '../contexts/AuthContext'

import {
  activateUser,
  changeUserEmail,
  createUser,
  deactivateUser,
  deleteUser,
  getUsers,
  updateUser,
  updateUserRole,
} from '../services/usersService'

import type {
  UserListItem,
  UserRoleCode,
  UserUpdatePayload,
} from '../types/users'


/**
 * Orquesta listado, creación, edición y operaciones administrativas.
 * Los servicios existentes conservan los flujos de invitación y auditoría.
 */
function UsuariosPage() {
  const { user } = useAuth()

  const [users, setUsers] =
    useState<UserListItem[]>([])

  const [loading, setLoading] =
    useState(true)

  const [error, setError] =
    useState<string | null>(null)

  const [successMessage, setSuccessMessage] =
    useState<string | null>(null)

  const [showCreateForm, setShowCreateForm] =
    useState(false)

  const [editingUser, setEditingUser] =
    useState<UserListItem | null>(null)


/**
 * Recupera el listado administrativo desde la API.
 */
  const loadUsers = async () => {
    setLoading(true)
    setError(null)

    try {
      const result =
        await getUsers()

      setUsers(result)

    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : 'No fue posible obtener los usuarios.',
      )

    } finally {
      setLoading(false)
    }
  }


  useEffect(() => {
    void loadUsers()
  }, [])


  const allowedRoles: UserRoleCode[] =
    user?.role_code === 'SUPERADMIN'
      ? [
          'SUPERADMIN',
          'DIRECTIVA',
          'COORDINADOR',
          'MONITOR',
        ]
      : [
          'DIRECTIVA',
          'COORDINADOR',
          'MONITOR',
        ]


  // ==========================================================
  // CREACIÓN
  // ==========================================================

/**
 * Abre el formulario de invitación de usuarios.
 */
  const handleOpenCreateForm = () => {
    setEditingUser(null)
    setSuccessMessage(null)
    setError(null)
    setShowCreateForm(true)
  }


/**
 * Cierra la creación sin enviar datos.
 */
  const handleCancelCreate = () => {
    setShowCreateForm(false)
  }


/**
 * Sincroniza la vista después de una creación exitosa.
 */
  const handleUserCreated = async (
    createdUser: UserListItem,
  ) => {
    setShowCreateForm(false)

    setSuccessMessage(
      `Usuario ${createdUser.email} creado correctamente. `
      + 'Se envió una invitación al correo registrado.',
    )

    await loadUsers()
  }


  // ==========================================================
  // EDICIÓN
  // ==========================================================

/**
 * Selecciona el usuario que se editará.
 */
  const handleOpenEdit = (
    selectedUser: UserListItem,
  ) => {
    setShowCreateForm(false)
    setSuccessMessage(null)
    setError(null)
    setEditingUser(selectedUser)
  }


/**
 * Regresa al listado sin aplicar cambios adicionales.
 */
  const handleCancelEdit = () => {
    setEditingUser(null)
  }


/**
 * Actualiza únicamente los datos personales editables.
 */
  const handleUpdateBasicData = async (
    userId: string,
    payload: UserUpdatePayload,
  ): Promise<UserListItem> => {
    const updatedUser =
      await updateUser(
        userId,
        payload,
      )

    setUsers((current) =>
      current.map((item) =>
        item.id === updatedUser.id
          ? updatedUser
          : item,
      ),
    )

    setEditingUser(updatedUser)

    return updatedUser
  }


  // ==========================================================
  // CAMBIO DE CORREO
  // ==========================================================

/**
 * Usa el flujo separado de cambio de correo; no modifica contraseña.
 */
  const handleUpdateEmail = async (
    userId: string,
    email: string,
  ): Promise<UserListItem> => {
    const updatedUser =
      await changeUserEmail(
        userId,
        { email },
      )

    setUsers((current) =>
      current.map((item) =>
        item.id === updatedUser.id
          ? updatedUser
          : item,
      ),
    )

    setEditingUser(updatedUser)

    return updatedUser
  }


  // ==========================================================
  // CAMBIO DE ROL
  // ==========================================================

/**
 * Solicita cambio de rol mediante su endpoint específico.
 */
  const handleUpdateRole = async (
    userId: string,
    roleCode: UserRoleCode,
  ): Promise<UserListItem> => {
    const updatedUser =
      await updateUserRole(
        userId,
        {
          role_code: roleCode,
        },
      )

    setUsers((current) =>
      current.map((item) =>
        item.id === updatedUser.id
          ? updatedUser
          : item,
      ),
    )

    setEditingUser(updatedUser)

    return updatedUser
  }


  // ==========================================================
  // ESTADO
  // ==========================================================

/**
 * Activa o desactiva la cuenta sin eliminar su historial.
 */
  const handleToggleStatus = async (
    selectedUser: UserListItem,
  ): Promise<UserListItem> => {
    const updatedUser =
      selectedUser.activo
        ? await deactivateUser(
            selectedUser.id,
          )
        : await activateUser(
            selectedUser.id,
          )

    setUsers((current) =>
      current.map((item) =>
        item.id === updatedUser.id
          ? updatedUser
          : item,
      ),
    )

    setEditingUser(updatedUser)

    return updatedUser
  }


  // ==========================================================
  // ELIMINACIÓN
  // ==========================================================

/**
 * Ejecuta el flujo de eliminación existente, sin alterar su semántica.
 */
  const handleDeleteUser = async (
    selectedUser: UserListItem,
  ): Promise<void> => {
    await deleteUser(
      selectedUser.id,
    )

    setEditingUser(null)

    setSuccessMessage(
      `Usuario ${selectedUser.email} eliminado correctamente.`,
    )

    await loadUsers()
  }


  return (
    <section className="users-page">
      <header className="users-heading">
        <div>
          <h1>Usuarios</h1>
          <p>Administración de usuarios de HuellApp.</p>
        </div>
        {!showCreateForm && !editingUser && (
          <button
            className="users-primary"
            type="button"
            onClick={handleOpenCreateForm}
          >
            + Crear nuevo usuario
          </button>
        )}
      </header>

      {successMessage && (
        <p
          className="users-message users-message--success"
          role="status"
          aria-live="polite"
        >
          {successMessage}
        </p>
      )}


      {showCreateForm && (
        <UserCreateForm
          allowedRoles={allowedRoles}
          onCreate={createUser}
          onCreated={(createdUser) => {
            void handleUserCreated(
              createdUser,
            )
          }}
          onCancel={handleCancelCreate}
        />
      )}


      {editingUser && (
        <UserEditForm
          user={editingUser}
          allowedRoles={allowedRoles}
          onUpdateBasicData={
            handleUpdateBasicData
          }
          onUpdateEmail={
            handleUpdateEmail
          }
          onUpdateRole={
            handleUpdateRole
          }
          onToggleStatus={
            handleToggleStatus
          }
          onDelete={
            handleDeleteUser
          }
          onCancel={
            handleCancelEdit
          }
        />
      )}


      <div className="users-panel">
        <div className="users-panel-heading">
          <div>
            <h2>Usuarios registrados</h2>
            <p>{loading ? 'Cargando...' : `${users.length} usuarios`}</p>
          </div>
          <button
            type="button"
            className="users-secondary"
            onClick={() => { void loadUsers() }}
            disabled={loading}
          >
            Actualizar
          </button>
        </div>

      {loading && (
        <p className="users-feedback" role="status">
          Cargando usuarios...
        </p>
      )}


      {!loading && error && (
        <div className="users-feedback">
          <p role="alert" className="users-message users-message--error">
            {error}
          </p>

          <button
            type="button"
            className="users-secondary"
            onClick={() => {
              void loadUsers()
            }}
          >
            Reintentar
          </button>
        </div>
      )}


      {!loading
        && !error
        && users.length === 0 && (
          <p className="users-feedback">
            No hay usuarios registrados.
          </p>
        )}


      {!loading
        && !error
        && users.length > 0 && (
          <div className="users-table-scroll">
          <table className="users-table">
            <thead>
              <tr>
                <th scope="col">
                  RUT
                </th>

                <th scope="col">
                  Nombre
                </th>

                <th scope="col">
                  Correo
                </th>

                <th scope="col">
                  Teléfono
                </th>

                <th scope="col">
                  Rol
                </th>

                <th scope="col">
                  Estado
                </th>

                <th scope="col">
                  Acciones
                </th>
              </tr>
            </thead>

            <tbody>
              {users.map((item) => (
                <tr key={item.id}>
                  <td>
                    {item.rut}
                  </td>

                  <td className="users-name">
                    {item.nombres}{' '}
                    {item.apellido_paterno}{' '}
                    {item.apellido_materno}
                  </td>

                  <td className="users-email">
                    {item.email}
                  </td>

                  <td>
                    {item.telefono ?? '-'}
                  </td>

                  <td>
                    <span className="users-role">{item.roles.nombre}</span>
                  </td>

                  <td>
                    <span className={`users-status ${item.activo ? 'users-status--active' : 'users-status--inactive'}`}>
                      {item.activo ? 'Activo' : 'Inactivo'}
                    </span>
                  </td>

                  <td>
                    <button
                      type="button"
                      className="users-action"
                      onClick={() => {
                        handleOpenEdit(item)
                      }}
                    >
                      Editar
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </div>
    </section>
  )
}


export default UsuariosPage