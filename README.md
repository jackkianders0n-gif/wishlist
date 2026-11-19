# Wishlist

Shared Christmas and flat wishlist for Jack and Jakey. It's a single `index.html` on GitHub Pages, with the gym tracker's Supabase project behind it. It works the same way as House Hunt.

## Set up (once)

1. **Database:** in Supabase, open the SQL Editor, then run `supabase/schema.sql` followed by `supabase/seed.sql`.
2. **Members:** in the SQL Editor, run the "ADD THE TWO OF YOU" snippet at the bottom of `schema.sql`. The easiest version copies the two of you from `hh_members`.
3. **Edge Function:** go to Edge Functions › `link-preview`, paste in `supabase/functions/link-preview/index.ts` and deploy.
   - It's now members only, so JWT verification can be on or off.
   - Delete the `ALLOW_ANON_TEST` secret if you ever set it.
4. **App config:** `SUPABASE_URL` and `SUPABASE_KEY` at the top of `index.html` are already set to the gym tracker project (same values as House Hunt).
5. **Hosting:** create a GitHub repo called `wishlist`, push these files, then go to Settings › Pages and deploy from the `main` branch, root folder. The app will be at `https://<you>.github.io/wishlist/`.
6. **First run:** sign in, then press **Check prices** once. That fills in the pictures for everything except Argos.
7. **+ Wishlist button:** open the menu (your initial, top right) and choose **Get the + Wishlist button**. Drag the button onto your bookmarks bar. Use it on Argos pages to add the masher and rice cooker pictures.

## How it fits together

| Piece | What it does |
|---|---|
| `wl_members` + `wl_is_member()` | Only the two of you get in. Every `wl_` table has a members-only rule. Other gym tracker accounts see nothing. |
| `wl_items` | One row per thing you want: Flat or Christmas, category, quantity, top pick, and who bought it. |
| `wl_options` | One row per product link: picture, price, previous price and when it was last checked. `auto_fetch = false` for shops that block us (Argos). |
| `link-preview` function | Reads the picture, name and price from a link. Takes `{ url }` or `{ urls: [...] }` (up to 20, used by Check prices). |
| `bookmarklet.html` | Creates the + Wishlist button. It reads the product page in your own browser, then opens the app at `#add?url=…&title=…&image=…&price=…`. |
| `sw.js` | Lets the app open offline, read-only. **Bump `VERSION` when you change `index.html`.** |

- **Sign-in:** same email and password as the gym tracker. The session is kept under `wl-auth`, so it doesn't clash with the gym tracker or House Hunt.
- **Live updates:** each of you sees the other's changes straight away, through Supabase Realtime on `wl_items` and `wl_options`.
- **Check prices:** refreshes every option with `auto_fetch = true`. A changed price keeps the old one as "was £x". A shop that starts blocking is switched to `auto_fetch = false` automatically.

## Testing the link fetcher

`tools/link-preview-test.html` calls the function with the anon key, which the function now refuses. To use it again, temporarily add the secret `ALLOW_ANON_TEST=true` (Edge Functions › Secrets), then remove it afterwards.
