-- ============================================================
-- ARQUIVO: 0001_init.sql
-- OBJETIVO: Criar toda a estrutura do banco de dados do e-commerce
--            (clientes, produtos, pedidos e automações)
-- AUTOR: Renan Rosa
-- ============================================================

-- 🔹 Ativa extensões úteis no PostgreSQL/Supabase
-- "uuid-ossp" → cria identificadores únicos (UUID)
-- "pg_trgm" → melhora buscas por similaridade de texto
create extension if not exists "uuid-ossp";
create extension if not exists pg_trgm;

-- ============================================================
-- 🔹 Criação de tipos personalizados
-- ENUM = tipo de campo com valores fixos pré-definidos
-- Usado aqui para o status do pedido
-- ============================================================
create type public.order_status as enum (
  'pending',   -- Pedido feito, aguardando pagamento
  'paid',      -- Pago
  'shipped',   -- Enviado
  'delivered', -- Entregue
  'canceled'   -- Cancelado
);

-- ============================================================
-- 🔹 TABELA: customers (clientes)
-- Guarda informações do cliente vinculado ao usuário do Supabase Auth
-- ============================================================
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(), -- Identificador único
  user_id uuid unique references auth.users (id) on delete cascade, -- Ligação com usuário autenticado
  full_name text not null,       -- Nome completo
  email text not null unique,    -- E-mail do cliente
  phone text,                    -- Telefone (opcional)
  created_at timestamptz not null default now()  -- Data de criação
);

-- ============================================================
-- 🔹 TABELA: products (produtos)
-- Armazena os produtos disponíveis na loja
-- ============================================================
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,       -- Código do produto
  name text not null,             -- Nome do produto
  description text,               -- Descrição
  price_cents integer not null check (price_cents >= 0), -- Preço em centavos
  currency text not null default 'BRL',                  -- Moeda
  stock integer not null default 0 check (stock >= 0),   -- Estoque disponível
  active boolean not null default true,                  -- Produto ativo?
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 🔹 TABELA: orders (pedidos)
-- Cada pedido pertence a um cliente
-- ============================================================
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  status public.order_status not null default 'pending',
  total_cents integer not null default 0 check (total_cents >= 0),
  placed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 🔹 TABELA: order_items (itens do pedido)
-- Lista os produtos comprados dentro de um pedido
-- ============================================================
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid not null references public.products (id),
  quantity integer not null check (quantity > 0),  -- Quantidade de unidades
  unit_price_cents integer not null check (unit_price_cents >= 0), -- Preço unitário
  created_at timestamptz not null default now()
);

-- ============================================================
-- 🔹 Índices para acelerar consultas
-- ============================================================
create index if not exists idx_products_active on public.products(active);
create index if not exists idx_orders_customer on public.orders(customer_id);
create index if not exists idx_order_items_order on public.order_items(order_id);

-- ============================================================
-- 🔹 Função: atualizar automaticamente o campo updated_at
-- Executa sempre que o registro for alterado
-- ============================================================
create or replace function public.set_updated_at() 
returns trigger 
language plpgsql 
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Criação dos gatilhos (triggers)
create trigger trg_products_updated
  before update on public.products
  for each row execute function public.set_updated_at();

create trigger trg_orders_updated
  before update on public.orders
  for each row execute function public.set_updated_at();

-- ============================================================
-- 🔹 Função: calcular o total de um pedido
-- Soma (quantidade * preço) de todos os itens do pedido
-- ============================================================
create or replace function public.compute_order_total(p_order_id uuid)
returns integer 
language sql 
stable 
as $$
  select coalesce(sum(oi.quantity * oi.unit_price_cents), 0)
  from public.order_items oi
  where oi.order_id = p_order_id;
$$;

-- ============================================================
-- 🔹 Trigger: atualizar automaticamente o total do pedido
-- ============================================================
create or replace function public.update_order_total() 
returns trigger 
language plpgsql 
as $$
begin
  update public.orders o
     set total_cents = public.compute_order_total(o.id)
   where o.id = coalesce(new.order_id, old.order_id);
  return null;
end;
$$;

create trigger trg_order_items_total_aiud
  after insert or update or delete on public.order_items
  for each row execute function public.update_order_total();

