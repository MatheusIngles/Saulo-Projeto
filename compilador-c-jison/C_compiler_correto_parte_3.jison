/*
 * Compilador C (subconjunto) em Jison
 *  Parte 1 - analisador léxico (tokens da linguagem C)
 *  Parte 2 - gramática com mensagens de depuração para cada construção
 *  Parte 3 - tabela de símbolos com escopos, análise semântica,
 *            árvores sintáticas e código de três endereços (TAC) para atribuições
 *
 * Uso:  jison C_compiler_correto_parte_3.jison
 *       node C_compiler_correto_parte_3.js entrada_03.txt
 */

%{
    var escopos, proxEscopo, tabelaSimbolos, tac, erros, avisos, saida;
    var nTemp, nRotulo, typedefs, structs, ctxDecl, valorEnum;

    function reiniciar() {
        escopos = [0]; proxEscopo = 1;
        tabelaSimbolos = []; tac = []; erros = []; avisos = []; saida = [];
        nTemp = 0; nRotulo = 0; typedefs = {}; structs = {}; ctxDecl = []; valorEnum = 0;
    }
    reiniciar();

    var EMBUTIDAS = { printf: 'int', scanf: 'int', malloc: 'void*', calloc: 'void*', realloc: 'void*', free: 'void' };

    /* ---------- saída ---------- */
    function out(s) { saida.push(s === undefined ? '' : String(s)); }
    function log(linha, msg) { out('[linha ' + linha + '] ' + msg); }
    function erro(linha, msg) { erros.push('Linha ' + linha + ': ' + msg); out('[linha ' + linha + '] ERRO SEMÂNTICO: ' + msg); }

    /* ---------- escopos e tabela de símbolos ---------- */
    function escopoAtual() { return escopos[escopos.length - 1]; }
    function abrirEscopo(linha) { escopos.push(proxEscopo++); log(linha, 'Abrindo escopo ' + escopoAtual()); }
    function fecharEscopo(linha) { log(linha, 'Fechando escopo ' + escopos.pop()); }

    function buscar(nome) {
        for (var i = escopos.length - 1; i >= 0; i--)
            for (var j = 0; j < tabelaSimbolos.length; j++)
                if (tabelaSimbolos[j].id === nome && tabelaSimbolos[j].escopo === escopos[i]) return tabelaSimbolos[j];
        return null;
    }

    function declarar(nome, tipo, classe, linha, extra) {
        extra = extra || {};
        var esc = escopoAtual();
        var existente = tabelaSimbolos.filter(function (s) { return s.id === nome && s.escopo === esc; })[0];
        if (existente) {
            if (classe === 'funcao' && existente.classe === 'funcao') return existente; // protótipo + definição
            erro(linha, "'" + nome + "' já foi declarado neste escopo (linha " + existente.linha + ")");
            return null;
        }
        var s = { id: nome, tipo: tipo, classe: classe, escopo: esc, linha: linha,
                  modificadores: (extra.mods || []).join(' '), valor: extra.valor, constante: !!extra.constante };
        if (extra.params) s.params = extra.params;
        tabelaSimbolos.push(s);
        log(linha, 'Símbolo inserido: ' + nome + ' [' + classe + '] tipo ' + tipo + ' no escopo ' + esc);
        return s;
    }

    /* ---------- tipos ---------- */
    function montarTipo(specs) {
        var info = { tipo: '', typedef: false, constante: false, mods: [] }, base = [];
        specs.forEach(function (s) {
            if (s === 'typedef') info.typedef = true;
            else if (/^(const|volatile|static|extern|register|auto)$/.test(s)) {
                info.mods.push(s);
                if (s === 'const') info.constante = true;
            } else base.push(s);
        });
        if (base.every(function (b) { return /^(signed|unsigned|short|long)$/.test(b); })) base.push('int');
        info.tipo = base.join(' ');
        return info;
    }

    function categoria(t) {
        if (!t || t === '?') return '?';
        if (t.indexOf('[') >= 0) return 'array';
        if (/\*$/.test(t)) return 'ponteiro';
        if (/float|double/.test(t)) return 'real';
        if (/^(struct|union) /.test(t)) return 'agregado';
        if (t === 'void') return 'void';
        return 'inteiro'; // int, char, short, long, signed, unsigned, enum
    }
    function tipoElemento(t) {
        if (/\[[^\]]*\]$/.test(t)) return t.replace(/\[[^\]]*\]$/, '');
        if (/\*$/.test(t)) return t.slice(0, -1);
        return null;
    }
    function comoPonteiro(t) { return categoria(t) === 'array' ? tipoElemento(t) + '*' : t; }
    function tipoBase(t) { return t.replace(/\[.*$/, ''); }

    function compativel(destino, v) {
        var cd = categoria(destino), cs = categoria(v.tipo);
        if (cd === '?' || cs === '?') return true;
        if (cd === 'ponteiro') {
            if (v.k === 'num' && v.valor === '0') return true;
            if (cs !== 'ponteiro' && cs !== 'array') return false;
            var src = comoPonteiro(v.tipo);
            return src === 'void*' || destino === 'void*' || src === destino;
        }
        if (cd === 'inteiro') return cs === 'inteiro';
        if (cd === 'real') return cs === 'inteiro' || cs === 'real';
        if (cd === 'agregado') return destino === v.tipo;
        return false;
    }

    function verificarAtribuicao(destino, v, linha, nome) {
        if (compativel(destino, v)) return;
        if (categoria(destino) === 'inteiro' && categoria(v.tipo) === 'real')
            erro(linha, "atribuição de expressão real (" + v.tipo + ") à variável inteira '" + nome + "' (" + destino + ") - perda de precisão");
        else
            erro(linha, "tipos incompatíveis: '" + nome + "' é " + destino + " mas a expressão é " + v.tipo);
    }

    /* ---------- nós da árvore sintática (com verificação semântica) ---------- */
    function noNum(valor, tipo, linha) { return { k: 'num', valor: valor, tipo: tipo, linha: linha }; }

    function noId(nome, linha) {
        var s = buscar(nome), tipo = '?';
        if (!s) erro(linha, "variável '" + nome + "' não declarada ou fora do escopo");
        else if (/^(funcao|typedef|struct|union)$/.test(s.classe)) erro(linha, "'" + nome + "' não é uma variável");
        else tipo = s.tipo;
        return { k: 'id', nome: nome, tipo: tipo, simbolo: s, linha: linha };
    }

    function noBin(op, a, b, linha) {
        var ca = categoria(a.tipo), cb = categoria(b.tipo), t;
        if (ca === '?' || cb === '?') t = '?';
        else if (/^(==|!=|<|>|<=|>=)$/.test(op)) { t = 'int'; log(linha, 'Comparação: ' + texto(a) + ' ' + op + ' ' + texto(b)); }
        else if (op === '&&' || op === '||') t = 'int';
        else if (/^(%|&|\||\^|<<|>>)$/.test(op)) {
            if (ca !== 'inteiro' || cb !== 'inteiro') { erro(linha, "operador '" + op + "' exige operandos inteiros (" + a.tipo + ", " + b.tipo + ")"); t = '?'; }
            else t = 'int';
        }
        else if ((op === '+' || op === '-') && (ca === 'ponteiro' || ca === 'array') && cb === 'inteiro') t = comoPonteiro(a.tipo);
        else if (op === '+' && (cb === 'ponteiro' || cb === 'array') && ca === 'inteiro') t = comoPonteiro(b.tipo);
        else if ((ca !== 'inteiro' && ca !== 'real') || (cb !== 'inteiro' && cb !== 'real')) {
            erro(linha, "operador '" + op + "' inválido entre " + a.tipo + " e " + b.tipo); t = '?';
        }
        else if (ca === 'real' || cb === 'real') t = (a.tipo === 'double' || b.tipo === 'double') ? 'double' : 'float';
        else t = 'int';
        return { k: 'bin', op: op, l: a, r: b, tipo: t, linha: linha };
    }

    function ehLvalue(n) { return n.k === 'id' || n.k === 'indice' || n.k === 'membro' || (n.k === 'un' && n.op === '*'); }

    function checarEscrita(alvo, linha) {
        if (!ehLvalue(alvo)) { erro(linha, "'" + texto(alvo) + "' não pode receber atribuição (não é l-value)"); return false; }
        if (alvo.k === 'id' && alvo.simbolo) {
            if (alvo.simbolo.classe !== 'variavel') { erro(linha, "'" + alvo.nome + "' é " + alvo.simbolo.classe + " e não pode ser alterado"); return false; }
            if (alvo.simbolo.constante) { erro(linha, "'" + alvo.nome + "' é const e não pode ser alterado"); return false; }
        }
        if (categoria(alvo.tipo) === 'array') { erro(linha, "array '" + texto(alvo) + "' não pode ser atribuído diretamente"); return false; }
        return true;
    }

    function noAtrib(op, alvo, valor, linha) {
        if (checarEscrita(alvo, linha)) {
            var v = op === '=' ? valor : noBin(op.slice(0, -1), alvo, valor, linha);
            verificarAtribuicao(alvo.tipo, v, linha, texto(alvo));
        }
        return { k: 'atrib', op: op, alvo: alvo, valor: valor, tipo: alvo.tipo, linha: linha };
    }

    function noIncDec(k, op, e, linha) {
        checarEscrita(e, linha);
        if (['inteiro', 'real', 'ponteiro', '?'].indexOf(categoria(e.tipo)) < 0) erro(linha, "'" + op + "' inválido para o tipo " + e.tipo);
        return { k: k, op: op, e: e, tipo: e.tipo, linha: linha };
    }

    function noUn(op, e, linha) {
        var c = categoria(e.tipo), t = e.tipo;
        if (op === '!') t = 'int';
        else if (op === '~' && c !== 'inteiro' && c !== '?') { erro(linha, "'~' exige operando inteiro"); t = '?'; }
        else if (op === '-' && c !== 'inteiro' && c !== 'real' && c !== '?') { erro(linha, "'-' unário inválido para " + e.tipo); t = '?'; }
        else if (op === '*') {
            t = c === '?' ? '?' : tipoElemento(e.tipo);
            if (!t) { erro(linha, "'" + texto(e) + "' não é ponteiro e não pode ser desreferenciado"); t = '?'; }
        }
        else if (op === '&') {
            if (!ehLvalue(e)) erro(linha, "'&' exige uma variável");
            t = c === '?' ? '?' : e.tipo + '*';
        }
        return { k: 'un', op: op, e: e, tipo: t, linha: linha };
    }

    function noIndice(base, idx, linha) {
        var t = categoria(base.tipo) === '?' ? '?' : tipoElemento(base.tipo);
        if (!t) { erro(linha, "'" + texto(base) + "' não é array nem ponteiro"); t = '?'; }
        if (['inteiro', '?'].indexOf(categoria(idx.tipo)) < 0) erro(linha, "índice de '" + texto(base) + "' deve ser inteiro, não " + idx.tipo);
        return { k: 'indice', base: base, idx: idx, tipo: t, linha: linha };
    }

    function noMembro(base, campo, seta, linha) {
        var bt = base.tipo, t = '?';
        if (bt !== '?') {
            if (seta) bt = /\*$/.test(bt) ? bt.slice(0, -1) : (erro(linha, "'->' exige ponteiro para struct/union"), '?');
            else if (/\*$/.test(bt)) { erro(linha, "use '->' para acessar membro através de ponteiro"); bt = '?'; }
            if (bt !== '?') {
                if (!structs[bt]) erro(linha, "'" + texto(base) + "' não é struct/union definida");
                else if (!structs[bt].hasOwnProperty(campo)) erro(linha, "'" + bt + "' não possui o membro '" + campo + "'");
                else t = structs[bt][campo];
            }
        }
        return { k: 'membro', base: base, campo: campo, seta: seta, tipo: t, linha: linha };
    }

    function noChamada(nome, args, linha) {
        var s = buscar(nome), tipo = '?';
        if (nome === 'malloc' || nome === 'calloc' || nome === 'realloc') log(linha, 'Alocação dinâmica de memória: ' + nome);
        if (nome === 'free') log(linha, 'Desalocação de memória: free');
        if (s && s.classe === 'funcao') {
            tipo = s.tipo;
            if (s.params && s.params.length !== args.length)
                erro(linha, "função '" + nome + "' espera " + s.params.length + " argumento(s), recebeu " + args.length);
        }
        else if (EMBUTIDAS.hasOwnProperty(nome)) tipo = EMBUTIDAS[nome];
        else erro(linha, "função '" + nome + "' não declarada");
        return { k: 'chamada', nome: nome, args: args, tipo: tipo, linha: linha };
    }

    function filhos(n) {
        switch (n.k) {
            case 'bin': return [n.l, n.r];
            case 'atrib': return [n.alvo, n.valor];
            case 'un': case 'pre': case 'pos': case 'cast': return [n.e];
            case 'indice': return [n.base, n.idx];
            case 'membro': return [n.base];
            case 'chamada': return n.args;
            case 'ternario': return [n.c, n.a, n.b];
            case 'lista': return n.itens;
        }
        return [];
    }

    function texto(n) {
        function sub(x) { return /^(bin|atrib|ternario)$/.test(x.k) ? '(' + texto(x) + ')' : texto(x); }
        switch (n.k) {
            case 'num': return n.valor;
            case 'id': return n.nome;
            case 'bin': return sub(n.l) + ' ' + n.op + ' ' + sub(n.r);
            case 'atrib': return texto(n.alvo) + ' ' + n.op + ' ' + texto(n.valor);
            case 'un': case 'pre': return n.op + sub(n.e);
            case 'pos': return sub(n.e) + n.op;
            case 'cast': return '(' + n.tipo + ')' + sub(n.e);
            case 'indice': return texto(n.base) + '[' + texto(n.idx) + ']';
            case 'membro': return texto(n.base) + (n.seta ? '->' : '.') + n.campo;
            case 'chamada': return n.nome + '(' + n.args.map(texto).join(', ') + ')';
            case 'sizeof': return 'sizeof(' + n.texto + ')';
            case 'ternario': return sub(n.c) + ' ? ' + sub(n.a) + ' : ' + sub(n.b);
            case 'lista': return '{' + n.itens.map(texto).join(', ') + '}';
        }
        return '?';
    }

    function rotulo(n) {
        var r = { num: n.valor, id: n.nome, bin: n.op, atrib: n.op, un: n.op + ' (unário)', pre: n.op + ' (pré)', pos: n.op + ' (pós)',
                  cast: 'cast', indice: '[ ]', membro: (n.seta ? '->' : '.') + n.campo, chamada: n.nome + '()',
                  sizeof: 'sizeof(' + n.texto + ')', ternario: '?:', lista: '{ }' }[n.k];
        return r + '  <' + n.tipo + '>';
    }

    function desenharArvore(n) {
        var linhas = [rotulo(n)];
        (function rec(no, prefixo) {
            var fs = filhos(no);
            fs.forEach(function (f, i) {
                var ultimo = i === fs.length - 1;
                linhas.push(prefixo + (ultimo ? '└── ' : '├── ') + rotulo(f));
                rec(f, prefixo + (ultimo ? '    ' : '│   '));
            });
        })(n, '    ');
        return linhas.map(function (l, i) { return i ? l : '    ' + l; }).join('\n');
    }

    /* ---------- código de três endereços ---------- */
    function novoTemp() { return 't' + (nTemp++); }
    function novoRotulo() { return 'L' + (nRotulo++); }
    function emitir(l) { tac.push(l); out('    TAC: ' + l); }

    function lugar(n) {
        if (n.k === 'id') return n.nome;
        if (n.k === 'indice') return gerar(n.base) + '[' + gerar(n.idx) + ']';
        if (n.k === 'membro') return gerar(n.base) + (n.seta ? '->' : '.') + n.campo;
        if (n.k === 'un' && n.op === '*') return '*' + gerar(n.e);
        return gerar(n);
    }

    function gerar(n) {
        var t, a, b, d, v;
        switch (n.k) {
            case 'num': return n.valor;
            case 'id': return n.nome;
            case 'sizeof': return 'sizeof(' + n.texto + ')';
            case 'membro': return lugar(n);
            case 'bin':
                a = gerar(n.l); b = gerar(n.r); t = novoTemp();
                emitir(t + ' = ' + a + ' ' + n.op + ' ' + b); return t;
            case 'un':
                a = gerar(n.e); t = novoTemp(); emitir(t + ' = ' + n.op + a); return t;
            case 'cast':
                a = gerar(n.e); t = novoTemp(); emitir(t + ' = (' + n.tipo + ') ' + a); return t;
            case 'indice':
                a = lugar(n); t = novoTemp(); emitir(t + ' = ' + a); return t;
            case 'chamada':
                v = n.args.map(gerar);
                v.forEach(function (p) { emitir('param ' + p); });
                t = novoTemp(); emitir(t + ' = call ' + n.nome + ', ' + v.length); return t;
            case 'pre':
                d = lugar(n.e); t = novoTemp();
                emitir(t + ' = ' + d + ' ' + n.op[0] + ' 1'); emitir(d + ' = ' + t); return t;
            case 'pos':
                d = lugar(n.e); t = novoTemp(); a = novoTemp();
                emitir(t + ' = ' + d); emitir(a + ' = ' + t + ' ' + n.op[0] + ' 1'); emitir(d + ' = ' + a); return t;
            case 'atrib':
                d = lugar(n.alvo); v = gerar(n.valor);
                if (n.op !== '=') { t = novoTemp(); emitir(t + ' = ' + d + ' ' + n.op.slice(0, -1) + ' ' + v); v = t; }
                emitir(d + ' = ' + v); return d;
            case 'ternario':
                var lf = novoRotulo(), lfim = novoRotulo();
                t = novoTemp();
                emitir('ifFalse ' + gerar(n.c) + ' goto ' + lf);
                emitir(t + ' = ' + gerar(n.a)); emitir('goto ' + lfim);
                emitir(lf + ':'); emitir(t + ' = ' + gerar(n.b)); emitir(lfim + ':');
                return t;
        }
        return '?';
    }

    function temAtribuicao(n) {
        return n.k === 'atrib' || n.k === 'pre' || n.k === 'pos' || filhos(n).some(temAtribuicao);
    }

    /* comando de expressão: mostra árvore e gera TAC quando há atribuição */
    function instrucaoExpr(n, linha) {
        if (!temAtribuicao(n)) return;
        log(linha, 'Atribuição: ' + texto(n));
        out('    Árvore sintática:');
        out(desenharArvore(n));
        gerar(n);
    }

    /* ---------- declarações ---------- */
    function declararItem(d) {
        var ctx = ctxDecl[ctxDecl.length - 1], info = ctx.info;
        var tipo = info.tipo + new Array(d.ptr + 1).join('*') + d.dims.map(function (x) { return '[' + x + ']'; }).join('');
        if (ctx.membros) { ctx.membros.push({ nome: d.nome, tipo: tipo, linha: d.linha }); return; }
        if (info.typedef) {
            typedefs[d.nome] = tipo;
            log(d.linha, 'typedef: ' + d.nome + ' = ' + tipo);
            declarar(d.nome, tipo, 'typedef', d.linha);
            return;
        }
        log(d.linha, 'Declaração de variável: ' + (info.mods.length ? info.mods.join(' ') + ' ' : '') + tipo + ' ' + d.nome);
        if (/^(struct|union) /.test(info.tipo) && !structs[info.tipo]) erro(d.linha, "'" + info.tipo + "' não foi definida");
        var s = declarar(d.nome, tipo, 'variavel', d.linha, { constante: info.constante, mods: info.mods });
        if (!d.init) return;
        if (s) s.valor = texto(d.init);
        var alvo = { k: 'id', nome: d.nome, tipo: tipo, simbolo: s, linha: d.linha };
        if (d.init.k === 'lista') {
            if (categoria(tipo) === 'array') {
                log(d.linha, 'Inicialização de array: ' + d.nome + ' = ' + texto(d.init));
                (function percorrer(lista, caminho) {
                    lista.itens.forEach(function (item, i) {
                        if (item.k === 'lista') return percorrer(item, caminho + '[' + i + ']');
                        verificarAtribuicao(tipoBase(tipo), item, d.linha, d.nome + caminho + '[' + i + ']');
                        emitir(d.nome + caminho + '[' + i + '] = ' + gerar(item));
                    });
                })(d.init, '');
            } else log(d.linha, 'Inicialização por lista: ' + d.nome + ' = ' + texto(d.init));
            return;
        }
        if (categoria(tipo) === 'array') { erro(d.linha, "array '" + d.nome + "' deve ser inicializado com { ... }"); return; }
        verificarAtribuicao(tipo, d.init, d.linha, d.nome);
        instrucaoExpr({ k: 'atrib', op: '=', alvo: alvo, valor: d.init, tipo: tipo, linha: d.linha }, d.linha);
    }

    function iniciarDecl(specs) { ctxDecl.push({ info: montarTipo(specs), membros: null }); }

    function definirAgregado(tipo, membros, linha) {
        var mapa = {};
        membros.forEach(function (m) {
            if (mapa.hasOwnProperty(m.nome)) erro(m.linha, "membro '" + m.nome + "' repetido em " + tipo);
            mapa[m.nome] = m.tipo;
        });
        structs[tipo] = mapa;
        log(linha, 'Definição de ' + tipo + ' { ' + membros.map(function (m) { return m.tipo + ' ' + m.nome; }).join('; ') + ' }');
        declarar(tipo, tipo, tipo.split(' ')[0], linha);
        return tipo;
    }

    function definirDefine(textoLinha, linha) {
        var m = /^#define\s+([A-Za-z_]\w*)\s*(.*)$/.exec(textoLinha);
        if (!m) { erros.push('Linha ' + linha + ': #define mal formado'); return; }
        var valor = m[2].replace(/\/\/.*$/, '').replace(/\/\*.*?\*\//g, '').trim();
        var tipo = /^-?\d+$/.test(valor) ? 'int' : /^-?(\d+\.\d*|\.\d+)([eE][+-]?\d+)?[fF]?$/.test(valor) ? 'double'
                 : /^".*"$/.test(valor) ? 'char*' : /^'.+'$/.test(valor) ? 'char' : valor === '' ? 'vazio' : '?';
        log(linha, '#define ' + m[1] + (valor ? ' = ' + valor : ''));
        declarar(m[1], tipo, 'define', linha, { valor: valor, constante: true });
    }

    /* ---------- relatório final ---------- */
    function tabela(linhas, colunas) {
        var larg = colunas.map(function (c) {
            return Math.max(c.length, Math.max.apply(null, linhas.map(function (l) { return String(l[c] === undefined ? '' : l[c]).length; }).concat([0])));
        });
        function fmt(vals) { return '| ' + vals.map(function (v, i) { v = String(v === undefined ? '' : v); return v + new Array(larg[i] - v.length + 1).join(' '); }).join(' | ') + ' |'; }
        var sep = '+' + larg.map(function (w) { return new Array(w + 3).join('-'); }).join('+') + '+';
        return [sep, fmt(colunas), sep].concat(linhas.map(function (l) { return fmt(colunas.map(function (c) { return l[c]; })); }), [sep]).join('\n');
    }

    function relatorio() {
        out('\n================ TABELA DE SÍMBOLOS ================');
        out(tabela(tabelaSimbolos, ['id', 'classe', 'tipo', 'modificadores', 'escopo', 'linha', 'valor']));
        out('\n================ CÓDIGO DE TRÊS ENDEREÇOS ================');
        tac.forEach(function (l, i) { out(('   ' + i).slice(-4) + ':  ' + l); });
        out('\n================ ERROS ================');
        if (avisos.length) avisos.forEach(function (a) { out('AVISO: ' + a); });
        if (erros.length) erros.forEach(function (e) { out('ERRO: ' + e); });
        else out('Nenhum erro semântico encontrado.');
    }

    /* Recuperação de erro: se faltar ';' no fim de uma linha, insere e reanalisa */
    var parseOriginal = parser.parse;
    parser.parse = function (fonte) {
        var inseridos = [];
        for (var tentativa = 0; tentativa < 50; tentativa++) {
            reiniciar();
            avisos = inseridos.slice();
            try {
                parseOriginal.call(this, fonte);
                out('\nAnálise léxica, sintática e semântica concluída.');
                relatorio();
                console.log(saida.join('\n'));
                return { simbolos: tabelaSimbolos, tac: tac, erros: erros };
            } catch (e) {
                if (!e.hash || e.hash.line === undefined) throw e;
                // e.hash.line = linha (0-based) do token inesperado
                var nLinha = e.hash.line, linhas = fonte.split('\n'), l = linhas[nLinha] || '';
                var recuo = l.length - l.replace(/^\s+/, '').length;
                var esperadoPv = (e.hash.expected || []).indexOf("';'") >= 0;
                if (esperadoPv && e.hash.token !== 'EOF' && nLinha > 0 && l.slice(recuo).indexOf(e.hash.text) === 0) {
                    linhas[nLinha] = l.slice(0, recuo) + ';' + l.slice(recuo);
                    fonte = linhas.join('\n');
                    inseridos.push("Linha " + nLinha + ": ';' ausente no fim do comando (inserido automaticamente)");
                    continue;
                }
                erros.push('Linha ' + (nLinha + 1) + ': ERRO SINTÁTICO perto de ' + JSON.stringify(e.hash.text) +
                           ', esperado: ' + (e.hash.expected || []).join(', '));
                relatorio();
                console.log(saida.join('\n'));
                process.exitCode = 1;
                return { simbolos: tabelaSimbolos, tac: tac, erros: erros };
            }
        }
    };
%}

%lex
%%

\s+                                             /* espaços */
"//".*                                          /* comentário de linha */
"/*"([^*]|\*+[^*/])*\*+"/"                      /* comentário de bloco */

"#include"[ \t]*("<"[^>\r\n]+">"|\"[^"\r\n]+\") return 'INCLUDE';
"#define"[^\r\n]*                               return 'DEFINE';

/* palavras reservadas */
"auto"          return 'AUTO';
"break"         return 'BREAK';
"case"          return 'CASE';
"char"          return 'CHAR';
"const"         return 'CONST';
"continue"      return 'CONTINUE';
"default"       return 'DEFAULT';
"double"        return 'DOUBLE';
"do"            return 'DO';
"else"          return 'ELSE';
"enum"          return 'ENUM';
"extern"        return 'EXTERN';
"float"         return 'FLOAT';
"for"           return 'FOR';
"goto"          return 'GOTO';
"if"            return 'IF';
"int"           return 'INT';
"long"          return 'LONG';
"register"      return 'REGISTER';
"return"        return 'RETURN';
"short"         return 'SHORT';
"signed"        return 'SIGNED';
"sizeof"        return 'SIZEOF';
"static"        return 'STATIC';
"struct"        return 'STRUCT';
"switch"        return 'SWITCH';
"typedef"       return 'TYPEDEF';
"union"         return 'UNION';
"unsigned"      return 'UNSIGNED';
"void"          return 'VOID';
"volatile"      return 'VOLATILE';
"while"         return 'WHILE';
"NULL"          return 'NULL';

/* literais */
[0-9]+"."[0-9]*([eE][+-]?[0-9]+)?[fFlL]?        return 'F_LIT';
"."[0-9]+([eE][+-]?[0-9]+)?[fFlL]?              return 'F_LIT';
[0-9]+[eE][+-]?[0-9]+[fFlL]?                    return 'F_LIT';
"0"[xX][0-9a-fA-F]+[uUlL]*                      return 'INT_LIT';
[0-9]+[uUlL]*                                   return 'INT_LIT';
\'([^'\\\n]|\\.)+\'                             return 'CHAR_LIT';
\"([^"\\\n]|\\.)*\"                             return 'STRING_LIT';

