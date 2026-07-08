# Filtrado de credenciales para subprocesos de servidores MCP

## Lo que dice la documentación

Según la chuleta de seguridad de Hermes (verificada contra
`hermes-agent.nousresearch.com/docs/user-guide/security` a la fecha de redacción):

> Los subprocesos de servidores MCP solo reciben variables de entorno seguras (`PATH`, `HOME`,
> `USER`, `LANG`); las API keys se filtran salvo que se declaren explícitamente en el `env` del
> servidor MCP.

Esto es, en teoría, exactamente el comportamiento que quieres: que un servidor MCP de terceros
(código que no auditaste línea por línea) no pueda leer `OPENAI_API_KEY`, `AWS_SECRET_ACCESS_KEY`,
o cualquier otro secreto de otro proyecto que viva en tu variable de entorno global, solo porque
Hermes lo lanzó como subproceso.

## La tensión que hay que señalar, no esconder

El checklist general de seguridad de la misma chuleta dice, en el mismo documento:

> Guarda secretos en `~/.hermes/.env` con permisos de archivo restringidos — nunca en
> `config.yaml`.

Pero el único mecanismo documentado para pasarle una credencial a un servidor MCP es escribirla en
`config.yaml`, bajo `mcp_servers.<alias>.env`. Las dos reglas, tomadas literalmente, se contradicen
para este caso de uso específico. No hemos encontrado (a la fecha de esta skill) una sintaxis de
interpolación confirmada del tipo `${GITHUB_TOKEN}` que le permita a `config.yaml` referenciar un
valor guardado en `.env` en vez de contenerlo literalmente.

Esta skill no resuelve esa tensión por ti — la deja explícita para que la mitigues con controles
que sí están confirmados:

1. `chmod 600 ~/.hermes/config.yaml` en cuanto el archivo tenga cualquier `mcp_servers.*.env`
   poblado con un valor real.
2. Excluye `config.yaml` de cualquier sync de dotfiles, backup a almacenamiento compartido, o
   repositorio — aunque el resto del archivo (terminal, approvals) no sea sensible, ya lo es una
   vez que un solo servidor MCP tiene un secreto ahí adentro.
3. Si tu versión de Hermes sí soporta interpolación de variables en este bloque, confírmalo tú
   mismo (`hermes doctor`, changelog, o probando con una variable dummy) antes de asumirlo — y si
   lo confirmas, por favor actualiza esta referencia con la sintaxis real.

## Cómo verificar el filtrado tú mismo (no solo confiar en el doc)

La documentación es una afirmación sobre el comportamiento del binario `hermes`; no es algo que
este catálogo haya ejecutado contra una instancia real. Antes de confiar en ella para un setup de
producción, confírmala en la tuya:

1. Exporta una variable "canario" claramente falsa en tu shell antes de arrancar Hermes:
   ```bash
   export CANARY_SHOULD_NOT_LEAK="si-ves-esto-el-filtrado-no-funciona"
   ```
2. Sustituye temporalmente `command`/`args` de cualquier entrada de `mcp_servers` por
   `scripts/dump-mcp-subprocess-env.sh` (vive en esta misma skill).
3. Arranca `hermes`, deja que intente conectar ese "servidor" (va a fallar el handshake MCP porque
   no es un servidor real — eso es esperado, el subproceso ya alcanzó a correr y volcar su entorno
   antes de fallar).
4. Revisa el archivo de volcado que genera el script. Si `CANARY_SHOULD_NOT_LEAK` aparece ahí, el
   filtrado no está funcionando como lo documenta la chuleta — repórtalo antes de confiar secretos
   reales a ese servidor.
5. Restaura tu entrada real de `mcp_servers` y borra la variable canario.

Repite esta prueba una vez por versión mayor de Hermes que instales, no solo la primera vez — el
comportamiento de filtrado es una superficie de seguridad que puede cambiar entre releases sin que
lo notes si no lo vuelves a probar.
