# Azure

Skills y herramientas para correr Hermes Agent en infraestructura de Azure —
Container Apps o VM — con persistencia, secretos y sandbox resueltos de forma
específica para esa nube (no genérica multi-cloud).

> **Nota de proceso:** esta categoría arrancó con la hipótesis de que el
> ecosistema sería débil (demos puntuales, herramientas multi-nube
> genéricas). La búsqueda encontró más de lo esperado — incluyendo una skill
> `SKILL.md` real y varias herramientas de Hermes construidas específicamente
> para Azure — así que el balance final es más "curar + crear" que el
> "crear casi todo" que se anticipaba. Se documenta todo tal cual se
> encontró, verificado con la API de GitHub.

## Skills recomendadas

Repos con un `SKILL.md` real, en formato agentskills.io/Hermes.

### [`mertcano/Mergent`](https://github.com/mertcano/Mergent) — `monthly-activity-report`
Skill de Hermes que fusiona exports CSV de **Azure DevOps** y Trello en un
reporte mensual de actividad (`.docx`), de-duplicando work items que
aparecen en ambas fuentes. Frontmatter y estructura (`name`, `description`,
`version`, `platforms`, `metadata.hermes.tags/category`) siguen el spec al
pie de la letra — es el ejemplo más "de libro" que encontramos en toda la
búsqueda, para cualquier categoría.

### [`dautovri/cloud-cost-agent`](https://github.com/dautovri/cloud-cost-agent)
Skill de FinOps "native-first" para **AWS, GCP y Azure** — usa el CLI y el
motor de recomendaciones de cada nube (incluido `az`) para encontrar ahorros
reales, sin dashboard nuevo ni ingesta de datos. No es Azure-específica (es
la herramienta multi-nube genérica que anticipábamos encontrar), pero su
cobertura de Azure es real y funcional, no un stub.

## Skill original — creada por Dominicode

### [`azure-hermes-deploy`](skills/azure-hermes-deploy/SKILL.md)
Despliega Hermes Agent en **Azure Container Apps** o en una **VM de Azure**,
cubriendo las tres piezas que ninguna herramienta de terceros resolvía juntas
para Azure: persistencia de volúmenes (Azure Files / Managed Disk),
variables de entorno como secretos reales vía **Key Vault** (no hardcodeados
ni en `.env` versionado), y la activación correcta del sandbox aislado según
el target elegido (Docker nativo en VM vs. las limitaciones — y la
alternativa de *dynamic sessions* — en Container Apps).

> **Estado: ejemplo ilustrativo, no ejecutado aún contra un Hermes real.**
> El Bicep, el cloud-init y los scripts de `scripts/` están fundamentados en
> sintaxis real de Azure CLI/Bicep, pero no se han corrido de punta a punta
> contra una suscripción productiva. Revisa nombres de recursos, versiones
> de API y disponibilidad actual de features (como *Container Apps dynamic
> sessions*, que todavía se despliega región por región) contra la
> documentación oficial antes de usarlo contra algo que importe.

Incluye `references/` (matriz de decisión ACA vs VM, config de Hermes por
target), `templates/` (Bicep para Container Apps, cloud-init para la VM),
`scripts/` (deploy end-to-end para ambos paths) y `assets/` (diagrama de
arquitectura en Mermaid).

## Herramientas relacionadas (no son skills `SKILL.md`)

Código real de Hermes + Azure que no sigue el formato de skill pero es
directamente relevante si estás resolviendo lo mismo que `azure-hermes-deploy`
— vale la pena conocerlas antes de reinventar la rueda.

### [`unrealandychan/Hermes-Agent-Cloud`](https://github.com/unrealandychan/Hermes-Agent-Cloud)
Módulos de Terraform (compatibles con el Terraform Registry) para desplegar
Hermes Agent en AWS, GCP **y Azure** (VM + VNet + NSG). Es infraestructura
como código, no una skill instalable con `hermes skills install`.

### [`turbo998/hermes-azure-files-plugin`](https://github.com/turbo998/hermes-azure-files-plugin)
Plugin de *toolset* de Hermes ("equivalente Azure" de `hermes-s3files-plugin`
de AWS) para montar Azure Blob Storage / Azure Files vía BlobFuse2 o SDK
directo. Resuelve exactamente el problema de persistencia que
`azure-hermes-deploy` documenta a nivel de plataforma — este plugin lo
resuelve a nivel de Hermes mismo. 30 tests declarados, estado *beta*.