/* identificadores (nomes criados com typedef viram TYPE_NAME) */
[a-zA-Z_][a-zA-Z0-9_]*                          return typedefs.hasOwnProperty(yytext) ? 'TYPE_NAME' : 'IDF';

/* operadores */
"<<="           return 'SHL_IGUAL';
">>="           return 'SHR_IGUAL';
"->"            return 'SETA';
"++"            return 'INCREMENTO';
"--"            return 'DECREMENTO';
"+="            return 'MAIS_IGUAL';
"-="            return 'MENOS_IGUAL';
"*="            return 'MULT_IGUAL';
"/="            return 'DIV_IGUAL';
"%="            return 'MOD_IGUAL';
"&="            return 'AND_IGUAL';
"|="            return 'OR_IGUAL';
"^="            return 'XOR_IGUAL';
"<<"            return 'SHL';
">>"            return 'SHR';
"<="            return 'LE';
">="            return 'GE';
"=="            return 'EQ';
"!="            return 'NE';
"&&"            return 'AND';
"||"            return 'OR';
"!"             return 'NOT';
"~"             return '~';
"&"             return '&';
"|"             return '|';
"^"             return '^';
"<"             return '<';
">"             return '>';
"="             return '=';
"+"             return '+';
"-"             return '-';
"*"             return '*';
"/"             return '/';
"%"             return '%';
"?"             return '?';
":"             return ':';
"."             return '.';
"("             return '(';
")"             return ')';
"{"             return '{';
"}"             return '}';
"["             return '[';
"]"             return ']';
";"             return ';';
","             return ',';

