/**
 * HuellAPP
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

  const handleOpenCreateForm = () => {
    setEditingUser(null)
    setSuccessMessage(null)
    setError(null)
    setShowCreateForm(true)
  }


  const handleCancelCreate = () => {
    setShowCreateForm(false)
  }


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

  const handleOpenEdit = (
    selectedUser: UserListItem,
  ) => {
    setShowCreateForm(false)
    setSuccessMessage(null)
    setError(null)
    setEditingUser(selectedUser)
  }


  const handleCancelEdit = () => {
    setEditingUser(null)
  }


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
    <section>
      <header>
        <h2>
          Usuarios
        </h2>

        <p>
          Administración de usuarios de HuellAPP.
        </p>
      </header>


      {!showCreateForm
        && !editingUser && (
          <div>
            <button
              type="button"
              onClick={handleOpenCreateForm}
            >
              Crear nuevo usuario
            </button>
          </div>
        )}


      {successMessage && (
        <p
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


      <hr />


      {loading && (
        <p>
          Cargando usuarios...
        </p>
      )}


      {!loading && error && (
        <div>
          <p role="alert">
            {error}
          </p>

          <button
            type="button"
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
          <p>
            No hay usuarios registrados.
          </p>
        )}


      {!loading
        && !error
        && users.length > 0 && (
          <table>
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

                  <td>
                    {item.nombres}{' '}
                    {item.apellido_paterno}{' '}
                    {item.apellido_materno}
                  </td>

                  <td>
                    {item.email}
                  </td>

                  <td>
                    {item.telefono ?? '-'}
                  </td>

                  <td>
                    {item.roles.nombre}
                  </td>

                  <td>
                    {item.activo
                      ? 'Activo'
                      : 'Inactivo'}
                  </td>

                  <td>
                    <button
                      type="button"
                      onClick={() => {
                        handleOpenEdit(item)
                      }}
                    >
                      Editar usuario
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
    </section>
  )
}


export default UsuariosPage