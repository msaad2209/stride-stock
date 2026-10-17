# StrideStock — footwear shop stock and sales

An installable, mobile-first web app for footwear shops. It keeps stock, sales, returns, labels and exports online through Supabase. The v2 upgrade supports an admin account, shop-scoped staff accounts, Shop 1 and Shop 2, plus an all-shops read-only admin view.

## Set up your free Supabase project

1. Go to [supabase.com](https://supabase.com) and create a free project. Choose a strong database password and keep it somewhere safe.
2. In the project, open **SQL Editor**. Paste and run `supabase/migrations/001_init.sql` first. Then paste and run `supabase/seed.sql` to add Shop 1, starter categories and three sample designs.
3. Open **Authentication → Users → Add user**. Create your admin with an email and password. There is no sign-up screen in the app.
4. For this v2 app, open `supabase/migrations/002_v2.sql` in a text editor, replace `REPLACE_WITH_ADMIN_EMAIL` in the marked admin setup block with that Auth user's email, then paste the full file into Supabase **SQL Editor** and click **Run**. This adds profiles, Shop 2, the new categories and shop-scoped security. Keep the file for your records.
5. In **Project Settings → API**, copy the Project URL and the public anon/publishable key. Never put the `service_role` key in this app.

## Run it on your computer

1. Install the current Node.js LTS version from [nodejs.org](https://nodejs.org).
2. Open a terminal in this folder and run `npm install`.
3. Copy `.env.example` to `.env.local`. Replace the two example values with the Supabase Project URL and public anon key.
4. Run `npm run dev` and open the local address printed in the terminal. Sign in with the admin account.
5. `npm test` runs the included checks. `npm run build` creates the website in `dist`.

## Put it online with Cloudflare Pages

1. Push this folder to a private GitHub repository. In GitHub repository settings, add secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY` for the weekly keepalive workflow. The anon key is public by design; RLS still protects data.
2. In [Cloudflare Pages](https://pages.cloudflare.com/), choose **Create a project → Connect to Git** and select your repository.
3. Set framework preset to **Vite**, build command to `npm run build`, and build output directory to `dist`.
4. In Pages **Settings → Environment variables**, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for production (and preview if desired). Save and redeploy.
5. Open your HTTPS Pages address, sign in and add your shop's real stock. Keep the initial sample products only if useful.

## Install and try it on a phone

Open the HTTPS Pages site in your phone browser and choose **Add to Home Screen** (or **Install app**). In **Add incoming stock**, enter an item, article number, category, color, size range and quantities. Generate and print labels, or choose **Save as PDF** in the print dialog. Open **Sell**, tap **Scan a barcode**, allow camera access and scan a printed label. Change the price if needed and confirm. The fallback SKU field also accepts a USB/Bluetooth keyboard scanner.

Camera tips: use good light, hold the phone 15–25 cm from the label, print labels at least 38 mm wide, and avoid glossy laminate glare. The camera requires HTTPS. If you deny permission, allow it in the browser's site settings and retry.

## Excel and backups

On **Admin & exports**, download Stock and Sales as `.xlsx`, or Items as `.csv`; open the files in Excel. Make a monthly backup and keep a copy somewhere safe. You can also use the Supabase dashboard's table view to export any table to CSV and open it in Excel. Sales history is never overwritten by stock imports.

## Database and access notes

All business tables carry `shop_id`. The v2 migration requires an active profile and scopes shop-user reads/writes with Row Level Security; only admins can read across shops. The browser uses the public anon/publishable key. Quantity changes are restricted to atomic database RPCs, so concurrent or retried sales cannot reduce stock below zero or double-decrement a client retry.

The GitHub Actions keepalive runs weekly and calls the no-data `ping()` RPC. Add the two repository secrets above for it to work.

## v2 upgrade guide (existing live installation)

This is an additive upgrade for the already deployed beta. It does not drop tables or erase stock or sales. The SQL migration replaces the beta-wide authenticated-user policies with shop profiles, so take the backup first and follow these steps in order.

1. **Back up the current data.** Sign in as the current admin, open **Admin**, and download Stock and Sales. Save copies on your computer. The Supabase dashboard also lets you open each table and export CSV.
2. **Prepare the admin email in the migration.** Open `supabase/migrations/002_v2.sql` in a text editor. Find the marked `ADMIN PROFILE SETUP` block and replace `REPLACE_WITH_ADMIN_EMAIL` with the email of the existing Supabase Auth admin account. Keep the email inside the single quotes. Do not edit the service-role key into any file; no key is needed for this step.
3. **Run the migration.** In the Supabase Dashboard, open **SQL Editor → New query**. Paste the complete edited `002_v2.sql` file and click **Run**. Wait for the success result before moving on. The migration links your existing admin, keeps existing rows in their current shop, creates Shop 2 without sample inventory, installs the search index and RPCs, and seeds the standard categories.
4. **Deploy admin account management (recommended).** Install the free Supabase CLI from the Supabase documentation, open a terminal in the project folder, then run `supabase login`, `supabase link --project-ref YOUR_PROJECT_REF`, and `supabase functions deploy admin-manage-users`. Supabase supplies the service-role secret to the function runtime; never put that secret into Cloudflare, GitHub Actions, `.env.local`, or the source code. The detailed actions are in [`supabase/functions/admin-manage-users/README.md`](supabase/functions/admin-manage-users/README.md).
5. **If you cannot use the CLI**, create shop Auth users in **Authentication → Users → Add user**, then add the matching `profiles` row in SQL Editor with `role='shop'`, their `shop_id`, a display name, and `active=true`. See the function README for the manual fallback and password/deactivation steps. New shops can also be inserted through the Admin screen; categories are seeded automatically.
6. **Create Shop 2 logins.** Sign back into the deployed app as admin, choose a shop from the header when needed, open **Admin**, create two shop logins and assign each to Shop 2. Use temporary passwords and share them securely. Shop users go straight to the sales counter and cannot use Admin or see another shop's data.
7. **Push to GitHub.** Commit and push the updated app and migration to the connected GitHub repository. Cloudflare Pages rebuilds from `main`. Confirm its deployment succeeds before using the v2 UI. The existing `.env` values in Cloudflare stay the public Supabase Project URL and anon/publishable key.
8. **Verify the upgrade.** Sign in as admin and check the shop switcher, search, categories, Shop 2 and account creation. Sign in from a private/incognito browser as each shop user and confirm their shop name, stock, sale, and `/admin` access. Add test stock with two colors and a doubled size; verify quantities and batch labels. Print one label and scan it from a phone over HTTPS, confirm a sale and return it. Export more than 1,000 rows if you have them. The SQL safety scripts in `tests/` can be run in a transaction from the Supabase SQL Editor; review their comments first.
9. **Rollback notes.** Cloudflare can be rolled back to the previous successful deployment from the Pages deployment list. The v2 migration is forward-only and intentionally does not drop or reverse user data; do not rerun `001_init.sql` or delete the new profiles. If the new UI needs to be taken offline, revert the Git commit and redeploy the previous app. Keep the v2 migration active so its security policies remain in place. For database issues, restore the backup only after taking a fresh export and reviewing the tables affected.

### What changed in v2

- Stock, barcode, and sales searches use a tokenized Postgres RPC with trigram-indexed search text and server-side 50-row pages. The browser no longer scans whole tables for matching rows or dashboard totals.
- Stock intake supports a size-by-size pattern multiplied by per-color set counts and saves an entire intake batch atomically.
- Profiles enforce shop boundaries in RLS. Admin can choose one shop or an all-shops read-only view. Admin exports page through data in 1,000-row chunks and include a full CSV ZIP backup.
- Returns work for past sales and are idempotent. Sale retries use a UUID client reference.
- Standard categories are seeded for each shop; the previous default categories are retained but inactive.
- Weekly keepalive now calls the public `ping()` health RPC, which does not read shop data.

### Manual SQL fallback for shop profiles

If the Edge Function cannot be deployed, create the Auth user in the dashboard and run the following in the SQL Editor, replacing the email and shop UUID. Run this as the database owner, not from the browser:

```sql
insert into public.profiles(user_id, role, shop_id, active, display_name)
select id, 'shop', 'REPLACE_WITH_SHOP_UUID'::uuid, true, 'Shop staff'
from auth.users where lower(email) = lower('shop@example.invalid');
```

For an admin, use `role='admin'` and `shop_id=null`. Keep only the intended admin accounts.

## Search and scale notes

List screens call paginated database RPCs (50 results per page); summary cards are calculated in SQL. Exports read in 1,000-row windows because the Supabase REST API caps responses. Barcode printing loads nothing by default and prints up to 100 labels per print batch. Service-worker caching is limited to the app shell; sales and stock require an internet connection.

## Future roadmap (not implemented)

- Supplier and purchase tracking
- GST invoices
- Offline stock and sales