<<EOF>>         return 'EOF';
.               { erros.push('Linha ' + yylloc.first_line + ": ERRO LÉXICO: caractere inválido '" + yytext + "'"); }

/lex

%start programa

%nonassoc IFX
%nonassoc ELSE
%right '=' MAIS_IGUAL MENOS_IGUAL MULT_IGUAL DIV_IGUAL MOD_IGUAL AND_IGUAL OR_IGUAL XOR_IGUAL SHL_IGUAL SHR_IGUAL
%right '?' ':'
%left OR
%left AND
%left '|'
%left '^'
%left '&'
%left EQ NE
%left '<' '>' LE GE
%left SHL SHR
%left '+' '-'
%left '*' '/' '%'
%right NOT '~' INCREMENTO DECREMENTO UNARIO CAST SIZEOF
%left '[' '.' SETA

%%

programa
    : elementos EOF
    ;

elementos
    : elementos elemento
    | /* vazio */
    ;

elemento
    : diretiva
    | funcao
    | comando
    ;

diretiva
    : INCLUDE   { log(@1.first_line, 'Diretiva include: ' + $1); }
    | DEFINE    { definirDefine($1, @1.first_line); }
    ;

/* ---------------- funções (apenas reconhecidas, não são o foco do trabalho) ---------------- */

