-- =====================================================================
-- Meta Premiada — banco de dados do modo online (Supabase)
-- Como usar: Supabase > SQL Editor > New query > cole este arquivo > Run.
-- Depois, em "mp_admins", cadastre o e-mail de cada pessoa da equipe
-- (o mesmo e-mail criado em Authentication > Users).
-- =====================================================================

-- Tabelas (cada registro guarda os dados em JSON, igual ao modo demonstração)
create table if not exists mp_config    (id text primary key, data jsonb not null, created_at timestamptz default now());
create table if not exists mp_campanhas (id text primary key, data jsonb not null, created_at timestamptz default now());
create table if not exists mp_redes     (id text primary key, data jsonb not null, created_at timestamptz default now());
create table if not exists mp_clientes  (id text primary key, data jsonb not null, created_at timestamptz default now());
create table if not exists mp_cupons    (id text primary key, data jsonb not null, created_at timestamptz default now());
create table if not exists mp_premios   (id text primary key, data jsonb not null, created_at timestamptz default now());
create table if not exists mp_audit     (id text primary key, data jsonb not null, created_at timestamptz default now());
create table if not exists mp_admins    (email text primary key);

-- Regras que o banco garante sozinho, mesmo se alguém burlar o app:
-- um cupom (chave de acesso) só pode ser usado uma vez; um CPF só tem um cadastro.
create unique index if not exists mp_cupons_chave  on mp_cupons  ((data->>'chave'));
create unique index if not exists mp_clientes_cpf  on mp_clientes ((data->>'cpf'));
create index if not exists mp_cupons_cliente on mp_cupons ((data->>'clienteId'));

-- A auditoria não pode ser apagada nem alterada
create or replace function mp_audit_imutavel() returns trigger language plpgsql as $$
begin raise exception 'A auditoria não pode ser alterada'; end $$;
drop trigger if exists mp_audit_lock on mp_audit;
create trigger mp_audit_lock before update or delete on mp_audit for each row execute function mp_audit_imutavel();

-- Quem é administrador
create or replace function mp_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from mp_admins where lower(email) = lower(coalesce(auth.jwt()->>'email','')));
$$;

-- Segurança: por padrão ninguém lê nada; a equipe (admins) lê e grava tudo
do $$ declare t text; begin
  foreach t in array array['mp_config','mp_campanhas','mp_redes','mp_clientes','mp_cupons','mp_premios','mp_audit','mp_admins'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists adm_all on %I', t);
    execute format('create policy adm_all on %I for all to authenticated using (mp_is_admin()) with check (mp_is_admin())', t);
  end loop;
end $$;

-- O público (app do cliente) só lê config e campanhas
drop policy if exists pub_read on mp_config;
create policy pub_read on mp_config for select to anon, authenticated using (true);
drop policy if exists pub_read on mp_campanhas;
create policy pub_read on mp_campanhas for select to anon, authenticated using (true);

-- Redes visíveis ao público: só ativas/encerradas e sem dados da negociação
create or replace function mp_redes_publicas(p_camp text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', data->'id', 'campId', data->'campId', 'nome', data->'nome', 'status', data->'status',
    'ativadaEm', data->'ativadaEm', 'faixas', data->'faixas', 'premiosSorteio', coalesce(data->'premiosSorteio','[]'::jsonb),
    'lojas', (select coalesce(jsonb_agg(jsonb_build_object('id', l->'id', 'nome', l->'nome', 'cnpj', l->'cnpj', 'cidade', l->'cidade')), '[]'::jsonb)
              from jsonb_array_elements(coalesce(data->'lojas','[]'::jsonb)) l)
  )), '[]'::jsonb)
  from mp_redes where data->>'campId' = p_camp and data->>'status' in ('ativa','encerrada');
$$;

-- Cliente: identificação por CPF + data de nascimento
create or replace function mp_cliente(p_cpf text, p_nasc text) returns jsonb
language sql stable security definer set search_path = public as $$
  select data from mp_clientes where data->>'cpf' = p_cpf and data->>'nascimento' = p_nasc limit 1;