### [`mrobinson2/AzureAgentForge`](https://github.com/mrobinson2/AzureAgentForge)
Plataforma multi-agente self-hosteable que incluye el runtime de Hermes
como uno de sus componentes, desplegada vía Terraform a **Azure Container
Apps**. Se solapa directamente con el path de ACA de nuestra skill — útil
como referencia de una implementación más grande y productizada.

### [`barak3d/hermes-azure-deploy`](https://github.com/barak3d/hermes-azure-deploy)
Deployer interactivo de un comando (`pwsh ./deploy.ps1`) para levantar Hermes
en una VM chica de Azure, usando la suscripción de GitHub Copilot del
usuario como backend de modelo en vez de pagar por token aparte. Sin
licencia declarada — revisar términos con el autor antes de reusar el
código.

## Nivel de madurez

| Repo | Stars | Última actualización | Licencia |
|---|---|---|---|
| Mergent (`monthly-activity-report`) | 0 | 2026-06-11 | Sin licencia declarada |
| cloud-cost-agent | 1 | 2026-06-27 | MIT |
| Hermes-Agent-Cloud | 28 | 2026-07-06 | MIT |
| hermes-azure-files-plugin | 0 | 2026-05-16 | MIT |
| AzureAgentForge | 17 | 2026-07-07 | MIT |
| hermes-azure-deploy (barak3d) | 0 | 2026-06-26 | Sin licencia declarada |

*Verificado con `gh api repos/<owner>/<repo>` el día de esta redacción.
Stars bajas no son señal de mala calidad — la mayoría de este ecosistema es
muy reciente. Trátalas con la misma cautela que cualquier dependencia nueva,
y respeta la ausencia de licencia declarada donde aplique (no la asumas
como MIT/permissive por default).*

## Casos de uso

- Levantar un Hermes personal en Azure sin pagar por una VM siempre
  encendida (Container Apps, scale-to-zero para canales por webhook)
- Correr Hermes con su sandbox Docker nativo cuando una skill necesita
  ejecutar comandos de sistema reales, no solo un subprocess restringido
- Que la memoria/skills instaladas de Hermes sobrevivan un reinicio de VM o
  un redeploy de revisión en Container Apps, en vez de perderse
- Sacar las API keys y tokens de canal del `.env`/imagen de contenedor y
  moverlas a Key Vault con identidad administrada
- Generar un reporte mensual de actividad combinando Azure DevOps + Trello
  sin armar el merge a mano cada mes (`Mergent`)
- Auditar gasto en Azure (junto con AWS/GCP) desde el propio agente sin un
  dashboard adicional (`cloud-cost-agent`)

## Instalación

Para las skills reales (`Mergent`, `cloud-cost-agent`):

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force
```

`--force` porque son skills de la comunidad (trust level `community`), no
oficiales. Para la skill original de este repo:

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/awesome-hermes-for-developers/main/Azure/skills/azure-hermes-deploy/SKILL.md --force
```

(sustituye `<owner>` por el remoto real una vez publicado este repo). Las
"herramientas relacionadas" no se instalan como skill — son Terraform,
plugins de toolset o scripts de deploy; sigue el README de cada repo para su
mecanismo de instalación específico.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (3-4 min):
1. `az deployment group create` con `templates/containerapp.bicep` de
   `azure-hermes-deploy` contra una suscripción real
2. Mostrar el secreto resuelto vía Key Vault (`az containerapp show` sin
   valores en claro) y el volumen de Azure Files montado
3. Reiniciar la revisión y confirmar que la memoria de Hermes sobrevive
4. Contrastar con el path de VM: mismo despliegue pero con
   `terminal.backend: docker` funcionando de verdad

## Ejemplo real

*Pendiente* — ni la skill original ni las relacionadas se han corrido contra
un Hermes real todavía. Se actualiza con output real (comandos, logs,
capturas) una vez grabado el video de arriba — no se rellena con resultados
inventados mientras tanto.
