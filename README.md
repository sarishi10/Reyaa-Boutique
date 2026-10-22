# Reyaa Boutique

A Next.js / React / TypeScript fashion storefront with a Supabase database, separate customer and admin portals, Billplz payment verification, inventory reservations, courier tracking and opt-in email promotion tools.

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

For development, copy `.env.example` to `.env.local`. Put actual production values in the server host environment settings and redeploy. Never commit credentials.

## Database

Run `db/SETUP-ALL.sql` exactly once in a NEW empty Supabase project. Then run `db/VERIFY-SETUP.sql`. Individual original SQL scripts are retained for reference; do not run them again after using SETUP-ALL.

Approved administrator: `nisha.nairofficial0728@gmail.com`. Once the new database is connected, run `corepack pnpm admin:setup` locally with your private `.env.local`. It generates a random temporary password once and requires an email password reset before management access. No working password is included in the ZIP. See setup guide section 7.

## Hosting

GitHub stores the source. This project requires a Next.js server runtime; GitHub Pages cannot run it. The export contains ordinary Next.js commands and has no dependency on a Sites project ID or Cloudflare account. It is a separate portable export of the existing store; uploading it does not change the existing hosted Site.

## Current state

Checkout starts closed and the catalog starts empty. Configure real inventory, policies, shipping, Auth email, promotion delivery and Billplz before accepting customers. The merchant/account integrations have not been exercised with the client's live credentials.

## Important operational behavior

Billplz keys stay server-side. Only HMAC-verified callbacks plus provider retrieval with matching order/collection/amount can establish payment. Inventory is reserved before payment and settlement does not deduct it twice. Unpaid Billplz bills must be deleted before releasing inventory. Ambiguous bill creation errors require provider review and association through admin; never blindly recreate a payable bill.

Promotion emails require double opt-in. Drafts are previewed, explicitly queued and delivered one recipient per request while the admin page remains open. It can pause/resume. Ambiguous deliveries are held for provider-log review, preventing automatic duplicate sends. Provider acceptance is not proof of inbox delivery.

## Validation

The original store has passed desktop/mobile layout checks, typechecking, security route checks, Billplz signature/tampering checks and isolated executable PostgreSQL tests for prices, RLS, stock reservations and idempotency. This portable export also receives its own Next.js production build check. Real Supabase, merchant sandbox, SMTP and production acceptance testing remain required.
