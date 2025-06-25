## WINDOWS EXPORTER - GRAFANA

Este exportador de métricas recopila información en tiempo real a cerca de:

* Dirección IP y nombre del equipo.
* Porcentaje de uso de la CPU.
* MB/s enviados y recibidos.
* Espacio total del disco duro en GB.
* Espacio libre del disco duro en GB.
* Porcentaje de uso del disco duro.
* Memoria RAM total en GB.
* Porcentaje de memoria RAM en uso.
* Número de eventos críticos y errores graves, además muestra la descripción con la fecha en la que ocurrió cada evento.
* Información a cerca del usuario que ha iniciado sesión en el equipo y el sistema operativo que utiliza.

**Nota**: para aumentar la eficiencia de monitoreo se ha establecido recabar la información de los eventos en los últimos 5 días, esto puede modificarse en el script.

Está pensado para utilizarlo con [NSSM](https://nssm.cc/download). Este es una herramienta de código abierto para gestionar servicios en Windows.
De esta manera, utilizando NSSM conseguimos que el script se habilite como servicio y, logramos que cada vez que el equipo arranque este servicio se habilite y solo se puede parar con permisos elevados, como puede ser, la cuenta de administrador.

Se debe de monitorizar con Grafana y Prometheus. Para aplicar esto en una empresa se debe crear una carpeta compartida en red donde todos los equipos expondrán su dirección IP y el puerto que tiene abierto.
Ya que cada target está asociada al nombre del equipo, escribiendo {job=nombrequipo} podremos ver todos los datos a cerca de ese equipo. Esto se puede configurar al gusto.

**IMPORTANTE: SE DEBE INTRODUCIR LA RUTA DE LA CARPETA COMPARTIDA SI EXISTE Y EL DOMINIO, AMBOS VIENEN INDICADOS EN EL SCRIPT.**

Para facilitarlo, se mencionas las líneas que se deben de editar a continuación:

* $sharedTargetPath = "\Ruta\a\la\carpeta\compartida"

* $hostname = "$computerName.dominio"

* if (-not $target -or $target.Trim() -eq "" -or $target -eq ":$port" -or $target like "dominio:$port")