funcao
    : cab_funcao ';'
        { fecharEscopo(@2.first_line); log(@1.first_line, 'Protótipo de função: ' + $1); }
    | cab_funcao '{' comandos '}'
        { fecharEscopo(@4.first_line); log(@1.first_line, 'Definição de função: ' + $1); }
    ;

cab_funcao
    : inicio_decl ponteiros_opt IDF '(' params_opt ')'
        {
            var info = ctxDecl.pop().info;
            var ret = info.tipo + new Array($2 + 1).join('*');
            $5 = $5.filter(function (p) { return p.nome || p.tipo !== 'void'; }); // f(void)
            declarar($3, ret, 'funcao', @3.first_line, { params: $5 });
            abrirEscopo(@4.first_line);
            $5.forEach(function (p) { if (p.nome) declarar(p.nome, p.tipo, 'variavel', p.linha); });
            $$ = $3;
        }
    ;

params_opt
    : lista_params      { $$ = $1; }
    | /* vazio */       { $$ = []; }
    ;

lista_params
    : param                     { $$ = [$1]; }
    | lista_params ',' param    { $$ = $1.concat([$3]); }
    ;

param
    : especificadores declarador
        {
            var info = montarTipo($1);
            $$ = { nome: $2.nome, linha: $2.linha,
                   tipo: info.tipo + new Array($2.ptr + 1).join('*') + ($2.dims.length ? '*' : '') };
        }
    | especificadores   { $$ = { tipo: montarTipo($1).tipo }; }
    ;

