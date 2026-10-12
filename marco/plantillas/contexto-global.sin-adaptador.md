**En este puesto ninguna máquina lee las órdenes ni vigila las lecturas:** su
harness no tiene adaptador, así que no hay reglas de lectura ni guards. Estas
cuatro reglas, que con adaptador vigila en parte una máquina, aquí dependen
también de criterio, y por eso van con el texto de la norma:

- **R-03 · Solo el alias.** En documentos, mensajes y código aparece la
  referencia estable; nunca la IP, el host, la ruta de servidor ni la
  credencial.
- **R-04 · Un dato C3 no cruza al proveedor del modelo.**
- **R-06 · Sobre un servidor que no sea el local, toda acción que escriba,
  mueva, mate o reinicie se propone.** Se ejecuta solo con autorización
  explícita en el mensaje actual.
- **R-07 · Antes de una acción destructiva hay punto de restauración
  verificado**, o el usuario acepta explícitamente su ausencia.

De R-03 sigue en pie el barrido de la puerta de commit en cada proyecto dado
de alta; lo que falta es el guard que pregunta ante un `ssh` a una IPv4
literal.