$$;

create or replace function mp_cadastrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p->>'cpf','') !~ '^\d{11}$' then raise exception 'CPF inválido'; end if;
  if exists(select 1 from mp_clientes where data->>'cpf' = p->>'cpf') then raise exception 'CPF_JA_CADASTRADO'; end if;
  p := p || jsonb_build_object('criadoEm', to_jsonb(now()));
  insert into mp_clientes(id, data) values (p->>'id', p);
  return p;
end $$;

create or replace function mp_login(p_cpf text, p_nasc text) returns jsonb
language sql stable security definer set search_path = public as $$ select mp_cliente(p_cpf, p_nasc); $$;

create or replace function mp_meus_dados(p_cpf text, p_nasc text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb;
begin
  c := mp_cliente(p_cpf, p_nasc);
  if c is null then return null; end if;
  return jsonb_build_object('cliente', c, 'cupons',
    (select coalesce(jsonb_agg(data - 'foto'), '[]'::jsonb) from mp_cupons where data->>'clienteId' = c->>'id'));
end $$;

create or replace function mp_enviar_cupom(p_cpf text, p_nasc text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c jsonb; r jsonb; hoje_envios int; lim int;
begin
  c := mp_cliente(p_cpf, p_nasc);
  if c is null then raise exception 'SESSAO'; end if;
  if coalesce(p->>'chave','') !~ '^\d{44}$' then raise exception 'Chave de acesso inválida'; end if;
  if exists(select 1 from mp_cupons where data->>'chave' = p->>'chave') then raise exception 'CUPOM_JA_USADO'; end if;
  -- a loja precisa pertencer a uma rede ativa da campanha
  select data into r from mp_redes
   where data->>'campId' = p->>'campId' and data->>'status' = 'ativa'
     and exists(select 1 from jsonb_array_elements(coalesce(data->'lojas','[]'::jsonb)) l where l->>'cnpj' = substr(p->>'chave', 7, 14))
   limit 1;
  if r is null then raise exception 'A loja deste cupom não participa da campanha'; end if;
  select coalesce((data->'limites'->>'cuponsDia')::int, 0) into lim from mp_campanhas where id = p->>'campId';
  select count(*) into hoje_envios from mp_cupons where data->>'clienteId' = c->>'id' and created_at::date = now()::date;
  if lim > 0 and hoje_envios >= lim then raise exception 'Limite de cupons por dia atingido'; end if;
  -- campos definidos pelo servidor (o app não consegue forjar)
  p := p || jsonb_build_object('clienteId', c->>'id', 'redeId', r->>'id', 'cnpj', substr(p->>'chave', 7, 14),
                               'status', 'pendente', 'enviadoEm', to_jsonb(now()));
  p := p - 'valorAprovado' - 'analisadoPor' - 'analisadoEm' - 'numeros' - 'motivo';
  insert into mp_cupons(id, data) values (p->>'id', p);
  return p - 'foto';
end $$;

-- Lista pública de números da sorte (nome abreviado e CPF mascarado — mesma regra do app,
-- para que o código de verificação SHA-256 confira)
create or replace function mp_numeros_publicos(p_camp text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'redeId', cu.data->>'redeId', 'n', n.v,
    'nome', (regexp_split_to_array(btrim(cl.data->>'nome'), '\s+'))[1] ||
            coalesce(' ' || left((regexp_split_to_array(btrim(cl.data->>'nome'), '\s+'))[2], 1) || '.', ''),
    'cpf', '***.' || substr(cl.data->>'cpf', 4, 3) || '.' || substr(cl.data->>'cpf', 7, 3) || '-**'
  ) order by cu.data->>'redeId', n.v), '[]'::jsonb)
  from mp_cupons cu
  join mp_clientes cl on cl.id = cu.data->>'clienteId'
  cross join lateral jsonb_array_elements_text(coalesce(cu.data->'numeros', '[]'::jsonb)) n(v)
  where cu.data->>'campId' = p_camp and cu.data->>'status' = 'aprovado';
