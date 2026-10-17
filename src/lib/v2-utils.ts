import { z } from 'zod';
import { expandSizes } from './utils';

export const batchVariantInput = z.object({ color: z.string().trim().min(1), size: z.string().trim().min(1), quantity: z.number().int().min(0) });
export const batchInput = z.object({
  name: z.string().trim().min(1), article_no: z.string().trim().min(1), category_id: z.string().uuid(),
  default_price: z.coerce.number().finite().min(0), cost_price: z.union([z.literal(''), z.coerce.number().finite().min(0)]),
  variants: z.array(batchVariantInput).min(1),
}).refine((input) => input.variants.some((variant) => variant.quantity > 0), { message: 'At least one size quantity must be above zero' });

export const importRowInput = z.object({
  item_name: z.string().trim().min(1), article_no: z.string().trim().min(1), category: z.string().trim().min(1),
  color: z.string().trim().min(1), size_from: z.coerce.number().finite(), size_to: z.coerce.number().finite(),
  qty_per_size: z.coerce.number().int().min(0), size_qty_overrides: z.string().optional().default(''),
  sets: z.coerce.number().int().min(1).default(1), default_price: z.coerce.number().finite().min(0),
  cost_price: z.union([z.literal(''), z.coerce.number().finite().min(0)]).optional().default(''),
}).refine((row) => row.size_from <= row.size_to, { message: 'Size start must be less than or equal to size end', path: ['size_to'] });

export function expandSetVariants(from: number, to: number, half: boolean, pattern: Record<string, number>, colors: Array<{ color: string; sets: number }>) {
  const sizes = expandSizes(from, to, half);
  return colors.flatMap(({ color, sets }) => sizes.map((size) => ({
    color: color.trim(), size, quantity: (pattern[size] ?? 0) * sets,
  }))).filter((variant) => variant.quantity > 0);
}

export function expandImportRow(row: z.infer<typeof importRowInput>) {
  const sizes = expandSizes(row.size_from, row.size_to);
  const overrides: Record<string, number> = {};
  for (const part of row.size_qty_overrides.split(';').filter(Boolean)) {
    const match = /^\s*(\d+(?:\.5)?)\s*:\s*(\d+)\s*$/.exec(part);
    if (!match) throw new Error(`Invalid size quantity override: ${part}`);
    const [, size, quantity] = match;
    overrides[size] = Number(quantity);
  }
  return sizes.map((size) => ({ color: row.color, size, quantity: (overrides[size] ?? row.qty_per_size) * row.sets })).filter((v) => v.quantity > 0);
}

export const searchTokens = (query: string) => query.trim().toLocaleLowerCase('en-IN').split(/\s+/).filter(Boolean);
export const tokenSearchMatches = (haystack: string, query: string) => searchTokens(query).every((token) => haystack.toLocaleLowerCase('en-IN').includes(token));

export type LabelRow = { id: string; quantity: number; qty_added?: number };
export type LabelCopyMode = 'batch' | 'stock' | 'variant' | 'custom';
export function labelCopies(row: LabelRow, mode: LabelCopyMode, customCopies = 1): number {
  if (mode === 'batch') return Math.max(0, row.qty_added || 0);
  if (mode === 'stock') return Math.max(0, row.quantity || 0);
  if (mode === 'custom') return Math.max(0, Math.floor(customCopies));
  return 1;
}
export function totalLabelCount(rows: LabelRow[], mode: LabelCopyMode, customCopies = 1): number {
  return rows.reduce((total, row) => total + labelCopies(row, mode, customCopies), 0);
}
export function expandLabelChunk<T extends LabelRow>(rows: T[], mode: LabelCopyMode, offset: number, limit = 100, customCopies = 1): T[] {
  const result: T[] = [];
  let skip = Math.max(0, offset);
  for (const row of rows) {
    const count = labelCopies(row, mode, customCopies);
    if (skip >= count) { skip -= count; continue; }
    const copies = Math.min(count - skip, limit - result.length);
    for (let index = 0; index < copies; index += 1) result.push(row);
    skip = 0;
    if (result.length >= limit) break;
  }
  return result;
}