-- ============================================================
-- 🔹 Função RPC: place_order
-- Cria um novo pedido a partir de uma lista de produtos (em JSON)
-- e atualiza automaticamente o estoque e o total
-- ============================================================
create or replace function public.place_order(items jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_order_id uuid;
  v_user_id uuid := auth.uid(); -- Pega o usuário logado
  v_item jsonb;
  v_product_id uuid;
  v_qty int;
  v_price int;
begin
  if v_user_id is null then
    raise exception 'Usuário não autenticado';
  end if;

  select c.id into v_customer_id from public.customers c where c.user_id = v_user_id;
  if v_customer_id is null then
    raise exception 'Cliente não encontrado';
  end if;

  insert into public.orders(customer_id) values (v_customer_id) returning id into v_order_id;

  -- Percorre os itens enviados no JSON
  for v_item in select * from jsonb_array_elements(items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::int;

    if v_qty is null or v_qty <= 0 then
      raise exception 'Quantidade inválida';
    end if;

    select price_cents into v_price 
    from public.products p 
    where p.id = v_product_id and p.active = true;

    if v_price is null then
      raise exception 'Produto inválido ou inativo';
    end if;

    -- Atualiza estoque (subtrai quantidade comprada)
    update public.products p 
      set stock = stock - v_qty 
      where p.id = v_product_id and p.stock >= v_qty;

    if not found then
      raise exception 'Estoque insuficiente';
    end if;

    insert into public.order_items(order_id, product_id, quantity, unit_price_cents)
    values (v_order_id, v_product_id, v_qty, v_price);
  end loop;

  return v_order_id;
end;
$$;

-- ============================================================
-- 🔹 Função: alterar status do pedido (com segurança)
-- Apenas o dono pode cancelar; admin pode mudar livremente
-- ============================================================
create or replace function public.set_order_status(p_order_id uuid, p_next public.order_status)
returns void 
language plpgsql 
security definer 
as $$
declare
  v_curr public.order_status;
  v_cust uuid;
  v_user uuid := auth.uid();
begin
  select status, customer_id into v_curr, v_cust from public.orders where id = p_order_id;
  if v_curr is null then raise exception 'Pedido não encontrado'; end if;

  if v_user is not null and exists(select 1 from public.customers c where c.id = v_cust and c.user_id = v_user) then
    if p_next <> 'canceled' or v_curr <> 'pending' then
      raise exception 'Ação não permitida';
    end if;
  end if;

  update public.orders set status = p_next where id = p_order_id;
end;
$$;

-- ============================================================
-- 🔹 Fila de e-mails (mail_queue)
-- Guarda e-mails de confirmação de pedido para envio automático
-- ============================================================
create table if not exists public.mail_queue (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  to_email text not null,
  payload jsonb not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

-- ============================================================
-- 🔹 Trigger: quando o pedido muda para "paid", envia e-mail
-- ============================================================
create or replace function public.enqueue_order_confirmation() 
returns trigger 
language plpgsql 
as $$
declare 
  v_email text; 
  v_name text; 
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    select email, full_name into v_email, v_name
    from public.customers c where c.id = new.customer_id;
    insert into public.mail_queue(order_id, to_email, payload)
    values (new.id, v_email, jsonb_build_object('customer_name', v_name));
  end if;
  return new;
end;
$$;

create trigger trg_orders_paid_enqueue
  after update of status on public.orders
  for each row execute function public.enqueue_order_confirmation();

-- ============================================================
-- 🔹 VIEWs (visões)
-- Servem para facilitar consultas prontas
-- ============================================================
create or replace view public.v_products as
  select id, sku, name, description, price_cents, currency, stock, active
  from public.products 
  where active = true;

create or replace view public.v_my_orders as
  select o.*
  from public.orders o
  join public.customers c on c.id = o.customer_id
  where c.user_id = auth.uid();

-- ============================================================
-- 🔹 Regras de segurança RLS (Row Level Security)
-- Cada usuário só vê o que é dele
-- ============================================================
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.mail_queue enable row level security;

-- Clientes: só o dono pode ver, editar e criar o próprio registro
create policy customers_select_own on public.customers
  for select using (user_id = auth.uid());
create policy customers_update_own on public.customers
  for update using (user_id = auth.uid());
create policy customers_insert_self on public.customers
  for insert with check (user_id = auth.uid());

-- Produtos: qualquer um pode visualizar, mas apenas o sistema pode alterar
create policy products_select_all on public.products for select using (true);

-- Pedidos: o cliente só vê e cria os seus
create policy orders_select_own on public.orders for select using (
  exists(select 1 from public.customers c where c.id = orders.customer_id and c.user_id = auth.uid())
);
create policy orders_insert_owner on public.orders for insert with check (
  exists(select 1 from public.customers c where c.id = orders.customer_id and c.user_id = auth.uid())
);
create policy orders_update_none on public.orders for update using (false);

-- Itens do pedido: seguem a regra do pedido
create policy order_items_select_own on public.order_items for select using (
  exists(
    select 1 from public.orders o
    join public.customers c on c.id = o.customer_id
    where o.id = order_items.order_id and c.user_id = auth.uid()
  )
);
create policy order_items_insert_owner on public.order_items for insert with check (
  exists(
    select 1 from public.orders o
    join public.customers c on c.id = o.customer_id
    where o.id = order_items.order_id and c.user_id = auth.uid()
  )
);
create policy order_items_update_none on public.order_items for update using (false);

-- Fila de e-mails: ninguém acessa, só o sistema
create policy mail_queue_block_all on public.mail_queue for all using (false) with check (false);
