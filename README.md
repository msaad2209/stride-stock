# StrideStock

StrideStock is a mobile-first footwear inventory and sales app. It runs as a static installable PWA and uses Supabase for sign-in, online data, database safeguards and shop isolation. The browser only uses the public anon key; never add a service-role key to the frontend or Cloudflare Pages.

## Before you start

You need a free Supabase account/project, a GitHub account and a free Cloudflare account. No SQL program needs to be installed: run migrations in the Supabase website's SQL Editor. The project builds with Node.js and npm.

## Release and live database update

Follow these steps in order. The updated frontend deliberately blocks sign-in use until schema version 3 exists.

1. **Run `003_fix.sql`.** In Supabase Dashboard, open your project → **SQL Editor** → **New query**. Open `supabase/migrations/003_fix.sql` from this repository, copy the entire file into the editor, then click **Run**. Wait for Success. This is additive and preserves current stock and sales. It installs the version guard and label/RPC fixes.
2. **Reset test data only if you intend to erase it.** Open `supabase/maintenance/reset_all_data.sql` in the repository. Near the top, edit `confirm text := '';` to `confirm text := 'DELETE EVERYTHING';`, then copy all of that file into a new Supabase SQL Editor query and Run. This permanently deletes every shop, item, variant, stock entry, sale, category and shop account; it keeps the admin account. Skip this step if any business data should be kept. Do not paste or run this maintenance script without editing and reviewing its confirmation line.
3. **Redeploy the Edge Function.** Install the free Supabase CLI, open PowerShell in the repository folder, and run:

   ```powershell
   npx supabase login
   npx supabase link --project-ref klcjwirbjosgiljbasiv
   npx supabase functions deploy admin-manage-users
   ```

   The function gets its service-role secret from Supabase's server-side runtime. Do not copy that secret into `.env`, GitHub, Cloudflare Pages, or frontend code.
4. **Push the app release.** Push the current branch to GitHub. Cloudflare Pages should start a build automatically. In Cloudflare Dashboard → **Workers & Pages** → `stride-stock` → **Deployments**, wait until the latest deployment is successful.
5. **Verify the release.** Open `https://stride-stock.pages.dev`, sign in as the admin, and open **Admin → System check** (or `/admin/system`). Confirm database schema, RPCs, RLS, app version and the Edge Function are green. Refresh the page if a release completed while it was already open.
6. **Refresh older phone installs.** The phone checks for updates on launch, on focus and every five minutes. If it still shows the old screen, close the app fully and reopen it twice, or reinstall it. Confirm its footer version matches the laptop.
7. **Create the first shop and shop account.** In **Admin**, enter the business's shop name and choose **Create shop**. The standard categories are created for it automatically. Then create a shop login with an email, temporary password, display name and that shop. Sign in to the shop account in a private browser window to verify its access.
8. **Run the acceptance checklist** below before entering live stock.

## Run locally

