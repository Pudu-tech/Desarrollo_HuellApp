"""Pruebas locales: python -m unittest discover -s tests desde backend."""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4

from fastapi import HTTPException
from starlette.requests import Request

from app.api import cursos, salas


class ResourceDeletionTests(unittest.IsolatedAsyncioTestCase):
    async def call_delete(self, module, result=None, failure=None):
        resource_id, actor_id, request_id = uuid4(), uuid4(), uuid4()
        request = Request({
            "type": "http", "headers": [(b"user-agent", b"regression-test")],
            "client": ("127.0.0.1", 1234), "state": {"request_id": request_id},
        })
        client = Mock()
        client.rpc.return_value.execute.return_value.data = result
        if failure:
            client.rpc.return_value.execute.side_effect = failure
        with patch.object(module, "get_supabase_client", return_value=client):
            function = module.eliminar_curso if module is cursos else module.eliminar_sala
            response = function(request, resource_id, SimpleNamespace(id=actor_id))
        name, payload = client.rpc.call_args.args
        entity = "curso" if module is cursos else "sala"
        self.assertEqual(name, "eliminar_curso_atomico" if module is cursos else "eliminar_sala_atomica")
        self.assertEqual(payload[f"p_{entity}_id"], str(resource_id))
        self.assertEqual(payload["p_actor_user_id"], str(actor_id))
        self.assertEqual(payload["p_request_id"], str(request_id))
        self.assertEqual(payload["p_ip_address"], "127.0.0.1")
        self.assertEqual(payload["p_user_agent"], "regression-test")
        client.table.assert_not_called()
        return response

    async def test_success_and_audit_context(self):
        for module in (cursos, salas):
            with self.subTest(module=module.__name__):
                self.assertIsNone(await self.call_delete(module, {"ok": True}))

    async def test_domain_errors(self):
        for module, prefix in ((cursos, "COURSE"), (salas, "ROOM")):
            for code, expected in ((f"{prefix}_NOT_FOUND", 404),
                                   (f"{prefix}_HAS_FUTURE_ASSIGNMENTS", 409),
                                   ("FORBIDDEN", 403), ("ACTOR_NOT_FOUND", 403)):
                with self.subTest(code=code):
                    with self.assertRaises(HTTPException) as error:
                        await self.call_delete(module, {"ok": False, "error_code": code})
                    self.assertEqual(error.exception.status_code, expected)

    async def test_invalid_rpc_or_database_failure(self):
        for module in (cursos, salas):
            for result, failure in ((None, None), ([], None),
                                    ({"ok": False, "error_code": "UNKNOWN"}, None),
                                    (None, RuntimeError("audit insert failed"))):
                with self.subTest(result=result):
                    with self.assertRaises(HTTPException) as error:
                        await self.call_delete(module, result, failure)
                    self.assertEqual(error.exception.status_code, 500)

    def test_delete_routes_require_permission_and_return_204(self):
        for module in (cursos, salas):
            route = next(route for route in module.router.routes if "DELETE" in route.methods)
            self.assertEqual(route.status_code, 204)
            self.assertEqual(len(route.dependant.dependencies), 1)
            dependency = route.dependant.dependencies[0].call
            captured = dict(zip(dependency.__code__.co_freevars,
                                (cell.cell_contents for cell in dependency.__closure__)))
            self.assertEqual(captured["permission_code"],
                             "DELETE_COURSE" if module is cursos else "DELETE_ROOM")


if __name__ == "__main__":
    unittest.main()