$$;

-- Aprovação de cupom pela equipe. Gera os números da sorte no próprio banco, com trava,
-- para que dois aprovadores ao mesmo tempo nunca gerem números repetidos.
create or replace function mp_aprovar(p_id text, p_valor numeric, p_por text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cu jsonb; ca jsonb; tot numeric; tem int; novos int; seq int; nums jsonb := '[]'::jsonb; vpn numeric;
begin
  if not mp_is_admin() then raise exception 'Sem permissão'; end if;
  select data into cu from mp_cupons where id = p_id for update;
  if cu is null then raise exception 'Cupom não encontrado'; end if;
  if cu->>'status' = 'aprovado' then raise exception 'Cupom já aprovado'; end if;
  perform pg_advisory_xact_lock(hashtext('mp_num_' || (cu->>'campId')));
  select data into ca from mp_campanhas where id = cu->>'campId';
  cu := cu || jsonb_build_object('status','aprovado','valorAprovado',p_valor,'motivo','','analisadoPor',p_por,'analisadoEm',to_jsonb(now()));
  vpn := coalesce((ca->'sorteio'->>'valorPorNumero')::numeric, 0);
  if coalesce(ca->>'formato','faixas') <> 'faixas' and vpn > 0 and (ca->'sorteio'->>'congelado') is null then
    select coalesce(sum((data->>'valorAprovado')::numeric),0), coalesce(sum(jsonb_array_length(coalesce(data->'numeros','[]'::jsonb))),0)
      into tot, tem from mp_cupons
     where data->>'campId' = cu->>'campId' and data->>'clienteId' = cu->>'clienteId' and data->>'redeId' = cu->>'redeId'
       and data->>'status' = 'aprovado' and id <> p_id;
    novos := floor((tot + p_valor) / vpn)::int - tem;
    select coalesce(max(v::int), 0) into seq from mp_cupons, jsonb_array_elements_text(coalesce(data->'numeros','[]'::jsonb)) v
     where data->>'campId' = cu->>'campId';
    for i in 1..greatest(novos, 0) loop seq := seq + 1; nums := nums || to_jsonb(lpad(seq::text, 6, '0')); end loop;
  end if;
  cu := cu || jsonb_build_object('numeros', nums);
  update mp_cupons set data = cu where id = p_id;
  return cu;
end $$;

grant execute on function mp_numeros_publicos(text) to anon, authenticated;
grant execute on function mp_aprovar(text, numeric, text) to authenticated;
grant execute on function mp_redes_publicas(text), mp_cadastrar(jsonb), mp_login(text,text), mp_meus_dados(text,text),
  mp_enviar_cupom(text,text,jsonb), mp_is_admin() to anon, authenticated;
revoke execute on function mp_cliente(text,text) from anon, authenticated, public;

-- Fotos dos cupons: o cliente pode enviar; só a equipe pode ver
insert into storage.buckets (id, name, public) values ('mp-cupons', 'mp-cupons', false) on conflict (id) do nothing;
drop policy if exists "mp envio de fotos" on storage.objects;
create policy "mp envio de fotos" on storage.objects for insert to anon, authenticated with check (bucket_id = 'mp-cupons');
drop policy if exists "mp equipe ve fotos" on storage.objects;
create policy "mp equipe ve fotos" on storage.objects for select to authenticated using (bucket_id = 'mp-cupons' and mp_is_admin());

-- Configuração inicial
insert into mp_config(id, data) values ('geral', '{"id":"geral","appNome":"Meta Premiada"}') on conflict (id) do nothing;

-- >>> Troque pelo seu e-mail (e repita para cada pessoa da equipe):
-- insert into mp_admins(email) values ('seu-email@empresa.com.br');
