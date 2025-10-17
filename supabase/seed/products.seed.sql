-- ============================================================
-- ARQUIVO: products.seed.sql
-- OBJETIVO: Inserir produtos de exemplo na tabela "products"
-- ============================================================

-- Cada linha adiciona um produto de exemplo com código (SKU),
-- nome, descrição, preço (em centavos) e quantidade em estoque.

insert into public.products (sku, name, description, price_cents, stock)
values
('BK-001', 'Livro Infantil A', 'Livro ilustrado com atividades educativas', 3990, 50),
('BK-002', 'Livro Infantil B', 'Histórias curtas para leitura infantil', 4590, 30),
('BK-003', 'Jogo Educacional', 'Jogo de alfabetização divertido e interativo', 5990, 20)
on conflict do nothing;  -- Evita erro se os produtos já existirem
