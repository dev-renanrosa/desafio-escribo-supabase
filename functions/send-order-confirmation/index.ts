// ============================================================
// ARQUIVO: send-order-confirmation/index.ts
// OBJETIVO: Enviar e-mails de confirmação quando o pedido é pago
// ============================================================

// Importa a biblioteca do Supabase (usada para acessar o banco)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Lê as variáveis de ambiente configuradas no Supabase
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; // chave secreta (service role)
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY"); // chave opcional de envio de e-mails

// Função que envia o e-mail (pode usar a API Resend ou simular)
async function sendEmail(to: string, subject: string, html: string) {
  if (!RESEND_API_KEY) {
    console.log("[AVISO] RESEND_API_KEY não configurada — simulando envio...");
    return { ok: true };
  }

  // Faz a requisição para a API de envio de e-mails
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: "no-reply@escribo.dev", to, subject, html }),
  });

  if (!res.ok) throw new Error(await res.text());
  return await res.json();
}

// Função principal executada quando a Edge Function é chamada
export default async function handler(req: Request) {
  // Cria um cliente Supabase com permissão total (service role)
  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Busca até 10 e-mails pendentes na fila (mail_queue)
  const { data: pendentes, error } = await client
    .from("mail_queue")
    .select("id, order_id, to_email, payload")
    .eq("status", "pending")
    .limit(10);

  if (error) return new Response(error.message, { status: 500 });
  if (!pendentes || pendentes.length === 0)
    return new Response("Nenhum e-mail pendente.");

  // Envia os e-mails um por um
  for (const row of pendentes) {
    const assunto = `Confirmação do pedido ${row.order_id}`;
    const nomeCliente = row.payload?.customer_name ?? "Cliente";

    const html = `
      <p>Olá, ${nomeCliente}!</p>
      <p>Recebemos o pagamento do seu pedido <b>${row.order_id}</b>.</p>
      <p>Em breve você receberá atualizações de envio.</p>
    `;

    try {
      await sendEmail(row.to_email, assunto, html);
      await client
        .from("mail_queue")
        .update({ status: "sent", processed_at: new Date().toISOString() })
        .eq("id", row.id);
    } catch (e) {
      console.error(e);
      await client
        .from("mail_queue")
        .update({ status: "error", processed_at: new Date().toISOString() })
        .eq("id", row.id);
    }
  }

  return new Response("E-mails processados com sucesso!");
}
