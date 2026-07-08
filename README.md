# Escalabilidad, Alta Disponibilidad y Observabilidad en AWS

Laboratorio de la asignatura **Arquitecturas de Software**. Se construye una arquitectura en AWS Academy Learner Lab que integra tres capacidades:

- **Escalabilidad horizontal** (Amazon EC2 Auto Scaling)
- **Alta disponibilidad** (Application Load Balancer + múltiples zonas de disponibilidad)
- **Observabilidad** (CloudWatch Metrics)

Todo el trabajo se realiza sobre la consola de AWS (no hay código de aplicación propio más allá de un script de arranque). Este documento recoge la teoría, las decisiones tomadas durante la construcción, las respuestas a las actividades de análisis de la guía y el informe final.

## Preparación inicial

- **Región fija:** `us-east-1` (N. Virginia), usada durante todo el laboratorio.
- **VPC:** se usa la VPC default de la cuenta (`172.31.0.0/16`), que trae 6 subredes públicas, una por cada zona de disponibilidad de la región (`us-east-1a` a `us-east-1f`). Son públicas porque comparten una tabla de enrutamiento con ruta hacia un Internet Gateway y asignan IP pública automáticamente.

## Conceptos base

### Escalabilidad vs. alta disponibilidad

- **Escalabilidad** es la capacidad de un sistema de adaptarse al aumento o disminución de carga. Puede ser **vertical** (más CPU/RAM/disco en una sola máquina) u **horizontal** (agregar más instancias). Este laboratorio trabaja escalabilidad horizontal con Auto Scaling.
- **Alta disponibilidad** busca que el sistema siga funcionando aunque falle un componente. Se logra distribuyendo instancias entre zonas de disponibilidad y usando un Load Balancer que solo envía tráfico a instancias saludables.

Son conceptos relacionados pero distintos: se puede escalar sin ser altamente disponible (por ejemplo, muchas instancias en una sola AZ) y se puede ser altamente disponible sin escalar (dos instancias fijas en dos AZ, sin Auto Scaling).

## Parte 1: Escalabilidad horizontal

### Security Groups

Se crean dos Security Groups separados, uno para el Load Balancer y otro para las instancias EC2, en vez de uno compartido:

- El SG del ALB (`alb-scalability-sg`) acepta HTTP desde Internet (`0.0.0.0/0`), porque es el único punto de entrada público de la arquitectura.
- El SG de EC2 (`ec2-scalability-sg`) acepta HTTP **únicamente desde el SG del ALB**, no desde `0.0.0.0/0`. Esto obliga a que todo el tráfico hacia las instancias pase por el Load Balancer: si una instancia EC2 tuviera IP pública expuesta, nadie podría llegarle directo por HTTP sin pasar por el ALB, reduciendo la superficie de ataque.

> **Nota sobre nombres:** la guía sugiere los nombres `sg-alb-scalability` y `sg-ec2-scalability`, pero AWS no permite nombrar un Security Group empezando con el prefijo `sg-` (reservado para los IDs autogenerados, ej. `sg-0123abcd...`). Se usaron en su lugar `alb-scalability-sg` y `ec2-scalability-sg`, manteniendo la misma intención semántica.

### Instancia base y depuración de conectividad

Al crear `web-scalability-base` con el Security Group `ec2-scalability-sg` (que solo acepta HTTP desde el SG del ALB), probar la IP pública directamente desde el navegador **no funciona todavía**, porque el ALB aún no existe: no hay ningún origen autorizado para llegar por HTTP a la instancia. El error fue `ERR_CONNECTION_TIMED_OUT`, no un error de conexión rechazada.

Esto ilustra una propiedad importante de los Security Groups: son *stateful* y de tipo "fail-closed" (denegar por defecto). Cuando no existe una regla que permita el tráfico, AWS descarta el paquete silenciosamente en vez de responder con un rechazo explícito, lo que en el cliente se percibe como un timeout, no como "conexión rechazada". Esa distinción ayuda a diferenciar un problema de Security Group (timeout) de un problema de la aplicación (por ejemplo, "connection refused" si Apache no estuviera corriendo).

**Solución adoptada:** se agregó temporalmente una regla de entrada HTTP con origen "Mi IP" en `ec2-scalability-sg`, solo para validar la instancia base antes de crear la AMI. Esta regla se retira una vez confirmado que Apache y el endpoint `/health` responden correctamente, ya que rompe el principio de que solo el ALB debe tener acceso directo.

**Técnica de diagnóstico sin SSH:** dado que la guía evita deliberadamente el uso de SSH, para descartar que el problema fuera el script de arranque (y no el Security Group) se usó **EC2 → Acciones → Monitorear y solucionar problemas → Obtener registro del sistema**, que expone la salida de consola/`cloud-init` sin necesitar acceso remoto. Ahí se confirmó que `dnf install httpd stress-ng`, `systemctl enable httpd` y los `curl` de metadatos (token, instance-id, availability-zone) se ejecutaron sin errores, lo que descartó un problema de aplicación y devolvió la sospecha al Security Group (donde en efecto la regla temporal se había guardado con el puerto en `0` en vez de `80` en el primer intento).

### Creación de la AMI

