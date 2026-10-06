# Guia de apresentação: Compilador C em Jison

> Este arquivo é só para você estudar. Ele fica fora do repositório e não vai para o professor.

---

## 1. O que o professor pede (enunciado)

| Parte | O que pede | Como o trabalho atende |
|---|---|---|
| **1: Léxico** | Expressões regulares para palavras reservadas, identificadores, números inteiros e reais, strings e caracteres, operadores e símbolos | Bloco `%lex ... /lex` do `.jison`: as 32 palavras reservadas, todos os operadores da lista, `#include`, `#define` e comentários `//` e `/* */` |
| **2: Gramática** | Atribuições, alocações (malloc), desalocações (free), if/else, while, do-while, for, comparações, defines, includes. **Imprimir mensagem a cada caso reconhecido** | Regras depois do `%%`. Cada uma imprime `[linha N] Laço FOR...`, `Comparação...`, `Alocação dinâmica...` e assim por diante |
| **3: Semântica** | Tabela de símbolos, **árvores sintáticas**, análise semântica com base na tabela, **código intermediário para atribuições** | Funções JavaScript no topo do arquivo: tabela com pilha de escopos, árvore impressa e TAC para cada atribuição, tudo fechado com um relatório final |

Frase do enunciado que vale lembrar: *"Não será tratado o uso de funções"*. As funções são **reconhecidas** (por exemplo `main` e `printArray` da entrada_04), mas o foco são os comandos e as atribuições.

---

## 2. Roteiro da apresentação (mais ou menos 10 minutos)

Antes de começar, gere o parser:
```bash
jison C_compiler_correto_parte_3.jison
```

1. **Mostre o arquivo `.jison` e as 3 seções**: o código JS no topo (Parte 3), o `%lex` (Parte 1) e a gramática (Parte 2).
2. **entrada_01**: o caso básico. Aponte as mensagens da Parte 2 (if, for, while, comparações), uma árvore sintática, o TAC e a tabela de símbolos no final.
   ```bash
   node C_compiler_correto_parte_3.js entrada_01.txt
   ```
3. **entrada_03**: o arquivo do professor sobre **escopo**. Mostre:
   - as duas `soma4` aparecem na tabela com escopos diferentes (2 e 3), sem erro;
   - o erro da linha 46: `4.5` deixa a expressão real e ela é atribuída a `sum`, que é int;
   - o erro da linha 47: `soma3` foi declarada dentro do `if`, e aquele escopo já fechou.
4. **entrada_04**: o exemplo completo do PDF. Mostre struct, union, enum, typedef, malloc/free e matriz na tabela de símbolos.
5. **entrada_07_semantica**: um erro semântico de cada tipo (12 no total).
6. **Teste ao vivo**: se o professor pedir, apague uma declaração ou troque um `int` por `float` e rode de novo.

---

## 3. Onde fica cada coisa no código

| Conceito | Função ou regra no `.jison` |
|---|---|
| Pilha de escopos | `abrirEscopo`, `fecharEscopo`, regras `bloco` / `abre_bloco` / `abre_for` |
| Inserção na tabela | `declarar` (acusa redeclaração no mesmo escopo) |
| Busca na tabela | `buscar` (percorre a pilha do topo para a base) |
| Tipo de uma expressão | `noBin`, `noUn`, `noIndice`, `noMembro`, `noChamada` |
| Compatibilidade na atribuição | `compativel` e `verificarAtribuicao` |
| L-value e const | `checarEscrita` |
| Desenho da árvore | `desenharArvore` |
| Geração de TAC | `gerar` (percurso em pós-ordem) e `instrucaoExpr` |
| Declarações | `declararItem` |
| Precedência | linhas `%left` / `%right` antes da gramática |
| If/else ambíguo | `%nonassoc IFX` / `%nonassoc ELSE` e `%prec IFX` |
| Recuperação do `;` ausente | `parser.parse = function ...` no fim do bloco JS |

---

## 4. Perguntas prováveis e respostas

### Léxico

**Como você impede que `int` seja reconhecido como identificador?**
No Jison vence a **primeira regra** que casa. As palavras reservadas vêm antes da regra de identificador. Além disso, o Jison acrescenta `\b` (fronteira de palavra) aos padrões literais. Por isso `integer` não casa com `int` e é lido como identificador.

**Por que `<<=` aparece antes de `<<`, e `<<` antes de `<`?**
Pelo mesmo motivo: a primeira regra vence. Se `<` viesse antes, `<<=` seria quebrado em três tokens.

**Como os comentários são tratados?**
Por expressões regulares sem `return`. O texto é consumido e descartado. O comentário de bloco usa `"/*"([^*]|\*+[^*/])*\*+"/"`, que cobre várias linhas.

**Como funciona o `#define`?**
A linha inteira vira um token `DEFINE`. A ação `definirDefine` separa o nome do valor e insere na tabela com classe `define`, o tipo deduzido do valor e a marca de constante. Por isso `MAX = 20` dá erro.

**O que acontece com um caractere inválido, como `@`?**
A última regra (`.`) registra um erro léxico com o número da linha e a análise continua.

### Sintático

**Que tipo de parser o Jison gera?**
Um parser **LALR(1)**, ascendente (bottom-up), de deslocamento e redução (shift/reduce), igual ao Yacc/Bison.

**A gramática tem conflitos?**
Não, zero. A gramática de expressões é ambígua (`expr '+' expr`), mas as declarações `%left` e `%right` resolvem os conflitos por precedência e associatividade. A versão antiga tinha 32 conflitos.

**Como resolveu o "dangling else"?**
`if (a) if (b) x; else y;` é ambíguo. Com `%nonassoc IFX` declarado **antes** de `%nonassoc ELSE`, o ELSE tem precedência maior, o parser prefere fazer shift e o `else` fica com o `if` mais próximo, como manda o C.

