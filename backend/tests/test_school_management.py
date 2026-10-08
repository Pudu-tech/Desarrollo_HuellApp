"""HuellAPP · Regresión de contratos, catálogo y errores de la ficha escolar.

No se conecta a Supabase: usa el cliente simulado para comprobar contratos HTTP.
Ejecutar desde backend con python -m unittest discover -s tests.
"""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4

from fastapi import HTTPException
from pydantic import ValidationError
from starlette.requests import Request

from app.api import catalogos, colegios
from app.core.resource_integrity import raise_school_resource_conflict
from app.schemas.cursos import CursoCreate
from app.schemas.salas import SalaCreate, SalaUpdate


class SchoolManagementTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_course_catalog_contract(self):
        client = Mock()
        level = {"id": str(uuid4()), "codigo": "NIVEL_TEST", "nombre": "Nivel de prueba", "orden": 1}
        client.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = [level]
        with patch.object(catalogos, "get_supabase_client", return_value=client):
            items = catalogos.listar_niveles_curso(SimpleNamespace())
        client.table.assert_called_once_with("niveles_curso")
        client.table.return_value.select.return_value.eq.assert_called_once_with("activo", True)
        client.table.return_value.select.return_value.eq.return_value.order.assert_called_once_with("orden")
        self.assertEqual(items[0].codigo, level["codigo"])
        self.assertEqual(str(items[0].id), level["id"])

    async def test_school_delete_contract_and_context(self):
        actor, school, request_id = uuid4(), uuid4(), uuid4()
        request = Request({"type": "http", "headers": [(b"user-agent", b"school-test")],
                           "client": ("127.0.0.1", 9999), "state": {"request_id": request_id}})
        for result, expected in (({"ok": True}, None),
                                 ({"ok": False, "error_code": "SCHOOL_HAS_FUTURE_ASSIGNMENTS"}, 409),
                                 ({"ok": False, "error_code": "FORBIDDEN"}, 403),
                                 ({"ok": False, "error_code": "SCHOOL_NOT_FOUND"}, 404),
                                 (None, 500)):
            client = Mock()
            client.rpc.return_value.execute.return_value.data = result
            with patch.object(colegios, "get_supabase_client", return_value=client):
                if expected is None:
                    self.assertIsNone(colegios.eliminar_colegio(request, school, SimpleNamespace(id=actor)))
                else:
                    with self.assertRaises(HTTPException) as error:
                        colegios.eliminar_colegio(request, school, SimpleNamespace(id=actor))
                    self.assertEqual(error.exception.status_code, expected)
            name, params = client.rpc.call_args.args
            self.assertEqual(name, "eliminar_colegio_atomico")
            self.assertEqual(params["p_actor_user_id"], str(actor))
            self.assertEqual(params["p_colegio_id"], str(school))
            self.assertEqual(params["p_request_id"], str(request_id))
            client.table.assert_not_called()

    def test_resource_integrity_errors_hide_sql_details(self):
        for code in ("RESOURCE_SCHOOL_IMMUTABLE", "SCHOOL_RESOURCE_UNAVAILABLE"):
            with self.assertRaises(HTTPException) as error:
                raise_school_resource_conflict(RuntimeError(f"SQL PRIVATE DETAIL {code}"))
            self.assertEqual(error.exception.status_code, 409)
            self.assertNotIn("PRIVATE", error.exception.detail)
        self.assertIsNone(raise_school_resource_conflict(RuntimeError("unrelated failure")))

    def test_existing_payload_validation(self):
        school, level = uuid4(), uuid4()
        course = CursoCreate(colegio_id=school, nivel_curso_id=level, seccion=" b ", anio=2026)
        self.assertEqual(course.seccion, "B")
        for section, year in (("AA", 2026), ("A", 1999), ("A", 2101)):
            with self.assertRaises(ValidationError):
                CursoCreate(colegio_id=school, nivel_curso_id=level, seccion=section, anio=year)
        with self.assertRaises(ValidationError):
            SalaCreate(colegio_id=school, nombre=" ", capacidad=30)
        with self.assertRaises(ValidationError):
            SalaCreate(colegio_id=school, nombre="Sala", capacidad=0)
        self.assertIsNone(SalaUpdate(capacidad=None).capacidad)


if __name__ == "__main__":
    unittest.main()
