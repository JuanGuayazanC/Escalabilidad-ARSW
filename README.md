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

