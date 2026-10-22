# Compartir un tema personalizado

El editor de Personalizado permite copiar un código que se deriva de la configuración del borrador: fondo, acento principal, acento secundario y transparencia. No incluye cuentas, servidores ni datos del dispositivo.

El bloque «Código del tema» muestra el código actual, permite copiarlo y pegar o escribir otro. «Cargar código» valida y actualiza el borrador y la vista previa. Solo «Guardar y aplicar» persiste y selecciona el tema; cancelar conserva la configuración previa. Un código inválido muestra un error sin modificar el borrador.

Formato v1: `CWT1-RRGGBB-RRGGBB-RRGGBB-P`, con tres colores RGB opacos y porcentaje de transparencia de 0 a 100, hasta cuatro decimales. El codificador produce mayúsculas y elimina ceros decimales sobrantes. El lector acepta espacios y saltos de línea al pegar, limita la entrada original a 128 caracteres y rechaza versiones desconocidas, colores inválidos y transparencias fuera de rango. La precisión máxima es 0,0001 puntos porcentuales.

Validación: roundtrip y casos inválidos del formato; pruebas del editor para generar/copiar, importar/ver previsualización y conservar borrador ante errores o cancelación; pruebas existentes de persistencia y de colores de la vista previa. Sin nuevas dependencias ni comunicación con un servidor.
