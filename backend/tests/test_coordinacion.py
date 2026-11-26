from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.api import coordinacion
from app.core.config import get_settings
from app.core.security import get_current_user
from app.main import app


class PanelMonitoresTests(TestCase):
    def setUp(self):
        self.school_id = uuid4()
        self.coordinator_id = uuid4()
        self.actor = SimpleNamespace(
            id=uuid4(),
            role_code="DIRECTIVA",
            effective_permissions={"VIEW_COORDINATOR_MONITORS", "MANAGE_COORDINATOR_MONITORS"},
        )
        self.enterContext(patch.dict(app.dependency_overrides, {get_current_user: lambda: self.actor}))
        self.client = self.enterContext(TestClient(app))
        self.path = f"/colegios/{self.school_id}/coordinadores/{self.coordinator_id}/monitores/panel"

    def test_panel_consulta_candidatos_solo_con_permiso_de_gestion(self):
        with (
            patch.object(coordinacion, "get_supabase_client", return_value=object()) as db,
            patch.object(coordinacion, "_obtener_colegio") as school,
            patch.object(coordinacion, "_consultar_monitores", return_value=[]),
            patch.object(coordinacion, "_listar_usuarios_activos_por_rol", return_value=[]) as candidates,
        ):
            response = self.client.get(self.path)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json(), {"asignados": [], "candidatos": []})
            school.assert_called_once_with(db.return_value, self.school_id, coordinador_id=self.coordinator_id)
            candidates.assert_called_once_with(db.return_value, "MONITOR")

            candidates.reset_mock()
            self.actor.effective_permissions.remove("MANAGE_COORDINATOR_MONITORS")
            self.assertEqual(self.client.get(self.path).status_code, 200)
            candidates.assert_not_called()

    def test_coordinador_no_puede_consultar_otro_equipo(self):
        self.actor.role_code = "COORDINADOR"
        with patch.object(coordinacion, "get_supabase_client") as db:
            self.assertEqual(self.client.get(self.path).status_code, 403)
        db.assert_not_called()

    def test_error_inesperado_conserva_cors_e_identificador(self):
        origin = get_settings().cors_origins[0]
        with (
            patch.object(coordinacion, "get_supabase_client", return_value=object()),
            patch.object(coordinacion, "_obtener_colegio", side_effect=RuntimeError("fallo simulado")),
            self.assertLogs("app.middleware.request_id", level="ERROR"),
        ):
            response = self.client.get(self.path, headers={"Origin": origin})
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.headers["access-control-allow-origin"], origin)
        self.assertTrue(response.headers["x-request-id"])
        self.assertNotIn("fallo simulado", response.json()["detail"])

    def test_asignacion_devuelve_solo_el_monitor_guardado(self):
        monitor_id = uuid4()
        monitor = coordinacion.MonitorCoordinadorItem(
            relation_id=uuid4(), monitor_id=monitor_id, nombres="Monitor",
            apellido_paterno="Prueba", email="monitor@example.org", activo=True,
        )
        with (
            patch.object(coordinacion, "get_supabase_client", return_value=object()) as db,
            patch.object(coordinacion, "_gestionar_monitor") as write,
            patch.object(coordinacion, "_consultar_monitores", return_value=[monitor]) as read,
        ):
            response = self.client.post(self.path.removesuffix("/panel"), json={"monitor_id": str(monitor_id)})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json(), monitor.model_dump(mode="json"))
        self.assertEqual(write.call_args.kwargs["accion"], "ASSIGN")
        read.assert_called_once_with(db.return_value, self.school_id, self.coordinator_id, monitor_id=monitor_id)