**Por que `a + b * c` calcula a multiplicação primeiro?**
`'*'` foi declarado em um `%left` **abaixo** de `'+'`. No Jison, quanto mais abaixo na lista, maior a precedência.

**Por que a mensagem do IF aparece depois das mensagens dos comandos de dentro dele?**
Porque o parser é ascendente: a regra do `if` só é **reduzida** depois que todo o corpo foi reconhecido. As ações executam no momento da redução.

**O que são `$$`, `$1` e `@1`?**
`$1`, `$2`... são os valores dos símbolos do lado direito da regra. `$$` é o valor do lado esquerdo, ou seja, o resultado. `@1.first_line` é a linha do primeiro símbolo, usada nas mensagens.

**Como `ULong` vira um tipo depois do `typedef`?**
Quando o `typedef` é reduzido, o nome vai para o objeto `typedefs`. Na regra de identificador, o léxico consulta esse objeto e devolve `TYPE_NAME` em vez de `IDF`. Essa técnica se chama *lexer hack* e é a mesma usada em compiladores C de verdade.

**O que acontece se faltar `;`?**
O parser lança o erro. O `parser.parse` personalizado verifica se o token inesperado é o primeiro da linha e se o `;` estava entre os esperados. Se for o caso, insere o `;`, registra um aviso e reanalisa. Foi o que aconteceu na entrada_03 original do professor (linhas 46 a 48). Para qualquer outro erro, mostra a linha e os tokens esperados.

### Semântico e tabela de símbolos

**Quais informações a tabela guarda?**
Para cada símbolo: `id`, `classe` (variavel, define, constante, funcao, typedef, struct, union), `tipo`, `modificadores` (const, register...), `escopo`, `linha` e `valor` inicial.

**Como funciona o escopo?**
Uma **pilha**. Cada `{` empilha um número novo de escopo e cada `}` desempilha. Toda declaração vai para o escopo do topo. A busca percorre a pilha do topo até o escopo 0 (global): acha primeiro a variável mais interna e não enxerga escopos que já foram fechados. O `for` tem escopo próprio, por isso dois `for (int i...)` não acusam redeclaração.

**Por que `soma3` dá erro na entrada_03?**
Ela foi declarada no bloco do `if` (escopo 6). Quando o `}` do `if` fecha, o escopo 6 sai da pilha. Na linha 47 o escopo ativo é o do `for` (5), e a busca não encontra `soma3`.

**E por que as duas `soma4` não dão erro?**
Cada uma está em um bloco irmão diferente (escopos 2 e 3). Redeclaração só é erro **no mesmo escopo**.

**Por que a linha com `4.5` dá erro e `average = (float)sum / SIZE` não?**
A expressão `... / 4.5` tem tipo real (double), e atribuir um real a `sum` (int) **perde precisão**. Já `average` é float, e real em real é permitido. A regra é: inteiro para real pode (alarga), real para inteiro não pode.

**Como o tipo de uma expressão é calculado?**
De baixo para cima, junto com a árvore. Cada nó guarda seu `tipo`. Em `noBin`, se um operando é real, o resultado é real; comparações e `&&`/`||` resultam em int; `%` exige dois inteiros.

**Como `malloc` e `free` são tratados?**
São funções embutidas (junto com printf e scanf). `malloc` retorna `void*`, que é compatível com qualquer ponteiro. O cast `(int *)` deixa o tipo `int*` explícito.

### Árvore e código intermediário

**Qual a diferença entre árvore sintática e árvore de derivação?**
A árvore de derivação mostra todas as regras da gramática. A **árvore sintática abstrata** (AST), que é o que geramos, guarda só operadores e operandos, sem parênteses e sem `;`. A estrutura da árvore já contém a precedência.

**O que é código de três endereços?**
Uma representação intermediária em que cada instrução tem **no máximo um operador** e três "endereços" (dois operandos e um resultado). Expressões grandes são quebradas em temporários (`t0`, `t1`, ...).

**Como o TAC é gerado?**
A função `gerar` percorre a árvore em **pós-ordem**: primeiro os filhos, depois o nó. Cada operador cria um temporário novo. Exemplo de `odd_count = soma4 * 10 + 34`:
```
t0 = soma4 * 10
t1 = t0 + 34
odd_count = t1
```

**Por que não tem TAC para `if` e `while` (desvios e rótulos)?**
O enunciado pede código intermediário **para expressões de atribuição**. Mesmo assim, o ternário `?:` já gera `ifFalse ... goto L0`, então dá para mostrar que a ideia de rótulos está implementada.

**Como `a[i] = x` e `i++` viram TAC?**
`a[i] = x` vira `a[i] = x` (atribuição indexada). `i++` vira `t0 = i`, `t1 = t0 + 1`, `i = t1`.

### Limitações (é melhor você citar antes que perguntem)

- Funções são reconhecidas, mas o tipo do `return` e os tipos dos argumentos não são verificados, só a quantidade de argumentos.
- Não há TAC para estruturas de controle, só para atribuições, como o enunciado pede.
- `break` fora de laço não é acusado.
- A inicialização de struct (`{1, "John"}`) não tem os tipos de cada campo conferidos.

---

## 5. Cuidado na apresentação

O professor pode pedir para você **alterar algo ao vivo**. Treine com estes três exemplos:
- adicionar uma palavra ou operador novo no léxico (uma linha no `%lex`);
- adicionar uma mensagem em alguma regra (`log(@1.first_line, '...')`);
- criar uma verificação nova, por exemplo divisão por zero literal dentro de `noBin`: `if (op === '/' && b.k === 'num' && b.valor === '0') erro(linha, 'divisão por zero');`.
