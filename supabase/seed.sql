-- Wishlist — your current list (from Christmas_List.docx), run ONCE after schema.sql.
-- Run it in the SQL Editor (runs as the database owner, so row-level security doesn't block it).

with items(list, category, title, qty, sort) as (values
  ('xmas', 'Christmas', 'Electric masher',               1,  10),
  ('xmas', 'Christmas', 'Ninja food processor',          1,  20),

  ('flat', 'Kitchen',   'Bin',                           1, 100),
  ('flat', 'Kitchen',   'Baking tray',                   2, 110),
  ('flat', 'Kitchen',   'Plates, bowls etc',             1, 120),
  ('flat', 'Kitchen',   'Cutlery',                       1, 130),
  ('flat', 'Kitchen',   'Cooking spoons, spatula',       1, 140),
  ('flat', 'Kitchen',   'Saucepans',                     1, 150),
  ('flat', 'Kitchen',   'Air fryer',                     1, 160),
  ('flat', 'Kitchen',   'Kettle',                        1, 170),
  ('flat', 'Kitchen',   'Toaster',                       1, 180),
  ('flat', 'Kitchen',   'Kitchen scissors',              1, 190),
  ('flat', 'Kitchen',   'Vegetable peeler',              1, 200),
  ('flat', 'Kitchen',   'Tupperware',                    1, 210),
  ('flat', 'Kitchen',   'Table',                         1, 220),
  ('flat', 'Kitchen',   'Chairs',                        1, 230),
  ('flat', 'Kitchen',   'Microwave',                     1, 240),
  ('flat', 'Kitchen',   'Rice cooker',                   1, 250),
  ('flat', 'Kitchen',   'Oven gloves',                   1, 260),
  ('flat', 'Kitchen',   'Chopping board',                1, 270),
  ('flat', 'Kitchen',   'Can opener',                    1, 280),
  ('flat', 'Kitchen',   'Tea towels',                    1, 290),
  ('flat', 'Kitchen',   'Colander',                      1, 300),
  ('flat', 'Kitchen',   'Salt and pepper grinder',       1, 310),

  ('flat', 'Bathroom',  'Toilet brush',                  1, 400),
  ('flat', 'Bathroom',  'Towels – small & bath sheet',   1, 410),

  ('flat', 'Lounge',    'Sofa',                          1, 500),
  ('flat', 'Lounge',    'Cushions',                      1, 510),

  ('flat', 'Bedroom',   'Bedside table',                 1, 600),
  ('flat', 'Bedroom',   'Desk',                          1, 610),
  ('flat', 'Bedroom',   'Bed',                           1, 620),
  ('flat', 'Bedroom',   'Sofa bed',                      1, 630),
  ('flat', 'Bedroom',   'Desk chair',                    1, 640),

  ('flat', 'Cleaning',  'Mop',                           1, 700),
  ('flat', 'Cleaning',  'Hoover',                        1, 710)
)
insert into public.wl_items (list, category, title, qty, sort, created_by)
select list, category, title, qty, sort, null from items;

with opts(item_title, url, store, title, image, price, auto_fetch, checked) as (values
  ('Electric masher', 'https://www.argos.co.uk/product/9214419', 'argos.co.uk',
    'Electric masher', null, null::numeric, false, null::timestamptz),
  ('Ninja food processor', 'https://www.amazon.co.uk/dp/B0GLQX3L6F', 'amazon.co.uk',
    'Ninja PrecisionPro 2.1L Food Processor, 4 Auto Presets, Black BZ651UK', null, 84.99, true, '2026-11-19 10:31+00'),
  ('Baking tray', 'https://www.procook.co.uk/product/non-stick-baking-tray-granite-41-x-31cm', 'procook.co.uk',
    'Non-Stick Granite Effect Baking Tray 41 x 31cm', null, 14.00, true, '2026-11-19 10:31+00'),
  ('Saucepans', 'https://www.sharkninja.co.uk/ninja-extended-life-ceramic-3-piece-saucepan-set-cw93003eui/CW93003EUI.html', 'sharkninja.co.uk',
    'Ninja Extended Life Ceramic 3-Piece Saucepan Set CW93003EUI', null, 129.99, true, '2026-11-19 10:31+00'),
  ('Kettle', 'https://www.amazon.co.uk/dp/B09434RPTF', 'amazon.co.uk',
    'Breville Bold Vanilla Cream Electric Kettle | 1.7L | 3kW Fast Boil | Cream & Silver Chrome [VKT223]', null, 26.00, true, '2026-11-19 10:31+00'),
  ('Toaster', 'https://www.amazon.co.uk/dp/B0942M5B2Y', 'amazon.co.uk',
    'Breville Bold 2 Slice Toaster with High-Lift & Wide Slots | Cream & Silver Chrome [VTR003]', null, 26.00, true, '2026-11-19 10:31+00'),
  ('Kitchen scissors', 'https://www.amazon.co.uk/dp/B000KILLXM', 'amazon.co.uk',
    'OXO Good Grips Kitchen & Herb Scissors', null, 13.79, true, '2026-11-19 10:31+00'),
  ('Vegetable peeler', 'https://www.amazon.co.uk/dp/B00004OCIU', 'amazon.co.uk',
    'OXO Good Grips Y Peeler', null, 6.40, true, '2026-11-19 10:31+00'),
  ('Rice cooker', 'https://www.argos.co.uk/product/9345168', 'argos.co.uk',
    'Russell Hobbs 2L Rice Cooker – White', null, 28.00, false, '2026-11-19 10:36+00')
)
insert into public.wl_options (item_id, url, store, title, image, price, auto_fetch, price_checked_at, created_by)
select i.id, o.url, o.store, o.title, o.image, o.price, o.auto_fetch, o.checked, null
from opts o
join public.wl_items i on i.title = o.item_title;

-- Pictures aren't stored here: open the app and press "Check prices" once to fill them in
-- for everything except Argos (use the + Wishlist button on those two Argos pages).
