Usar codex dentro de contenedor con $HOME/.codex del contenedor montada en volumes/codex

Si la ruta está montada como volumen/bind (.warp/docker/volumes/appconfig:/ruta/en/contenedor), esos archivos viven fuera del filesystem
   “de la imagen”.
 
   Entonces:
 
   - cambios en esa carpeta no quedan en docker commit,
   - al crear imagen desde contenedor, esa ruta montada no se “empaqueta”.
 
   Solo se comitea lo que está en las capas del contenedor, no lo que viene de mounts.