/* ---------------- declarações ---------------- */

declaracao
    : inicio_decl lista_decl    { ctxDecl.pop(); }
    | inicio_decl               { ctxDecl.pop(); }
    ;

inicio_decl
    : especificadores           { iniciarDecl($1); }
    ;

especificadores
    : especificador                     { $$ = [$1]; }
    | especificadores especificador     { $$ = $1.concat([$2]); }
    ;

especificador
    : INT { $$ = 'int'; } | CHAR { $$ = 'char'; } | FLOAT { $$ = 'float'; } | DOUBLE { $$ = 'double'; }
    | VOID { $$ = 'void'; } | LONG { $$ = 'long'; } | SHORT { $$ = 'short'; }
    | SIGNED { $$ = 'signed'; } | UNSIGNED { $$ = 'unsigned'; }
    | CONST { $$ = 'const'; } | VOLATILE { $$ = 'volatile'; }
    | STATIC { $$ = 'static'; } | EXTERN { $$ = 'extern'; } | REGISTER { $$ = 'register'; } | AUTO { $$ = 'auto'; }
    | TYPEDEF { $$ = 'typedef'; }
    | TYPE_NAME { $$ = typedefs[$1]; }
    | agregado { $$ = $1; }
    | enumeracao { $$ = $1; }
    ;

