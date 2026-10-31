def maximo_lista(lista):
    if not lista: # esta parte la pueden obviar
        raise ValueError("La lista no puede estar vacía")
    
    maximo = lista[0]
    for num in lista:
        if num > maximo:
            maximo = num
    return maximo

#print (maximo_lista([3,4,5,24,5,65,46]))