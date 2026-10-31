def transponer_matriz(matriz):
    filas = len(matriz)
    columnas = len(matriz[0])
    transpuesta = []
    for j in range(columnas):
        nueva_fila = []
        for i in range(filas):
            nueva_fila.append(matriz[i][j])
        transpuesta.append(nueva_fila)
    return transpuesta

print(transponer_matriz([[1,2,3],[4,5,6]]))