agregado
    : tipo_agregado IDF '{' membros '}'     { $$ = definirAgregado($1 + ' ' + $2, $4, @1.first_line); }
    | tipo_agregado '{' membros '}'         { $$ = definirAgregado($1 + ' <anônima>', $3, @1.first_line); }
    | tipo_agregado IDF                     { $$ = $1 + ' ' + $2; }
    ;

tipo_agregado
    : STRUCT    { $$ = 'struct'; }
    | UNION     { $$ = 'union'; }
    ;

membros
    : membro            { $$ = $1; }
    | membros membro    { $$ = $1.concat($2); }
    ;

membro
    : inicio_membro lista_decl ';'      { $$ = ctxDecl.pop().membros; }
    ;

inicio_membro
    : especificadores                   { ctxDecl.push({ info: montarTipo($1), membros: [] }); }
    ;

enumeracao
    : ENUM IDF '{' enumeradores virgula_opt '}' { valorEnum = 0; $$ = 'enum ' + $2; log(@1.first_line, 'Definição de ' + $$); }
    | ENUM '{' enumeradores virgula_opt '}'     { valorEnum = 0; $$ = 'enum <anônima>'; log(@1.first_line, 'Definição de ' + $$); }
    | ENUM IDF                                  { $$ = 'enum ' + $2; }
    ;

