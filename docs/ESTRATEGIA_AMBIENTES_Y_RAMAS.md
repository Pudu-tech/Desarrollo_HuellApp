# HuellAPP - Estrategia de Ramas y Ambientes

## 1. Objetivo

Este documento define la estrategia de ramas Git y su relación con los ambientes de Supabase y Vercel utilizados por HuellAPP.

El objetivo principal es mantener un flujo de trabajo simple, ordenado y de costo cero durante el desarrollo académico del proyecto, utilizando únicamente los recursos gratuitos disponibles.

---

## 2. Estrategia general

HuellAPP utilizará tres tipos de ramas:

- `main`
- `dev`
- `feature/*`

Cada una tendrá un propósito específico dentro del ciclo de desarrollo.

---

# 3. GitHub

## `main`

Corresponde a la rama estable del proyecto.

Uso:

- Código listo para producción.
- Versiones previamente validadas.
- Cambios que ya pasaron por desarrollo y pruebas.
- Base para los despliegues productivos.

Relación con ambientes:

```text
main
  ↓
Producción