1. Install Node.js LTS from [nodejs.org](https://nodejs.org/).
2. In the repository folder, copy `.env.example` to `.env.local`.
3. In Supabase Dashboard → **Project Settings → API**, copy the Project URL and anon/public key into `.env.local`:

   ```env
   VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
   VITE_SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
   ```

   The anon key is designed for browser use and protected by RLS. Never use the service-role key here.
4. In PowerShell, run:

   ```powershell
   npm install
   npm run dev
   ```

5. Open the local URL shown by Vite. Camera access requires HTTPS, so camera scanning should be tested on the deployed `https://` site, not a plain HTTP phone connection.

## GitHub and Cloudflare Pages

1. Push this repository to GitHub. In Cloudflare Dashboard, open **Workers & Pages → Create → Pages → Connect to Git** and choose the repository.
2. Set production branch to `main`, build command to `npm run build`, and output directory to `dist`.
3. Under the Pages project's **Settings → Environment variables**, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for Production (and Preview if you will use preview deployments). Save and redeploy.
4. Commit and push changes to `main`; Cloudflare builds each push. Confirm the deployment is successful before sharing it.

## Install on a phone and use the camera

Open the deployed HTTPS URL in Chrome on Android or Safari on iPhone. Android: browser menu → **Install app** or **Add to Home screen**. iPhone: Safari **Share** → **Add to Home Screen**. Open the installed app, sign in and go to **Sell → Scan with camera**. Allow camera access. You can also type or keyboard-scan a SKU into the always-visible field and press Enter.

Camera tips: use good light, hold the phone about 15–25 cm from the label, print labels at least 38 mm wide, and avoid glossy laminate glare. The camera requires HTTPS. If permission was denied, allow it in the browser/site settings and retry.

## Everyday use

- **Add incoming stock:** enter item and article number, category, size range and per-size pair count, then add one or more colors and set counts. Existing article/color/size combinations are reused and quantity is added. The successful batch shows its exact pair count and offers **Print N labels**.
- **Print box labels:** select labels from the same stock-entry batch to print exactly the newly added pairs. Search stock to print one label per pair currently in stock, one per variant, or a custom amount. Labels use the same barcode for identical pairs. Use the browser print dialog; choose **Save as PDF** there if needed.
- **Sell:** scan, use a keyboard-wedge scanner, type a SKU, or search item/article and pick a size. Confirm the price to save the sale. The scanner ignores the same code for two seconds. Returns restore one pair exactly once.
- **Stock and sales:** use search, category/size/color filters and the stock status filter. Quantity adjustments require a reason. Sales history supports date, category, status and text filters.
- **Admin and Excel:** admins can download stock and sales as `.xlsx`, items as `.csv`, and a full CSV ZIP backup. Exports page through large datasets. Imports preview and validate before adding; imports do not overwrite sales history.

## Acceptance checklist

- Add a test article with sizes 37–41 and one color; set size 39 to 2 pairs and the others to 1. It should show five variants, six pairs and **Print 6 labels**. Preview/print includes two labels for size 39.
- Add a second color and verify it creates separate barcodes per color/size. Repeat the same article/color/size and verify quantity increases without duplicate variants.
- Print a label, scan it from the phone, edit its price, and confirm. Check stock drops by one and today's sales shows the exact sale price. Scan the same label again within two seconds; it must not double-submit.
- Sell the last pair, verify another sale is blocked, then return the first sale and confirm stock is restored once.
- Search a color in Stock; combine a size and category filter. Check the phone and laptop show the same app version.
- Export Stock as `.xlsx` and open it in Excel. Test a shop account in a private window: it must only see its assigned shop and `/admin` must redirect away.
- To verify isolation fully, create a second shop and account, then confirm that account cannot see the first shop's records.

## Data and security

All business data is online; there is no offline stock or sale mode. `shop_id` scopes all business tables and RLS policies. Admin users can manage shops/accounts and view exports; shop users are limited to their assigned shop. Soft-deactivate stock/category records in the UI rather than deleting sales history. Timestamps are stored in UTC and displayed in Asia/Kolkata; currency is INR.

Monthly, download Stock, Sales and the full ZIP backup, then store a copy somewhere safe. Supabase Dashboard table views can also export individual tables to CSV; open those CSV files in Excel. The weekly GitHub Actions keepalive makes a GET request to the Supabase REST API root with the public anon key. Add GitHub repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY` for that workflow.

## Database files

- `supabase/migrations/001_init.sql`: original base schema.
- `supabase/migrations/002_v2.sql`: shop profiles, policies, search and shop RPCs.
- `supabase/migrations/003_fix.sql`: v3 release fix; run this against the live project before using the new frontend.
- `supabase/seed.sql`: intentionally does not create shops or sample inventory. Admin creates the shops.
- `supabase/maintenance/reset_all_data.sql`: separate, manual, confirmation-gated destructive reset.
- `tests/`: Vitest utilities and SQL safety scripts. SQL test scripts are for a disposable test database or reviewed transaction; never run fixtures against live data without understanding them.

## Future roadmap (not implemented)

- Multiple users with roles and permissions
- Multi-shop switching for staff
- Supplier and purchase tracking
- GST invoices
- Offline mode
