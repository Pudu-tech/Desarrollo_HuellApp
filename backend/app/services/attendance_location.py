"""HuellApp · Dirección complementaria de asistencia.

RESPONSABILIDADES
------------------------------------------------------------
- Resolver coordenadas a una dirección y enriquecer un registro ya confirmado.

ESTADO ACTUAL
------------------------------------------------------------
- La geocodificación es opcional y sus fallos no invalidan la asistencia.

SECURITY
------------------------------------------------------------
Envía coordenadas al proveedor configurado solo desde backend; la clave
del proveedor permanece en el entorno y no se devuelve al cliente.
"""
import httpx
from app.core.config import get_settings


def lookup_address(latitude, longitude):
    """Consulta geocodificación opcional; falta de clave o fallo del proveedor devuelve None."""
    key = get_settings().google_maps_api_key
    if not key or not key.get_secret_value():
        return None
    try:
        response = httpx.get('https://maps.googleapis.com/maps/api/geocode/json', params={
            'latlng': f'{latitude},{longitude}', 'key': key.get_secret_value(), 'language': 'es',
        }, timeout=4)
        response.raise_for_status()
        body = response.json()
        if body.get('status') != 'OK' or not body.get('results'):
            return None
        result = body['results'][0]
        def component(kind):
            return next((item['long_name'] for item in result.get('address_components', []) if kind in item['types']), None)
        return {'direccion_detectada': result['formatted_address'],
                'comuna_detectada': component('administrative_area_level_3') or component('locality'),
                'region_detectada': component('administrative_area_level_1')}
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        return None


def enrich_attendance(db, participant, latitude, longitude):
    """Añade una dirección si puede resolverse; el informe ya confirmado no se revierte."""
    address = lookup_address(latitude, longitude)
    if address:
        try:
            db.table('asistencias_asignacion').update(address).eq('asignacion_participante_id', str(participant)).execute()
        except Exception:
            pass  # La asistencia ya quedó confirmada por la RPC; dirección es complementaria.
