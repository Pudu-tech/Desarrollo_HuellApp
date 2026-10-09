"""Benchmark reproducible sin red: tres listados con 150 ms de espera por consulta.

python -m tests.benchmark_read_concurrency no requiere credenciales de usuarios.
Ejecutar como python tests/benchmark_read_concurrency.py desde backend.
Mide concurrencia del servidor; no estima latencia real de Internet.
"""
import asyncio
import sys
import time
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import httpx
from fastapi import FastAPI
from app.api import colegios, users, asignaciones


class SlowQuery:
    def __getattr__(self, name):
        return lambda *args, **kwargs: self

    def execute(self):
        time.sleep(.15)
        return SimpleNamespace(data=[])


async def measure():
    app = FastAPI()
    actor = SimpleNamespace(role_code='SUPERADMIN')
    for module in (colegios, users, asignaciones):
        app.include_router(module.router)
        route = next(route for route in module.router.routes if route.path == module.router.prefix and 'GET' in route.methods)
        app.dependency_overrides[route.dependant.dependencies[0].call] = lambda: actor
    with patch.object(colegios, 'get_supabase_client', return_value=SlowQuery()), \
         patch.object(users, 'get_supabase_client', return_value=SlowQuery()), \
         patch.object(asignaciones, 'get_supabase_client', return_value=SlowQuery()):
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url='http://test') as client:
            for _ in range(3):
                started = time.perf_counter()
                responses = await asyncio.gather(*(client.get(path) for path in ('/colegios', '/users', '/asignaciones')))
                assert all(response.status_code == 200 for response in responses), [r.status_code for r in responses]
                print(f'Tres listados concurrentes: {(time.perf_counter()-started)*1000:.0f} ms')


if __name__ == '__main__':
    asyncio.run(measure())
