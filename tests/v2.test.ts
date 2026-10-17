import { describe, expect, it } from 'vitest';
import { expandImportRow, expandSetVariants, importRowInput, labelCopies, totalLabelCount, expandLabelChunk, searchTokens, tokenSearchMatches } from '../src/lib/v2-utils';
import { expandSizes } from '../src/lib/utils';

describe('v2 set quantities', () => {
  it('rejects fractional sizes unless half sizes are enabled', () => {
    expect(() => expandSizes(7.5, 9)).toThrow('enable half sizes');
    expect(expandSizes(7.5, 9, true)).toEqual(['7.5','8','8.5','9']);
  });
  it('multiplies the shared size pattern by each color set count', () => {
    const rows = expandSetVariants(37, 41, false, { '37':1,'38':1,'39':2,'40':1,'41':1 }, [
      { color:'Black', sets:2 }, { color:'Brown', sets:1 },
    ]);
    expect(rows).toEqual([
      {color:'Black',size:'37',quantity:2},{color:'Black',size:'38',quantity:2},{color:'Black',size:'39',quantity:4},{color:'Black',size:'40',quantity:2},{color:'Black',size:'41',quantity:2},
      {color:'Brown',size:'37',quantity:1},{color:'Brown',size:'38',quantity:1},{color:'Brown',size:'39',quantity:2},{color:'Brown',size:'40',quantity:1},{color:'Brown',size:'41',quantity:1},
    ]);
  });
  it('expands import overrides and set counts', () => {
    const row = importRowInput.parse({ item_name:'Sparx', article_no:'A101', category:'Shoes - Gents', color:'Black', size_from:'7', size_to:'10', qty_per_size:'1', size_qty_overrides:'8:2;9:2', sets:'2', default_price:'1499' });
    expect(expandImportRow(row)).toEqual([
      {color:'Black',size:'7',quantity:2},{color:'Black',size:'8',quantity:4},{color:'Black',size:'9',quantity:4},{color:'Black',size:'10',quantity:2},
    ]);
  });
  it('rejects malformed overrides and invalid size ranges', () => {
    expect(importRowInput.safeParse({item_name:'x',article_no:'a',category:'c',color:'Black',size_from:10,size_to:7,qty_per_size:1,default_price:0}).success).toBe(false);
    const valid = importRowInput.parse({item_name:'x',article_no:'a',category:'c',color:'Black',size_from:7,size_to:8,qty_per_size:1,default_price:0});
    expect(()=>expandImportRow({...valid,size_qty_overrides:'8:two'})).toThrow('Invalid size quantity override');
  });
});

describe('database search token preparation', () => {
  it('keeps all words and matches multi-word item/article queries', () => {
    expect(searchTokens(' Sparx   A101 ')).toEqual(['sparx','a101']);
    expect(tokenSearchMatches('sparx runner a101 black 8 fw000123','sparx a101')).toBe(true);
    expect(tokenSearchMatches('sparx runner a101 black','sparx unknown')).toBe(false);
  });
  it('treats percent and apostrophe as ordinary token characters', () => {
    expect(searchTokens(" 100% John's ")).toEqual(['100%','john\'s']);
    expect(tokenSearchMatches("100% john's black", "100% John's")).toBe(true);
  });
});

describe('physical pair labels', () => {
  const rows = [
    { id:'37', quantity:1, qty_added:1 }, { id:'38', quantity:1, qty_added:1 },
    { id:'39', quantity:2, qty_added:2 }, { id:'40', quantity:1, qty_added:1 }, { id:'41', quantity:1, qty_added:1 },
  ];
  it('prints one label per physical pair added in the batch', () => {
    expect(totalLabelCount(rows, 'batch')).toBe(6);
    expect(labelCopies(rows[2], 'batch')).toBe(2);
    expect(expandLabelChunk(rows, 'batch', 0, 100)).toHaveLength(6);
    expect(expandLabelChunk(rows, 'batch', 0, 100).filter(row => row.id === '39')).toHaveLength(2);
  });
  it('splits a large print job into chunks without losing or duplicating labels', () => {
    const many = Array.from({length:200}, (_, i) => ({id:String(i), quantity:3, qty_added:3}));
    expect(totalLabelCount(many, 'batch')).toBe(600);
    const first = expandLabelChunk(many, 'batch', 0, 100);
    const next = expandLabelChunk(many, 'batch', 100, 100);
    expect(first).toHaveLength(100);
    expect(next).toHaveLength(100);
    expect(first.map(r => r.id)).not.toEqual(next.map(r => r.id));
  });
});
