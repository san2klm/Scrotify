# Publicar CrotoWave

Este repositorio es el de desarrollo (cerrado). El público es
<https://github.com/Dante0Q/CrotoWave> y **no recibe nunca el historial de
este**: en commits viejos hay credenciales. La primera publicación sale de una
copia del árbol actual, con un solo commit.

## Reglas

- No agregar `github.com/Dante0Q/CrotoWave` como remoto de este repositorio: un
  `git push` equivocado subiría todo el historial.
- Las credenciales que aparecen en el historial viejo (la cuenta `Proyecto`,
  commits anteriores a `debbf37`) hay que cambiarlas igual: el repo de
  desarrollo también las tiene.
- No se publica hasta que la versión esté terminada.

## Primera publicación (historial limpio)

```sh
# 1. Copia del último commit, sin .git ni archivos ignorados.
dest=../CrotoWave-public
mkdir "$dest"
git archive --format=tar HEAD | tar -x -C "$dest"
cd "$dest"

# 2. Quitar lo que es solo del desarrollo.
rm -rf tasks AGENTS.md

# 3. Buscar secretos y datos privados antes de crear el repo.
gitleaks dir .                       # o: docker run --rm -v "$PWD:/r" zricethezav/gitleaks dir /r
grep -rIn -E 'password|passwd|secret|token' --exclude-dir=test . | less
grep -rIn -E '192\.168\.|templo\.cloud' . | less   # revisar que solo queden ejemplos y el relay público

# 4. Repo nuevo con un solo commit.
git init -b main
git config core.hooksPath .githooks
git add -A
git commit -s -m "CrotoWave 1.0.0"
git tag v1.0.0

# 5. Recién cuando todo esté revisado:
git remote add origin https://github.com/Dante0Q/CrotoWave.git
git push -u origin main --tags
```

Después, en GitHub: activar *secret scanning* y *push protection*, MFA en la
cuenta, y protección de la rama `main`.

## Versiones siguientes

Cada versión se copia igual (pasos 1 a 3) sobre el clon del repo público, y se
hace un commit por versión. Así el historial público nunca contiene el de
desarrollo.

## Binarios del release

1. Compilar: `scripts/build_apks.sh`, `scripts/build_appimage_portable.sh`, el
   instalador de Windows en CI.
2. Copiar a `dist/` y firmar: `scripts/sign_release.sh dist` (pide la contraseña
   de minisign en una ventana).
3. Subir al release de GitHub los binarios, `SHA256SUMS`, `SHA256SUMS.minisig`
   y `crotowave-release.pub`.

## Windows: pedir la firma gratis a SignPath Foundation

Cuando el repo público tenga la primera versión publicada:

1. Completar el formulario de <https://signpath.org/apply> con el repo, la
   licencia (GPL-3.0-or-later con permisos adicionales de la sección 7) y la
   política `docs/CODE_SIGNING_POLICY.md`.
2. Enlazar la política de firma y `PRIVACY.md` desde el `README.md` público
   (ya está en la sección «Licencia»).
3. Si aprueban: agregar al workflow `windows.yml` el paso de SignPath
   (`signpath/github-action-submit-signing-request`) con los secretos que dan,
   firmando el `.exe` y el instalador. Cada firma se aprueba a mano en SignPath.
