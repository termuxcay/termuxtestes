def adicionar_notas():
  notas = []
  while True:
    nota = float(input("Digite uma nota (ou -1 para finalizar): "))
    if nota == -1:
      break
    notas.append(nota)
  return notas

# ... (resto do seu código)

def calcular_media(notas):
  return sum(notas) / len(notas)

def determinar_situacao(media):
  return "Aprovado" if media >= 7 else "Reprovado"

def exibir_relatorio(notas, media, situacao):
  print("\nRelatório Final:")
  print("Notas:", notas)
  print("Média:", media)
  print("Situação:", situacao)

# Execução do programa
notas_aluno = adicionar_notas()
media_aluno = calcular_media(notas_aluno)
situacao_aluno = determinar_situacao(media_aluno)
exibir_relatorio(notas_aluno, media_aluno, situacao_aluno)
