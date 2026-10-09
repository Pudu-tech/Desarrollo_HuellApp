"""Pruebas de contratos, permisos y conflictos del catálogo sin credenciales reales."""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4
from fastapi import HTTPException
from pydantic import ValidationError
from app.api import catalogo_academico as api
from app.schemas.catalogo_academico import RecursoAcademicoDatos


class CatalogoAcademicoTests(unittest.TestCase):
    def test_asignatura_compartida_proyecta_niveles_sin_cambiar_id(self):
        subject, first, second = [str(uuid4()) for _ in range(3)]
        row = api.proyectar_ramo({"id": subject, "nivel_curso_id": None,
                                 "ramo_nivel": [{"nivel_curso_id": first}, {"nivel_curso_id": second}]})
        self.assertEqual(row["id"], subject)
        self.assertEqual(row["nivel_ids"], [first, second])

    def test_cliente_no_puede_inyectar_actor_estado_o_niveles_duplicados(self):
        level = str(uuid4())
        for injected in ({"activo": False}, {"created_by": str(uuid4())}, {"deleted_at": "2026-01-01"}):
            with self.assertRaises(ValidationError):
                RecursoAcademicoDatos.model_validate({"nombre": "Asignatura", "nivel_ids": [level], **injected})
        for payload in ({"nombre": "Asignatura", "nivel_ids": []},
                        {"nombre": "Asignatura", "nivel_ids": [level, level]},
                        {"nombre": "Espacio"},
                        {"nombre": "Mixto", "nivel_ids": [level], "ramo_id": str(uuid4())}):
            with self.assertRaises(ValidationError):
                RecursoAcademicoDatos.model_validate(payload)

    def test_rpc_usa_actor_autenticado_y_metadatos_del_request(self):
        actor = SimpleNamespace(id=uuid4())
        request = SimpleNamespace(state=SimpleNamespace(request_id=uuid4()),
                                  client=SimpleNamespace(host="127.0.0.1"), headers={"user-agent": "test"})
        result_id = str(uuid4())
        db = Mock()
        db.rpc.return_value.execute.return_value.data = {"ok": True, "registro": {
            "id": result_id, "nombre": "Asignatura", "activo": True, "nivel_ids": [str(uuid4())]}}
        datos = RecursoAcademicoDatos(nombre="Asignatura", nivel_ids=[uuid4()], descripcion=None)
        with patch.object(api, "get_supabase_client", return_value=db):
            saved = api.ejecutar_operacion("asignaturas", "CREATE", None, datos, actor, request)
        self.assertEqual(str(saved.id), result_id)
        rpc_name, payload = db.rpc.call_args.args
        self.assertEqual(rpc_name, "gestionar_catalogo_academico_atomico")
        self.assertEqual(payload["p_actor_user_id"], str(actor.id))
        self.assertEqual(payload["p_request_id"], str(request.state.request_id))
        self.assertEqual(payload["p_datos"]["descripcion"], None)
        self.assertNotIn("activo", payload["p_datos"])

    def test_conflictos_y_permisos_del_rpc_se_conservan(self):
        db = Mock()
        request = SimpleNamespace(state=SimpleNamespace(), client=None, headers={})
        for code, status in [("FORBIDDEN", 403), ("NOT_FOUND", 404), ("HAS_FUTURE_ASSIGNMENTS", 409), ("INVALID_LEVELS", 422)]:
            db.rpc.return_value.execute.return_value.data = {"ok": False, "error_code": code}
            with patch.object(api, "get_supabase_client", return_value=db), self.assertRaises(HTTPException) as error:
                api.ejecutar_operacion("asignaturas", "DELETE", uuid4(), None, SimpleNamespace(id=uuid4()), request)
            self.assertEqual(error.exception.status_code, status)

    def test_endpoints_exigen_permiso_de_la_accion(self):
        expected = {"GET": "VIEW", "POST": "CREATE", "PUT": "UPDATE", "DELETE": "DELETE"}
        for route in api.router.routes:
            method = next(iter(route.methods))
            if method not in expected:
                continue  # PATCH resuelve ACTIVATE/DEACTIVATE mediante require_permission.
            dependency = route.dependant.dependencies[0].call
            captured = dict(zip(dependency.__code__.co_freevars,
                                (cell.cell_contents for cell in dependency.__closure__)))
            self.assertEqual(captured["permission_code"], expected[method] + "_ACADEMIC_CATALOG")


if __name__ == "__main__":
    unittest.main()