Al crear la imagen (`ami-web-scalability-arsw`) desde `web-scalability-base`, la consola actual de AWS ya no usa una casilla **"No reboot"** (como asume la guía), sino una casilla renombrada y con polaridad invertida: **"Reiniciar instancia"**. Marcarla es lo que le indica a EC2 que reinicie la instancia antes de tomar el snapshot de los volúmenes, para asegurar que los datos en disco queden en un estado consistente (sin buffers de escritura pendientes). Se marcó esta casilla para lograr el mismo efecto que buscaba la guía original (dejar "No reboot" desmarcado).

### Launch Template sin User Data: limitación conocida y aceptada

La guía indica explícitamente no agregar User Data en el Launch Template, porque la AMI ya contiene Apache instalado, habilitado, y los archivos estáticos (`index.html`, `health`, `load.html`) generados en el disco.

Esto tiene una consecuencia que vale la pena dejar explícita: `index.html` **no es una plantilla dinámica**, es un archivo estático que el script de User Data generó **una sola vez**, sustituyendo `$INSTANCE_ID` y `$AZ` por los valores de `web-scalability-base` en el momento en que corrió. Como el Launch Template no vuelve a ejecutar ese script, **todas las instancias que lance el Auto Scaling Group mostrarán el mismo Instance ID y la misma Availability Zone** (los de la instancia base), aunque en realidad sean instancias distintas con IDs reales diferentes.

Esto afecta directamente dos partes de la guía que asumen contenido dinámico por instancia:
- Sección 18, que pide observar respuestas "desde diferentes instancias EC2" comparando el Instance ID en la respuesta HTTP.
- Sección 32 (reto final), ítem 5, "Evidencia de respuesta desde varias instancias".

**Decisión tomada:** seguir la guía tal como está (sin User Data en el Launch Template), en vez de agregar el script para que cada instancia regenere su propio `index.html` con su Instance ID real. La razón es que este es un laboratorio de aprendizaje centrado en seguir el flujo de Auto Scaling paso a paso tal como lo define el enunciado, no un ejercicio de rediseño de la arquitectura. Como consecuencia, el Instance ID mostrado en el HTML de todas las instancias será el mismo (el de la instancia base), aunque el balanceo de tráfico entre instancias reales sí esté ocurriendo (verificable por otras vías: el propio Target Group muestra IDs de instancia reales y distintos en su lista de targets, y CloudWatch reporta métricas por instancia real). Esto se explica en el informe final para que no se confunda con un error.

**Evidencia observada (sección 18):** el Auto Scaling Group lanzó dos instancias reales, `i-0132685d075728c82` (us-east-1a) e `i-0e2abd0ca8679538d` (us-east-1b), ambas registradas y `Healthy` en `tg-scalability-ha`. Al abrir el DNS del ALB (`alb-scalability-ha-2100884508.us-east-1.elb.amazonaws.com`) y recargar varias veces, la página **siempre** muestra `Instance ID: i-07ec19d59a8544fae` y `Availability Zone: us-east-1a` — los de `web-scalability-base` — confirmando la limitación explicada arriba: el contenido es estático y no refleja cuál de las dos instancias reales respondió. La prueba de que sí hay balanceo real entre las dos instancias está en el Target Group (sección 17), donde ambos IDs reales aparecen registrados y saludables de forma independiente.

También se ejecutó el bucle de prueba de la guía (`for i in {1..10}; do curl -s http://DNS_DEL_ALB | grep "Instance ID"; done`) desde Git Bash: las 10 peticiones respondieron exitosamente y las 10 mostraron el mismo `i-07ec19d59a8544fae`, consistente con lo ya explicado.

## Actividad 1: análisis de escalabilidad y alta disponibilidad

- **¿Qué componente distribuye el tráfico?** El Application Load Balancer (`alb-scalability-ha`).
- **¿Qué componente decide cuántas instancias deben existir?** El Auto Scaling Group (`asg-web-scalability`), según su capacidad deseada/mínima/máxima y su política de escalamiento.
- **¿Qué componente verifica la salud de las instancias?** El Target Group (`tg-scalability-ha`), mediante el health check configurado en la ruta `/health`.
- **¿Por qué se seleccionan dos zonas de disponibilidad?** Para que, si una zona de disponibilidad completa falla, las instancias de la otra zona sigan disponibles y el servicio no se caiga por completo.
- **¿Qué diferencia existe entre Target Group y Auto Scaling Group?** El Target Group es el mecanismo de enrutamiento y salud: agrupa los destinos hacia donde el ALB envía tráfico y determina si están saludables. El Auto Scaling Group es el mecanismo de ciclo de vida: decide cuántas instancias deben existir y las crea o termina. El ASG registra y retira automáticamente sus instancias en el Target Group, pero son responsabilidades distintas.
- **¿Qué pasaría si una instancia falla?** Ocurren dos pasos secuenciales: primero el ALB deja de enviarle tráfico en cuanto el health check la marca `Unhealthy` (casi inmediato, el tráfico se redirige a las instancias sanas restantes); después, el Auto Scaling Group —que usa ese mismo estado de salud del ELB— reemplaza la instancia por una nueva para recuperar la capacidad deseada (esto tarda más, del orden de minutos).
- **¿Qué pasaría si aumenta la carga?** La política de target tracking scaling detecta que la CPU promedio supera el 50% objetivo y el Auto Scaling Group lanza instancias adicionales (hasta el máximo configurado de 3) para repartir la carga y devolver la métrica cerca del valor objetivo.

