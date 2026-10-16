# Seguridad

## Cómo informar de un problema

Si encuentras una vulnerabilidad (por ejemplo, un script que pueda ejecutar código no verificado, una descarga sin
comprobación de sha256 o un permiso excesivo), **no abras un issue público**: usa
[«Report a vulnerability»](https://github.com/Kuzan-dev/vitrum/security/advisories/new) (aviso privado de GitHub).
Para fallos normales, abre un issue.

## Alcance

- Los scripts de este repositorio (`install.sh`, `scripts/`, `tools/`) y las descargas fijadas por versión y
  sha256 (`config/visual/pins.env` y scripts de sistema).
- Los componentes de terceros (extensiones, temas, Waywallen, rEFInd…) tienen sus propios canales: informa
  también al proyecto original.

## Versiones con soporte

Solo la última versión publicada. Proyecto en pre-release, mantenido por una persona: sin plazos garantizados.
