suma=0
def es_primo(n, divisor=2):
    if n <= 1:
        return False
    if divisor * divisor > n:
        return True
    if n % divisor == 0:
        return False
    return es_primo(n, divisor + 1)

def sume(lista):
    global suma
    for i in lista:
        if es_primo(i):
            suma+=i
    return suma
print(sume([1,2,3,4,5,6,7,8,9,11]))