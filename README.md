# 🧩 Desafio Técnico – Escribo (Backend Supabase + IA)

Este projeto implementa o **backend completo de um e-commerce educativo**, usando **Supabase** como banco de dados e **Edge Functions** para automação com IA.

---

## 🚀 Objetivo
Atender aos requisitos do teste técnico da Escribo, implementando:

1. Criação de tabelas (clientes, produtos, pedidos e itens).
2. Políticas de segurança **RLS** completas.
3. Funções SQL automáticas (triggers e RPC).
4. Views para facilitar consultas.
5. Edge Functions para:
   - Envio de e-mail de confirmação de pedido.
   - Exportação de pedido em CSV.

---

## 🗂️ Estrutura do Projeto

desafio-escribo-supabase/
│
├─ supabase/
│ ├─ migrations/
│ │ └─ 0001_init.sql → Criação de tabelas e funções
│ └─ seed/
│ └─ products.seed.sql → Inserção de produtos de exemplo
│
└─ functions/
├─ send-order-confirmation/
│ └─ index.ts → Envia e-mail de confirmação
└─ export-order-csv/
└─ index.ts → Gera o CSV do pedido


---

## ⚙️ Requisitos

- **Supabase CLI** instalado  
- **Node.js 18+**  
- Uma conta no [Supabase](https://supabase.com)  
- (Opcional) Conta no [Resend](https://resend.com) para envio real de e-mails  

---

## 🧠 Passo a Passo para Rodar

### 1️⃣ Inicializar o projeto
```bash
supabase init

supabase start

supabase db reset

psql "$SUPABASE_DB_URL" -f supabase/seed/products.seed.sql

| Função                         | Descrição                                             |
| ------------------------------ | ----------------------------------------------------- |
| `place_order(items)`           | Cria um pedido e atualiza estoque automaticamente.    |
| `set_order_status(id, status)` | Altera o status do pedido (cliente só pode cancelar). |
| `compute_order_total(id)`      | Calcula o valor total do pedido.                      |

GET https://<project>.functions.supabase.co/export-order-csv?order_id=<UUID>
Authorization: Bearer <JWT_DO_USUARIO>

curl -X POST 'https://<project>.supabase.co/rest/v1/rpc/place_order' \
-H 'apikey: <anon>' -H 'Authorization: Bearer <JWT>' \
-H 'Content-Type: application/json' \
-d '{"items":[{"product_id":"<uuid_produto>","quantity":2}]}'



