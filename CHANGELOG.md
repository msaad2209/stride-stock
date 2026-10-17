# StrideStock fix release: findings and contract

## Root causes

- The phone could keep an older installed PWA because the previous worker did not enforce immediate activation, did not verify the deployed build version, and cached navigations without a freshness check. The stock-entry and RPC errors on the phone were consistent with that older bundle still calling the removed `add_stock` RPC.
- The prior barcode flow defaulted to a single label per variant. That ignored the number of newly added physical pairs. Batch printing now sums each variant's `stock_entries` for that batch; normal stock printing defaults to current quantity.
- The batch save view hid the actual Supabase error behind generic catch handling. RPC errors now preserve the database code/details/hint and provide friendly messages only for recognized network, version, permission, uniqueness, and check-constraint cases.
- The old migrations seeded sample shops/designs. Seeding has been removed and the explicit maintenance reset is separate from migration execution.

## RPC contract

Every frontend RPC call goes through `src/lib/rpc.ts`; parameter names and database signatures below are the PostgREST contract.

| Function | Database parameters | Frontend parameters |
|---|---|---|
| `get_schema_version` | none | `{}` |
| `check_functions` | none | `{}` |
| `check_rls_enabled` | none | `{}` |
| `add_stock_batch` | `p_payload jsonb, p_shop_id uuid` | `p_payload, p_shop_id` |
| `batch_label_rows` | `p_batch_id uuid, p_shop_id uuid` | `p_batch_id, p_shop_id` |
| `search_variants` | `p_q text, p_category uuid, p_size text, p_color text, p_stock text, p_limit integer, p_offset integer, p_shop_id uuid, p_batch_id uuid, p_sort text, p_since timestamptz` | same names; `p_since` optional |
| `shop_stats` | `p_shop_id uuid` | `p_shop_id` |
| `list_sales` | `p_shop_id uuid, p_from timestamptz, p_to timestamptz, p_status text, p_q text, p_limit integer, p_offset integer, p_category uuid` | same names |
| `shop_colors` | `p_shop_id uuid` | `p_shop_id` |
| `sell_variant` | `p_sku_code text, p_sold_price numeric, p_client_ref uuid, p_shop_id uuid` | same names |
| `return_sale` | `p_sale_id uuid, p_reason text, p_shop_id uuid` | same names |
| `adjust_stock` | `p_variant_id uuid, p_delta integer, p_note text, p_shop_id uuid` | same names |

## Migration and checks

`003_fix.sql` marks schema version 3, removes stale `add_stock` and sale/return overloads, adds the batch-label RPC and admin diagnostics, and asks PostgREST to reload its schema. It preserves stock and sales. `reset_all_data.sql` is destructive and deliberately requires the administrator to edit its confirmation literal before a manual run.

Run `npm test` and `npm run build` before release. SQL regression checks are under `tests/`; they are scripts, not auto-run against the live Supabase project.
