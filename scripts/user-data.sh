#!/bin/bash
dnf update -y
dnf install -y httpd stress-ng

systemctl enable httpd
systemctl start httpd

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Laboratorio de Escalabilidad</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: #f4f7fb;
            color: #1f2937;
            padding: 40px;
        }
        .card {
            background: white;
            border-radius: 12px;
            padding: 30px;
            max-width: 760px;
            margin: auto;
            box-shadow: 0 10px 25px rgba(0,0,0,0.08);
        }
        h1 {
            color: #2563eb;
        }
        code {
            background: #f3f4f6;
            padding: 4px 8px;
            border-radius: 6px;
        }
        .badge {
            display: inline-block;
            background: #dbeafe;
            color: #1d4ed8;
            padding: 6px 12px;
            border-radius: 20px;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="card">
        <span class="badge">ARSW - Escalabilidad</span>
        <h1>Aplicación Web Escalable</h1>
        <p>Esta respuesta fue generada por una instancia EC2 dentro de un Auto Scaling Group.</p>
        <p><strong>Instance ID:</strong> <code>$INSTANCE_ID</code></p>
        <p><strong>Availability Zone:</strong> <code>$AZ</code></p>
        <p><strong>Estado:</strong> Servicio disponible</p>
    </div>
</body>
</html>
EOF

echo "OK" > /var/www/html/health

cat <<EOF > /var/www/html/load.html
<!DOCTYPE html>
<html>
<head>
    <title>Simulación de carga</title>
</head>
<body>
    <h1>Endpoint de prueba de carga</h1>
    <p>Use este endpoint para generar solicitudes HTTP.</p>
</body>
</html>
EOF
