-- ===================================================================
-- Fixed Asset Register — one-shot Supabase setup
--
-- Paste this whole file into a NEW Supabase project's SQL Editor and
-- run it once. It is idempotent (safe to re-run on an existing setup;
-- existing tables / policies are preserved or replaced cleanly).
--
-- After running this SQL:
--   1. Supabase dashboard → Authentication → Providers → Email → ENABLE
--      (uncheck "Confirm email" during testing for instant signup)
--   2. Authentication → URL Configuration
--        Site URL:       https://<your-host>/
--        Redirect URLs:  https://<your-host>/**
--      (For local testing, also add http://localhost:8000/** )
--   3. Edit docs/config.js with your Project URL and anon public key
--      (Project Settings → API)
--   4. Open the app → sign up via the login page → start using
-- ===================================================================


-- ========================== TABLES =================================

-- Master data: categories
CREATE TABLE IF NOT EXISTS public.categories (
  id   SERIAL PRIMARY KEY,
  name TEXT   NOT NULL
);

-- Master data: locations
CREATE TABLE IF NOT EXISTS public.locations (
  id   SERIAL PRIMARY KEY,
  name TEXT   NOT NULL
);

-- Master data: depreciation rates
CREATE TABLE IF NOT EXISTS public.depreciation_rates (
  id         BIGSERIAL        PRIMARY KEY,
  rate_name  TEXT             NOT NULL,
  percentage DOUBLE PRECISION NOT NULL
);

-- Assets — one row per fixed asset entry, owned per user
CREATE TABLE IF NOT EXISTS public.assets (
  id                SERIAL                  PRIMARY KEY,
  owner_id          UUID                    NOT NULL DEFAULT auth.uid()
                                            REFERENCES auth.users(id) ON DELETE CASCADE,
  name              TEXT                    NOT NULL,
  asset_tag         TEXT,
  category_id       INTEGER                 REFERENCES public.categories(id),
  location_id       INTEGER                 REFERENCES public.locations(id),
  location_detail   TEXT,
  purchase_date     DATE                    NOT NULL,
  purchase_year     NUMERIC,
  quantity          INTEGER                 DEFAULT 1,
  unit_cost         NUMERIC(12,2)           DEFAULT 0,
  purchase_cost     NUMERIC                 NOT NULL,
  depreciation_rate DOUBLE PRECISION,
  status            TEXT                    DEFAULT 'Active',
  remarks           TEXT
);

-- Asset additions — CapEx upgrades attached to a parent asset
CREATE TABLE IF NOT EXISTS public.asset_additions (
  id                BIGSERIAL     PRIMARY KEY,
  created_at        TIMESTAMPTZ   DEFAULT NOW(),
  parent_asset_id   BIGINT        NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
  description       TEXT,
  remarks           TEXT,
  quantity          INTEGER       DEFAULT 1,
  unit_cost         NUMERIC(12,2) DEFAULT 0,
  addition_cost     NUMERIC(12,2) NOT NULL,
  depreciation_rate DOUBLE PRECISION,
  purchase_date     DATE          NOT NULL,
  purchase_year     INTEGER
);

-- Disposals — log of full or partial asset disposals
CREATE TABLE IF NOT EXISTS public.disposals (
  id                  BIGSERIAL    PRIMARY KEY,
  created_at          TIMESTAMPTZ  DEFAULT NOW(),
  asset_id            BIGINT       REFERENCES public.assets(id),
  name                TEXT,
  remarks             TEXT,
  category_id         BIGINT       REFERENCES public.categories(id),
  location_id         BIGINT       REFERENCES public.locations(id),
  sales_proceed       NUMERIC      DEFAULT 0,
  quantity_disposed   INTEGER      NOT NULL DEFAULT 1,
  unit_cost           NUMERIC      DEFAULT 0,
  total_disposal_cost NUMERIC      DEFAULT 0,
  disposal_date       DATE,
  disposal_year       INTEGER,
  status              TEXT         DEFAULT 'Disposed'
);


-- ========================== ROW LEVEL SECURITY =====================

-- Enable RLS on every table
ALTER TABLE public.assets             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_additions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disposals          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.depreciation_rates ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policies so re-running this file is safe
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'assets','asset_additions','disposals',
        'categories','locations','depreciation_rates'
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                   r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

-- Per-owner policies on assets
CREATE POLICY "owner read assets"  ON public.assets
  FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY "owner write assets" ON public.assets
  FOR ALL    TO authenticated USING (owner_id = auth.uid())
                              WITH CHECK (owner_id = auth.uid());

-- Additions inherit ownership via parent_asset_id → assets.owner_id
CREATE POLICY "owner read additions" ON public.asset_additions
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM public.assets
    WHERE assets.id = asset_additions.parent_asset_id
      AND assets.owner_id = auth.uid()
  ));
CREATE POLICY "owner write additions" ON public.asset_additions
  FOR ALL    TO authenticated USING (EXISTS (
    SELECT 1 FROM public.assets
    WHERE assets.id = asset_additions.parent_asset_id
      AND assets.owner_id = auth.uid()
  )) WITH CHECK (EXISTS (
    SELECT 1 FROM public.assets
    WHERE assets.id = asset_additions.parent_asset_id
      AND assets.owner_id = auth.uid()
  ));

-- Disposals inherit ownership via asset_id → assets.owner_id
CREATE POLICY "owner read disposals" ON public.disposals
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM public.assets
    WHERE assets.id = disposals.asset_id
      AND assets.owner_id = auth.uid()
  ));
CREATE POLICY "owner write disposals" ON public.disposals
  FOR ALL    TO authenticated USING (EXISTS (
    SELECT 1 FROM public.assets
    WHERE assets.id = disposals.asset_id
      AND assets.owner_id = auth.uid()
  )) WITH CHECK (EXISTS (
    SELECT 1 FROM public.assets
    WHERE assets.id = disposals.asset_id
      AND assets.owner_id = auth.uid()
  ));

-- Shared master data: any authenticated user can read + write.
-- Tighten this later (e.g. only an admin role) if you want to lock
-- master-data editing.
CREATE POLICY "auth read categories"  ON public.categories
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth write categories" ON public.categories
  FOR ALL    TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth read locations"   ON public.locations
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth write locations"  ON public.locations
  FOR ALL    TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth read rates"       ON public.depreciation_rates
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth write rates"      ON public.depreciation_rates
  FOR ALL    TO authenticated USING (true) WITH CHECK (true);


-- ========================== OPTIONAL ===============================

-- Uncomment to seed a few common master-data rows on first install.
-- INSERT INTO public.depreciation_rates (rate_name, percentage) VALUES
--   ('10%', 10), ('15%', 15), ('20%', 20), ('33%', 33);

-- Uncomment to seed common categories.
-- INSERT INTO public.categories (name) VALUES
--   ('FURNITURE & FITTINGS'), ('OFFICE EQUIPMENT'),
--   ('PLANT & MACHINERY'), ('MOTOR VEHICLES');

-- Uncomment to seed common locations.
-- INSERT INTO public.locations (name) VALUES
--   ('HQ'), ('Warehouse'), ('Office');

-- ===================================================================
-- DONE. Configure email auth in the dashboard, update docs/config.js,
-- and open the app.
-- ===================================================================
