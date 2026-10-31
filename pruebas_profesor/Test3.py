from Test2 import maximo_lista
suma=0
multiplicacion=1
def sumeMayores(lista):
    global suma, multiplicacion
    while suma <100:
        valorMaximo=maximo_lista(lista)
        if valorMaximo/2==5:
            valorMaximo*=2
        suma+=valorMaximo
        multiplicacion*=valorMaximo
        if multiplicacion>500:
            multiplicacion=10
        else: 
            multiplicacion=multiplicacion-10
    return (suma,multiplicacion)
print(sumeMayores([10,2,3,4]))
