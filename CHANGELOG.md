# Changelog

## v2 (2026-10-17)

- Fixed stock search root cause: the beta sent PostgREST `.or()` filters against `variants.sku_code` and `variants.color` while the joined item name/article fields lived in another table, then performed additional filtering in the browser. This query never searched item name/article consistently and special punctuation could also break the PostgREST filter syntax. The v2 UI uses a parameterized Postgres RPC over trigger-maintained, lowercase `variants.search_text`, with whitespace-token matching and a GIN trigram index. Search results are paginated in SQL.
- Added shop profiles, shop-scoped RLS, admin shop selection, the Shop 2 seed, and the standard 14 categories. Old categories are retained and inactive for new stock.
- Added size-wise set multipliers, multiple colors per intake, atomic stock batch RPC, batch-linked labels, sales search, sale retry idempotency, back-dated return RPC, SQL totals, paginated history, chunked admin exports, and CSV ZIP backup.
- Added the `admin-manage-users` Supabase Edge Function and changed keepalive to use a no-data `ping()` RPC.
