# Reyaa Boutique

A React / TypeScript storefront using Next.js APIs through Vinext on Cloudflare Workers, with a Supabase database, separate customer and admin portals, Billplz payment verification, inventory reservations, courier tracking and opt-in email promotion tools.

**Start with `SETUP-SUPABASE.md`.** It explains GitHub upload, database setup, server hosting, keys, accounts, email and launch checks.

## Commands

Node.js 22.13+ and the pnpm version declared in package.json are required.

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm dev
corepack pnpm typecheck
corepack pnpm build
corepack pnpm start
```

For local Worker development, copy `.env.example` to ignored `.dev.vars`. Put actual production values in the server host environment settings and redeploy. Never commit credentials.

## Database

Run `db/SETUP-ALL.sql` exactly once in a NEW empty Supabase project. Then run `db/VERIFY-SETUP.sql`. Individual original SQL scripts are retained for reference; do not run them again after using SETUP-ALL.

Approved administrator: `nisha.nairofficial0728@gmail.com`. Create the Auth user privately in Supabase Dashboard, then run `db/ADMIN-ROLE-LATER.sql`. Verified email recovery is required before management access. See setup guide section 7.

## Hosting

Upload these source files to the existing GitHub repository. Connect Cloudflare Workers with build `pnpm run build` and deploy `npx wrangler deploy`. Worker name: `reyaa-boutique`. No local Node installation required. Follow `SETUP-SUPABASE.md` sections 6–7 for browser-only hosting and admin creation.

Runtime credentials belong in Cloudflare Variables and Secrets, never in GitHub. The first deployment remains closed until configured. GitHub Pages cannot run the server APIs. No Sites project or Cloudflare account ID is embedded.

## Current state

Checkout starts closed and the catalog starts empty. Configure real inventory, policies, shipping, Auth email, promotion delivery and Billplz before accepting customers. The merchant/account integrations have not been exercised with the client's live credentials.

## Important operational behavior

Billplz keys stay server-side. Only HMAC-verified callbacks plus provider retrieval with matching order/collection/amount can establish payment. Inventory is reserved before payment and settlement does not deduct it twice. Unpaid Billplz bills must be deleted before releasing inventory. Ambiguous bill creation errors require provider review and association through admin; never blindly recreate a payable bill.

Promotion emails require double opt-in. Drafts are previewed, explicitly queued and delivered one recipient per request while the admin page remains open. It can pause/resume. Ambiguous deliveries are held for provider-log review, preventing automatic duplicate sends. Provider acceptance is not proof of inbox delivery.

## Validation

The original store has passed desktop/mobile layout checks, typechecking, security route checks, Billplz signature/tampering checks and isolated executable PostgreSQL tests for prices, RLS, stock reservations and idempotency. This portable export also receives its own Cloudflare production build and Wrangler packaging checks. Real Supabase, merchant sandbox, SMTP and production acceptance testing remain required.

