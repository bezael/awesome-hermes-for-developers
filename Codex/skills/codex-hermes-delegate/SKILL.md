---
name: codex-hermes-delegate
description: "Delega desde Hermes una tarea de código puntual y acotada a Codex CLI (codex exec) sin cambiar el runtime completo de Hermes, y trae el resultado de vuelta para verificarlo e integrarlo a la memoria de Hermes."
version: 0.1.0
author: Dominicode
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Codex, Delegation, Subagent, Memory, CLI]
    category: Codex
    related_skills: [hermes-agent-acp-skill, hermes-theia-codex-vision]
---

# Codex Hermes Delegate

> **Estado: skill original de Dominicode, ilustrativa.** Este SKILL.md fue redactado siguiendo el formato real de agentskills.io y los flags documentados de Codex CLI, pero **no se ha ejecutado todavía contra una instancia real de Hermes Agent**. Antes de instalarla en un servidor de producción, valida cada paso de la sección "Verification" tú mismo.

## Overview

A diferencia de registrar Codex como runtime completo de Hermes (el patrón "engine swap" donde Codex reemplaza `patch`/`terminal`/`write_file` para toda la sesión), esta skill cubre un caso más acotado: Hermes sigue siendo el orquestador, pero para **una tarea de generación de código puntual** — implementar una función, corregir un bug localizado, generar un snippet — delega el trabajo a un proceso `codex exec` no interactivo, espera (o sondea) el resultado, lo verifica, y solo entonces lo integra a su propio contexto/memoria. Hermes puede seguir trabajando en otra cosa mientras Codex resuelve la tarea delegada.

Esto es complementario a `hermes-agent-acp-skill` (delegación estilo ACP hacia Codex y Claude Code) y a `hermes-theia-codex-vision` (Codex para visión/generación de imágenes) — esta skill se enfoca específicamente en **generación de código de un solo turno**, con foco en el ciclo delegar → verificar → memorizar.

## When to Use

Usa esta skill cuando:

- Tienes una tarea de código **acotada y bien definida** (un archivo o un directorio pequeño, un contrato claro de entrada/salida) que quieres resolver sin bloquear el hilo principal de Hermes.
- Quieres una segunda implementación (de un modelo distinto) para comparar o para verificación cruzada antes de aceptar un cambio.
- La tarea encaja en el modo no interactivo de Codex (`codex exec`) — no requiere ida y vuelta conversacional.
- Quieres que el resultado quede **registrado en la memoria de Hermes** (qué se delegó, qué devolvió Codex, qué se verificó), no solo aplicado silenciosamente.

**No la uses para:**

- Sesiones completas de desarrollo donde quieres que Codex maneje todas las herramientas de Hermes (`patch`, `terminal`, `write_file`) — eso es el patrón de runtime swap, no delegación puntual (ver `braddown/hermes-codex-troubleshooting` para ese otro flujo).
- Tareas que requieren clarificación interactiva continua — `codex exec` es de un solo disparo.
- Refactors grandes multi-archivo sin un plan explícito de qué directorios puede tocar Codex.

## Prerequisites

| Requisito | Detalle |
|---|---|
| **Codex CLI instalado** | `npm install -g @openai/codex` |
| **Codex autenticado** | Vía ChatGPT Plus OAuth (`codex auth login`, revisa `~/.codex/auth.json` → `"auth_mode": "chatgpt"`) o `OPENAI_API_KEY` según cómo lo tengas configurado — confirma cuál usa tu instalación antes de automatizar nada |
| **Hermes con acceso a terminal** | La skill asume que Hermes puede invocar procesos (`terminal` tool o equivalente) |
| **Alcance definido** | Un directorio o archivo concreto que Codex pueda tocar — nunca delegues sin acotar el `--add-dir` |

## Procedure

1. **Definir el alcance de la tarea.** Antes de delegar, Hermes debe tener: (a) una instrucción acotada en lenguaje natural, (b) el directorio/archivo exacto que Codex puede modificar, (c) el criterio de "listo" (qué debe cumplir el resultado).

2. **Delegar con `codex exec` en modo no interactivo:**

   ```bash
   codex exec \
     --skip-git-repo-check \
     -s workspace-write \
     --add-dir <ruta-acotada> \
     "Implementa <tarea concreta> en <archivo>. No modifiques otros archivos. Criterio de listo: <criterio>." \
     --output-last-message /tmp/codex-result.txt
   ```

   > Verifica los nombres exactos de flags contra `codex exec --help` de tu versión instalada — han cambiado entre releases de Codex CLI y no hay que asumir que los de este ejemplo son estables a futuro.

3. **Capturar el resultado.** Lee el diff/patch generado o el archivo de `--output-last-message`. No lo apliques ni lo des por bueno automáticamente.

4. **Verificar antes de integrar.** Corre lint/tests sobre los archivos afectados (o el equivalente del proyecto) antes de que Hermes considere la tarea delegada como completa.

5. **Registrar en la memoria de Hermes.** Guarda una entrada breve: qué se delegó, el comando exacto usado, qué devolvió Codex, y qué verificación se corrió — para que sesiones futuras de Hermes tengan contexto sin tener que re-descubrir que esta tarea ya se intentó.

6. **Continuar.** Si `codex exec` se lanzó en background, Hermes sigue con su cola de tareas y vuelve a este resultado cuando esté disponible; si fue síncrono, continúa inmediatamente después de verificar.

## Pitfalls

- **Confusión de modo de auth.** Codex usa OAuth de ChatGPT Plus por defecto, no `OPENAI_API_KEY` — mismo gotcha documentado en `hermes-theia-codex-vision`. Confírmalo antes de asumir que un fallo es de red y no de auth.
- **Sandbox sin `--add-dir` explícito.** Sin acotar el directorio, Codex puede rechazar escrituras o (peor) tocar archivos fuera del alcance esperado. Sé explícito siempre.
- **`--skip-git-repo-check` fuera de un repo git.** Sin este flag, `codex exec` falla si el directorio de trabajo no es un repositorio git.
- **Los flags cambian entre versiones de Codex CLI.** No script-ees esto a ciegas en producción sin correr `codex exec --help` primero contra la versión instalada.
- **No confundir esta skill con el "engine swap" completo.** Delegar una tarea puntual (esta skill) y reemplazar el runtime completo de Hermes por Codex son dos patrones distintos — mezclarlos genera estado confuso sobre quién controla qué herramienta.
- **No perscindir de la verificación.** El resultado de Codex no es "hecho" hasta que Hermes corre lint/tests — de lo contrario la entrada de memoria queda registrando algo que nunca se validó.

## Verification

Esta skill es un diseño original de Dominicode para este catálogo — **no ha sido ejecutada todavía contra una instancia real de Hermes Agent ni contra Codex CLI**. Antes de confiar en ella:

1. Instala Codex CLI y autentica (`codex auth login`).
2. Corre el comando exacto de la sección "Procedure" contra un repo de prueba (no producción).
3. Confirma que el diff/patch resultante aplica limpio y que el archivo de `--output-last-message` es legible por Hermes.
4. Confirma que Hermes puede escribir la entrada de memoria descrita en el paso 5 sin intervención manual.

Actualiza esta sección (y el README de la categoría Codex) con el resultado real una vez se grabe la demostración — siguiendo el mismo criterio de honestidad que el resto del catálogo: sin resultados de ejecución inventados.
