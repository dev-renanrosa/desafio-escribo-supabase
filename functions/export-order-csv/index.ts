// ============================================================
// ARQUIVO: export-order-csv/index.ts
// OBJETIVO: Gerar e baixar o pedido do cliente em formato CSV
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Essas variáveis vêm do ambiente configurado no Supabase
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!; // usa o RLS

export default async function handler(req: Request) {
  // Só permite método GET
  if (req.method !== "GET") 
    return new Response("Método não permitido", { status: 405 });

  // Pega o ID do pedido (order_id) da URL
  const url = new URL(req.url);
  const orderId = url.searchParams.get("order_id");

  if (!orderId) 
    return new Response("Parâmetro order_id é obrigatório", { status: 400 });

  // Verifica se o usuário está autenticado
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) 
    return new Response("Autenticação necessária", { status: 401 });

  // Extrai o token JWT
  const jwt = authHeader.replace(/^Bearer\\s+/i, "");

  // Cria o cliente Supabase com o token do usuário (respeita RLS)
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { 
    global: { headers: { Authorization: `Bearer ${jwt}` } }
  });

  // Busca os itens do pedido com base no ID (somente se pertencer ao usuário logado)
  const { data: items, error } = await client
    .from("order_items")
    .select("order_id, product_id, quantity, unit_price_cents, products(name, sku)")
    .eq("order_id", orderId);

  if (error) return new Response(error.message, { status: 500 });
  if (!items || items.length === 0) 
    return new Response("Pedido não encontrado ou sem permissão", { status: 404 });

  // Monta o conteúdo do CSV
  const header = ["SKU", "Nome", "Quantidade", "Preço_Unitário", "Subtotal"];
  const rows = items.map((it: any) => [
    it.products?.sku ?? "",
    it.products?.name ?? "",
    it.quantity,
    it.unit_price_cents,
    it.quantity * it.unit_price_cents,
  ]);

  const csv = [header.join(","), ...rows.map(r => r.join(","))].join("\\n");

  // Retorna o CSV como download
  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename=pedido_${orderId}.csv`
    }
  });
}