virgula_opt
    : ','
    | /* vazio */
    ;

enumeradores
    : enumerador
    | enumeradores ',' enumerador
    ;

enumerador
    : IDF               { declarar($1, 'int', 'constante', @1.first_line, { valor: String(valorEnum++), constante: true }); }
    | IDF '=' INT_LIT   { valorEnum = parseInt($3, 10); declarar($1, 'int', 'constante', @1.first_line, { valor: String(valorEnum++), constante: true }); }
    ;

lista_decl
    : var_item
    | lista_decl ',' var_item
    ;

var_item
    : declarador                        { declararItem($1); }
    | declarador '=' inicializador      { $1.init = $3; declararItem($1); }
    ;

declarador
    : ponteiros_opt IDF dims_opt        { $$ = { ptr: $1, nome: $2, dims: $3, linha: @2.first_line, init: null }; }
    ;

ponteiros_opt
    : ponteiros_opt '*'     { $$ = $1 + 1; }
    | /* vazio */           { $$ = 0; }
    ;

dims_opt
    : dims_opt '[' expr ']'     { $$ = $1.concat([texto($3)]); if (['inteiro', '?'].indexOf(categoria($3.tipo)) < 0) erro(@2.first_line, 'tamanho de array deve ser inteiro'); }
    | dims_opt '[' ']'          { $$ = $1.concat(['']); }
    | /* vazio */               { $$ = []; }
    ;

inicializador
    : expr                              { $$ = $1; }
    | '{' lista_inic '}'                { $$ = { k: 'lista', itens: $2, tipo: 'lista' }; }
    | '{' lista_inic ',' '}'            { $$ = { k: 'lista', itens: $2, tipo: 'lista' }; }
    ;

lista_inic
    : inicializador                     { $$ = [$1]; }
    | lista_inic ',' inicializador      { $$ = $1.concat([$3]); }
    ;

nome_tipo
    : especificadores ponteiros_opt     { $$ = montarTipo($1).tipo + new Array($2 + 1).join('*'); }
    ;

/* ---------------- comandos ---------------- */

bloco
    : abre_bloco comandos '}'           { fecharEscopo(@3.first_line); log(@1.first_line, 'Bloco { } (linhas ' + @1.first_line + '-' + @3.first_line + ')'); }
    ;

abre_bloco
    : '{'                               { abrirEscopo(@1.first_line); }
    ;

comandos
    : comandos comando
    | /* vazio */
    ;

comando
    : declaracao ';'
    | expr ';'                          { if (!temAtribuicao($1)) log(@1.first_line, 'Comando de expressão: ' + texto($1)); instrucaoExpr($1, @1.first_line); }
    | ';'
    | bloco
    | IF '(' expr ')' comando %prec IFX         { log(@1.first_line, 'Estrutura condicional IF (' + texto($3) + ')'); }
    | IF '(' expr ')' comando ELSE comando      { log(@1.first_line, 'Estrutura condicional IF-ELSE (' + texto($3) + ')'); }
    | WHILE '(' expr ')' comando                { log(@1.first_line, 'Laço WHILE (' + texto($3) + ')'); }
    | DO comando WHILE '(' expr ')' ';'         { log(@1.first_line, 'Laço DO-WHILE (' + texto($5) + ')'); }
    | abre_for for_init ';' expr_opt ';' expr_opt ')' comando
        {
            if ($6) instrucaoExpr($6, @6.first_line);
            fecharEscopo(@8.last_line);
            log(@1.first_line, 'Laço FOR (' + ($4 ? texto($4) : '') + ')');
        }
    | SWITCH '(' expr ')' comando
        {
            if (['inteiro', '?'].indexOf(categoria($3.tipo)) < 0) erro(@1.first_line, 'expressão do switch deve ser inteira');
            log(@1.first_line, 'Estrutura SWITCH (' + texto($3) + ')');
        }
    | CASE expr ':'                     { log(@1.first_line, 'CASE ' + texto($2)); }
    | DEFAULT ':'                       { log(@1.first_line, 'DEFAULT'); }
    | BREAK ';'                         { log(@1.first_line, 'BREAK'); }
    | CONTINUE ';'                      { log(@1.first_line, 'CONTINUE'); }
    | RETURN expr_opt ';'               { log(@1.first_line, 'RETURN' + ($2 ? ' ' + texto($2) : '')); }
    | GOTO IDF ';'                      { log(@1.first_line, 'GOTO ' + $2); }
    | IDF ':'                           { log(@1.first_line, 'Rótulo ' + $1); }
    ;

abre_for
    : FOR '('                           { abrirEscopo(@1.first_line); }
    ;

for_init
    : declaracao
    | expr                              { instrucaoExpr($1, @1.first_line); }
    | /* vazio */
    ;

expr_opt
    : expr          { $$ = $1; }
    | /* vazio */   { $$ = null; }
    ;

