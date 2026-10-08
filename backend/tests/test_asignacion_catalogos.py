"""HuellAPP · Regresión de permisos y proyecciones de los catálogos de creación.

Usa respuestas simuladas: no conecta a Supabase ni modifica sus datos.
Ejecutar desde backend: python -m unittest discover -s tests.
"""
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4
from fastapi import HTTPException
from app.api import asignacion_catalogos as api


class Consulta:
    """Registra filtros para verificar el alcance de cada consulta de lectura."""
    def __init__(self, rows):
        self.rows = rows
        self.calls = []

    def select(self, value):
        self.calls.append(("select", value))
        return self

    def eq(self, field, value):
        self.calls.append(("eq", field, value))
        return self

    def is_(self, field, value):
        self.calls.append(("is", field, value))
        return self

    def in_(self, field, value):
        self.calls.append(("in", field, value))
        return self

    def order(self, value):
        self.calls.append(("order", value))
        return self

    def execute(self):
        return SimpleNamespace(data=self.rows)


class BaseSimulada:
    def __init__(self, rows):
        self.rows = rows
        self.queries = {}

    def table(self, name):
        query = Consulta(self.rows.get(name, []))
        self.queries[name] = query
        return query


class CatalogosAsignacionTests(unittest.IsolatedAsyncioTestCase):
    async def test_ramo_transversal_conserva_id_y_habilita_varios_niveles(self):
        subject, first, second = [str(uuid4()) for _ in range(3)]
        db = BaseSimulada({"ramos": [{"id": subject, "nombre": "Asignatura", "nivel_curso_id": None,
                                      "ramo_nivel": [{"nivel_curso_id": first}, {"nivel_curso_id": second}]}]})
        with patch.object(api, "get_supabase_client", return_value=db):
            result = api.listar_opciones_creacion(SimpleNamespace(role_code="SUPERADMIN"))
        self.assertEqual(str(result.ramos[0].id), subject)
        self.assertEqual([str(level) for level in result.ramos[0].nivel_ids], [first, second])

    async def test_creacion_filtra_tipos_y_proyecta_usuarios(self):
        user_id = str(uuid4())
        db = BaseSimulada({
            "tipos_actividad": [{"id": str(uuid4()), "nombre": "Reunión", "codigo": "REUNION"},
                                {"id": str(uuid4()), "nombre": "Capacitación", "codigo": "CAPACITACION"}],
            "usuarios": [{"id": user_id, "nombres": "Persona", "apellido_paterno": "Prueba",
                          "apellido_materno": None, "roles": {"codigo": "MONITOR"}}],
        })
        def permiso(_db, *, role_code, tipo_codigo):
            if tipo_codigo == "CAPACITACION":
                raise HTTPException(403, "Sin permiso")
        with patch.object(api, "get_supabase_client", return_value=db), patch.object(api, "_validar_permiso_tipo_actividad", side_effect=permiso):
            result = api.listar_opciones_creacion(SimpleNamespace(role_code="COORDINADOR"))
        self.assertEqual([item.codigo for item in result.tipos_actividad], ["REUNION"])
        self.assertEqual(str(result.participantes[0].id), user_id)
        self.assertNotIn("email", result.participantes[0].model_dump())
        self.assertIn(("in", "roles.codigo", ["DIRECTIVA", "COORDINADOR", "MONITOR"]), db.queries["usuarios"].calls)
        for table in ("usuarios", "colegios", "ramos"):
            self.assertIn(("eq", "activo", True), db.queries[table].calls)
            self.assertIn(("is", "deleted_at", "null"), db.queries[table].calls)

    async def test_recursos_se_restringen_al_colegio_activo(self):
        school = uuid4()
        db = BaseSimulada({})
        with patch.object(api, "get_supabase_client", return_value=db), patch.object(api, "_obtener_colegio_activo") as validate:
            result = api.listar_recursos_colegio_asignacion(school, SimpleNamespace())
        validate.assert_called_once_with(db, colegio_id=school)
        self.assertEqual(result.contactos, [])
        for table in ("cursos_colegio", "salas", "contactos_colegio"):
            self.assertIn(("eq", "colegio_id", str(school)), db.queries[table].calls)
            self.assertIn(("eq", "activo", True), db.queries[table].calls)
            self.assertIn(("is", "deleted_at", "null"), db.queries[table].calls)

    async def test_espacios_pertenecen_al_ramo_validado(self):
        subject = uuid4()
        db = BaseSimulada({})
        with patch.object(api, "get_supabase_client", return_value=db), patch.object(api, "_validar_ramo_activo") as validate:
            api.listar_espacios_asignacion(subject, SimpleNamespace())
        validate.assert_called_once_with(db, ramo_id=subject)
        for table in ("espacios_reflexion", "espacios_encuentro"):
            self.assertIn(("eq", "ramo_id", str(subject)), db.queries[table].calls)
            self.assertIn(("is", "deleted_at", "null"), db.queries[table].calls)

    async def test_monitor_no_accede_a_catalogos_de_gestion(self):
        with self.assertRaises(HTTPException) as error:
            api.listar_catalogos_asignaciones(SimpleNamespace(role_code="MONITOR"))
        self.assertEqual(error.exception.status_code, 403)

    def test_permisos_no_dependen_del_cliente(self):
        for route in api.router.routes:
            dependency = route.dependant.dependencies[0].call
            captured = dict(zip(dependency.__code__.co_freevars,
                                (cell.cell_contents for cell in dependency.__closure__)))
            expected = "VIEW_ASSIGNMENTS" if route.path == "/catalogos/asignaciones" else "REASSIGN_ASSIGNMENT" if any(path in route.path for path in ("/reasignacion", "/gestion-participantes")) else "UPDATE_ASSIGNMENT" if "/edicion" in route.path else "CREATE_ASSIGNMENT"
            self.assertEqual(captured["permission_code"], expected)

    def test_agregar_ofrece_personas_activas_sin_exponer_correo(self):
        db = BaseSimulada({'usuarios': [{'id': str(uuid4()), 'nombres': 'Ana', 'email': 'private@example.org'}]})
        with patch.object(api, 'get_supabase_client', return_value=db):
            result = api.opciones_gestion_participantes(SimpleNamespace())
        self.assertNotIn('email', result['participantes'][0])
        self.assertIn(('eq', 'activo', True), db.queries['usuarios'].calls)
        self.assertIn(('is', 'deleted_at', 'null'), db.queries['usuarios'].calls)
        self.assertIn(('eq', 'activo', True), db.queries['tipos_participacion'].calls)


if __name__ == "__main__":
    unittest.main()
