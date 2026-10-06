# Compilador C em Jison

Trabalho de Compiladores: analisador léxico, sintático e semântico para um subconjunto da linguagem C, com tabela de símbolos, árvores sintáticas e código de três endereços (TAC) para atribuições.

Tudo está em um único arquivo: [`C_compiler_correto_parte_3.jison`](C_compiler_correto_parte_3.jison).

## Como executar

```bash
npm install -g jison
jison C_compiler_correto_parte_3.jison
node C_compiler_correto_parte_3.js entrada_03.txt
```

## Organização do arquivo

| Parte do trabalho | Onde está |
|---|---|
| **Parte 1: léxico** | Bloco `%lex ... /lex`: palavras reservadas, identificadores, literais (int, float, char, string), operadores, comentários, `#include`, `#define` |
| **Parte 2: gramática** | Regras após `%%`: declarações, struct/union/enum/typedef, arrays e matrizes, ponteiros, malloc/free, if/else, while, do-while, for, switch/case, comparações. Cada construção imprime `[linha N] ...` |
| **Parte 3: semântica** | Código JavaScript no topo (`%{ ... %}`): tabela de símbolos com pilha de escopos, verificação de tipos, árvore sintática e geração de TAC |

## Saída do compilador

1. Mensagens de depuração para cada construção reconhecida, na ordem da análise.
2. Para cada atribuição: a árvore sintática e as instruções TAC geradas.
3. Relatório final com a tabela de símbolos, o código de três endereços e a lista de erros.

Exemplo (`entrada_01.txt`, linha 12):

```
[linha 12] Atribuição: sum += array[i]
    Árvore sintática:
    +=  <int>
    ├── sum  <int>
    └── [ ]  <int>
        ├── array  <int[5]>
        └── i  <int>
    TAC: t0 = array[i]
    TAC: t1 = sum + t0
    TAC: sum = t1
```

## Verificações semânticas

- Variável não declarada ou usada fora do seu escopo
- Redeclaração no mesmo escopo
- Atribuição de valor real a variável inteira (perda de precisão)
- Tipos incompatíveis (por exemplo, `int` atribuído a ponteiro)
- Atribuição a `const`, a constante de `#define`/`enum` ou a um array inteiro
- Índice de array que não é inteiro
- Operadores `% & | ^ << >>` com operando real
- Membro inexistente em struct/union, ou `.` usado em vez de `->`
- Função não declarada, ou chamada com número errado de argumentos
- Erros léxicos (caractere inválido) e sintáticos, com o número da linha

Se faltar `;` no fim de um comando, o compilador insere o `;`, emite um aviso e continua a análise.

## Entradas de teste

| Arquivo | Conteúdo | Erros esperados |
|---|---|---|
| `entrada_01.txt` | laços, if/else, arrays | 0 |
| `entrada_02.txt` | ponteiro, malloc/free, printf/scanf | 0 |
| `entrada_03.txt` | escopos, define, switch, cast | 2 (`4.5` em int, `soma3` fora do escopo) |
| `entrada_04.txt` | exemplo completo do enunciado (struct, union, enum, typedef...) | 0 |
| `entrada_05.txt` | comandos fora de função | 0 |
| `entrada_06.txt` | atribuições inválidas | 2 |
| `entrada_07_semantica.txt` | um caso para cada verificação semântica | 12 |
