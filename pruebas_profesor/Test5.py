def multiplicar_matrices(a, b):
    filasA = len(a)
    columnasA = len(a[0])
    columnasB = len(b[0])
    resultado = []
    for i in range(filasA):
        fila = []
        for j in range(columnasB):
            suma = 0
            for k in range(columnasA):
                suma += a[i][k] * b[k][j]
            fila.append(suma)
        resultado.append(fila)
    return resultado

print(multiplicar_matrices([[1,2],[3,4]], [[5,6],[7,8]]))
