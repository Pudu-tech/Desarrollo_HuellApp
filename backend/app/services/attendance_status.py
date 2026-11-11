"""HuellApp · Estado operativo de asistencia.

RESPONSABILIDADES
------------------------------------------------------------
- Derivar el estado mostrado a partir de participación y asistencia persistidas.

ESTADO ACTUAL
------------------------------------------------------------
- No reescribe los registros históricos para representar asistencia no requerida.

SECURITY
------------------------------------------------------------
La proyección de estado no concede permisos ni reemplaza la autorización
del endpoint que consulta el registro.
"""
def effective_attendance_state(state, participation):
    """Muestra NO_REQUERIDA para una asistencia pendiente con participación rechazada."""
    if state == 'PENDIENTE' and participation == 'RECHAZADA':
        return 'NO_REQUERIDA'
    return state
