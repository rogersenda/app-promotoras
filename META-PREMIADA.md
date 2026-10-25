# Meta Premiada — app de campanhas "compre e ganhe" com cupom fiscal

Um único arquivo (`meta-premiada.html`) com três partes:

| Parte | Endereço | Quem usa |
|---|---|---|
| App do cliente | `meta-premiada.html#/c/<campanha>/<rede>` | Consumidor final |
| Área da equipe | `meta-premiada.html#/admin` | Diretoria, representantes e aprovadores |
| Material de PDV | aberto pela aba Redes › "Material de PDV" | Impressão para a loja |

Serve para qualquer campanha e qualquer marca: nome, marcas, cores, datas, faixas e prêmios são configurados na aba **Campanhas**.

## Dois modos

**Demonstração**: é o padrão e funciona assim que o arquivo é aberto. Os dados ficam só no aparelho. Use-o para apresentar a mecânica às redes na negociação: abra no tablet, cadastre um cliente, use "Preencher com cupom de teste", aprove o cupom na área da equipe e mostre o painel. PIN da equipe: `1234`.

**Online (campanha real)**: os dados ficam num banco central (Supabase), e cliente, lojas e diretoria veem a mesma informação.
1. Crie uma conta e um projeto em supabase.com. O plano gratuito atende para começar.
2. Em SQL Editor, cole e rode `meta-premiada-supabase.sql`.
3. Em Authentication › Users, crie o usuário (e-mail e senha) de cada pessoa da equipe. Depois, no SQL Editor: `insert into mp_admins(email) values ('email@empresa.com.br');`
4. Em Settings › API, copie a *Project URL* e a chave *anon public* e cole no topo de `meta-premiada.html` (`SUPABASE_URL` e `SUPABASE_ANON_KEY`).
5. Publique o arquivo num endereço com **https** (GitHub Pages, Netlify ou Vercel) para que a câmera do celular funcione.
6. Antes de divulgar, faça um teste completo com 2 ou 3 cupons reais.

## Fluxo da campanha

1. **Campanhas**: crie a campanha, defina marcas, período, faixas padrão e gere o regulamento-modelo. **Revise o regulamento com o jurídico.**
2. **Redes**: cadastre cada rede em negociação. O simulador mostra o pedido extra, a verba de prêmios e se o custo dos prêmios cabe na verba.
3. Quando o pedido for faturado, informe a NF e mude o status para **Ativa**. A partir daí as faixas ficam travadas e os cupons dessas lojas passam a contar.
4. Gere o **Material de PDV** e o **link/QR Code** da rede.
5. **Aprovar cupons**: a equipe confere a foto e aprova ou recusa. Alertas automáticos apontam os casos suspeitos.
6. **Prêmios**: ranking por faixa e estoque, e registro de entrega com conferência de documento.
7. **Clientes/CRM**: exporte a base. Para marketing, use só "quem autorizou".

## Controles de justiça e transparência

- A chave de acesso do cupom (44 dígitos) é validada pelo dígito verificador e só pode ser usada **uma vez**. O banco garante isso.
- A loja (CNPJ na chave) precisa estar numa rede **ativa**. Compras antes da ativação não contam.
- Data dentro do período e conferida com o mês da chave. Limite de cupons por dia.
- CPF na nota exigido. No SAT, o QR traz o CPF, e o app recusa se ele for diferente do cadastro.
- Alertas para o aprovador: funcionário da rede, valor alto, vários cupons no mesmo dia e loja, numeração sequencial, chave digitada à mão e celular repetido.
- Faixas travadas depois da ativação da rede. Prêmios por ordem de atingimento.
- Auditoria de tudo (aprovações, recusas, mudanças, entregas e exportações). No modo online ela não pode ser apagada.
- LGPD: aceite do regulamento obrigatório e consentimento de marketing separado e opcional, com data registrada.

## Atenção legal

O modo "compre e ganhe" (prêmio garantido por faixa) é o padrão. **Sorteio para consumidor exige autorização prévia da SPA/Ministério da Fazenda**, por isso o app só libera números da sorte com o número do certificado de autorização preenchido. Confirme tudo com o jurídico antes de lançar.

## Próximas melhorias sugeridas

- Login do cliente por código via SMS ou WhatsApp. Hoje o cliente entra com CPF e data de nascimento.
- Leitura automática dos itens do cupom (OCR) para pré-preencher o valor das marcas.
- Perfis de acesso: representante vê só as próprias redes.