/* ---------------- expressões ---------------- */

expr
    : expr '=' expr             { $$ = noAtrib('=', $1, $3, @2.first_line); }
    | expr MAIS_IGUAL expr      { $$ = noAtrib('+=', $1, $3, @2.first_line); }
    | expr MENOS_IGUAL expr     { $$ = noAtrib('-=', $1, $3, @2.first_line); }
    | expr MULT_IGUAL expr      { $$ = noAtrib('*=', $1, $3, @2.first_line); }
    | expr DIV_IGUAL expr       { $$ = noAtrib('/=', $1, $3, @2.first_line); }
    | expr MOD_IGUAL expr       { $$ = noAtrib('%=', $1, $3, @2.first_line); }
    | expr AND_IGUAL expr       { $$ = noAtrib('&=', $1, $3, @2.first_line); }
    | expr OR_IGUAL expr        { $$ = noAtrib('|=', $1, $3, @2.first_line); }
    | expr XOR_IGUAL expr       { $$ = noAtrib('^=', $1, $3, @2.first_line); }
    | expr SHL_IGUAL expr       { $$ = noAtrib('<<=', $1, $3, @2.first_line); }
    | expr SHR_IGUAL expr       { $$ = noAtrib('>>=', $1, $3, @2.first_line); }
    | expr '?' expr ':' expr    { $$ = { k: 'ternario', c: $1, a: $3, b: $5, tipo: $3.tipo, linha: @2.first_line }; log(@2.first_line, 'Operador ternário ?:'); }
    | expr OR expr              { $$ = noBin('||', $1, $3, @2.first_line); }
    | expr AND expr             { $$ = noBin('&&', $1, $3, @2.first_line); }
    | expr '|' expr             { $$ = noBin('|', $1, $3, @2.first_line); }
    | expr '^' expr             { $$ = noBin('^', $1, $3, @2.first_line); }
    | expr '&' expr             { $$ = noBin('&', $1, $3, @2.first_line); }
    | expr EQ expr              { $$ = noBin('==', $1, $3, @2.first_line); }
    | expr NE expr              { $$ = noBin('!=', $1, $3, @2.first_line); }
    | expr '<' expr             { $$ = noBin('<', $1, $3, @2.first_line); }
    | expr '>' expr             { $$ = noBin('>', $1, $3, @2.first_line); }
    | expr LE expr              { $$ = noBin('<=', $1, $3, @2.first_line); }
    | expr GE expr              { $$ = noBin('>=', $1, $3, @2.first_line); }
    | expr SHL expr             { $$ = noBin('<<', $1, $3, @2.first_line); }
    | expr SHR expr             { $$ = noBin('>>', $1, $3, @2.first_line); }
    | expr '+' expr             { $$ = noBin('+', $1, $3, @2.first_line); }
    | expr '-' expr             { $$ = noBin('-', $1, $3, @2.first_line); }
    | expr '*' expr             { $$ = noBin('*', $1, $3, @2.first_line); }
    | expr '/' expr             { $$ = noBin('/', $1, $3, @2.first_line); }
    | expr '%' expr             { $$ = noBin('%', $1, $3, @2.first_line); }
    | NOT expr                  { $$ = noUn('!', $2, @1.first_line); }
    | '~' expr                  { $$ = noUn('~', $2, @1.first_line); }
    | '-' expr %prec UNARIO     { $$ = noUn('-', $2, @1.first_line); }
    | '+' expr %prec UNARIO     { $$ = $2; }
    | '*' expr %prec UNARIO     { $$ = noUn('*', $2, @1.first_line); }
    | '&' expr %prec UNARIO     { $$ = noUn('&', $2, @1.first_line); }
    | INCREMENTO expr           { $$ = noIncDec('pre', '++', $2, @1.first_line); }
    | DECREMENTO expr           { $$ = noIncDec('pre', '--', $2, @1.first_line); }
    | expr INCREMENTO           { $$ = noIncDec('pos', '++', $1, @2.first_line); }
    | expr DECREMENTO           { $$ = noIncDec('pos', '--', $1, @2.first_line); }
    | '(' nome_tipo ')' expr %prec CAST     { $$ = { k: 'cast', tipo: $2, e: $4, linha: @1.first_line }; log(@1.first_line, 'Conversão de tipo (' + $2 + ')'); }
    | SIZEOF '(' nome_tipo ')'  { $$ = { k: 'sizeof', texto: $3, tipo: 'int', linha: @1.first_line }; }
    | SIZEOF '(' expr ')'       { $$ = { k: 'sizeof', texto: texto($3), tipo: 'int', linha: @1.first_line }; }
    | expr '[' expr ']'         { $$ = noIndice($1, $3, @2.first_line); }
    | expr '.' IDF              { $$ = noMembro($1, $3, false, @2.first_line); }
    | expr SETA IDF             { $$ = noMembro($1, $3, true, @2.first_line); }
    | IDF '(' args_opt ')'      { $$ = noChamada($1, $3, @1.first_line); }
    | '(' expr ')'              { $$ = $2; }
    | IDF                       { $$ = noId($1, @1.first_line); }
    | INT_LIT                   { $$ = noNum($1, 'int', @1.first_line); }
    | F_LIT                     { $$ = noNum($1, 'double', @1.first_line); }
    | CHAR_LIT                  { $$ = noNum($1, 'char', @1.first_line); }
    | STRING_LIT                { $$ = noNum($1, 'char*', @1.first_line); }
    | NULL                      { $$ = noNum('NULL', 'void*', @1.first_line); }
    ;

args_opt
    : args          { $$ = $1; }
    | /* vazio */   { $$ = []; }
    ;

args
    : expr              { $$ = [$1]; }
    | args ',' expr     { $$ = $1.concat([$3]); }
    ;
