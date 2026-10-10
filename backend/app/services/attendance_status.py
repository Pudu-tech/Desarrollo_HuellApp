"""Estado operativo de asistencia sin alterar registros históricos."""
def effective_attendance_state(state, participation):
    if state == 'PENDIENTE' and participation == 'RECHAZADA':
        return 'NO_REQUERIDA'
    return state
