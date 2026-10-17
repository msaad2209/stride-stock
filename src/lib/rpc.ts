import type { PostgrestError } from '@supabase/supabase-js';
import { supabase } from './supabase';

export type RpcArgs = {
  get_schema_version: Record<string, never>;
  check_functions: Record<string, never>;
  check_rls_enabled: Record<string, never>;
  add_stock_batch: { p_payload: Record<string, unknown>; p_shop_id: string };
  batch_label_rows: { p_batch_id: string; p_shop_id: string };
  search_variants: { p_q: string; p_category: string | null; p_size: string | null; p_color: string | null; p_stock: string; p_limit: number; p_offset: number; p_shop_id: string | null; p_batch_id: string | null; p_sort: string; p_since?: string | null };
  shop_stats: { p_shop_id: string | null };
  list_sales: { p_shop_id: string | null; p_from: string | null; p_to: string | null; p_status: string; p_q: string; p_limit: number; p_offset: number; p_category: string | null };
  shop_colors: { p_shop_id: string | null };
  sell_variant: { p_sku_code: string; p_sold_price: number; p_client_ref: string; p_shop_id: string };
  return_sale: { p_sale_id: string; p_reason: string | null; p_shop_id: string | null };
  adjust_stock: { p_variant_id: string; p_delta: number; p_note: string; p_shop_id: string };
};

export class RpcClientError extends Error {
  readonly code?: string;
  readonly details?: string;
  readonly hint?: string;
  constructor(message: string, fields: { code?: string; details?: string; hint?: string } = {}) {
    super(message); this.name = 'RpcClientError'; Object.assign(this, fields);
  }
}

function normalize(error: PostgrestError | Error | unknown): RpcClientError {
  const e = error as Partial<PostgrestError> & { message?: string; name?: string; code?: string; details?: string; hint?: string };
  const raw = e?.message || String(error || 'Unknown database error');
  const code = e?.code;
  let message = raw;
  if (code === 'PGRST202' || /could not find the function|schema cache/i.test(raw)) message = 'App and database versions do not match. Reload the app or run the latest SQL migration.';
  else if (code === '42501') message = 'Permission denied for this shop.';
  else if (code === '23505') message = 'This item or variant already exists. Check the article, color, and size.';
  else if (code === '23514') message = 'The requested value is not allowed (for example, stock cannot be negative).';
  else if (code === '57014') message = 'The database request timed out. Check your connection and retry.';
  else if (error instanceof TypeError && (/failed to fetch|fetch failed|network error/i.test(raw) || (typeof navigator !== 'undefined' && !navigator.onLine))) message = 'Network error. Check your internet connection and retry.';
  const details = [code && `Code: ${code}`, e?.details && `Details: ${e.details}`, e?.hint && `Hint: ${e.hint}`, raw !== message && `Message: ${raw}`].filter(Boolean).join('\n');
  console.error('[StrideStock RPC]', { message, code, details: e?.details, hint: e?.hint, raw });
  return new RpcClientError(message, { code, details: details || raw, hint: e?.hint });
}

export async function rpcCall<K extends keyof RpcArgs>(name: K, args: RpcArgs[K]): Promise<{ data: any; error: RpcClientError | null }> {
  if (!supabase) return { data: null, error: new RpcClientError('Supabase is not configured.') };
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const result = await Promise.race([
      supabase.rpc(name, args as never),
      new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new RpcClientError('Database request timed out after 20 seconds. Check your connection and verify the result before retrying.', { code: 'CLIENT_TIMEOUT' })), 20_000); }),
    ]);
    return result.error ? { data: null, error: normalize(result.error) } : { data: result.data, error: null };
  } catch (error) {
    return { data: null, error: normalize(error) };
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export function rpcErrorText(error: unknown): string {
  if (error instanceof RpcClientError) return `${error.message}\n\nDETAILS:\n${error.details || error.message}`;
  return error instanceof Error ? error.message : String(error || 'Unexpected error');
}
