-- ===================================================================
-- Fixed Asset Register — schema reference
--
-- This file is for DOCUMENTATION only. Do NOT run it directly.
-- To provision a new Supabase project, run `setup.sql` instead —
-- that's the one-shot, idempotent setup file.
-- ===================================================================

-- Master data tables (shared across all authenticated users)
CREATE TABLE public.categories (
  id   SERIAL PRIMARY KEY,
  name TEXT   NOT NULL
);

CREATE TABLE public.locations (
  id   SERIAL PRIMARY KEY,
  name TEXT   NOT NULL
);

CREATE TABLE public.depreciation_rates (
  id         BIGSERIAL        PRIMARY KEY,
  rate_name  TEXT             NOT NULL,
  percentage DOUBLE PRECISION NOT NULL
);

-- Assets — one row per fixed asset, owned per user (RLS-scoped)
CREATE TABLE public.assets (
  id                SERIAL                  PRIMARY KEY,
  owner_id          UUID                    NOT NULL DEFAULT auth.uid()
                                            REFERENCES auth.users(id) ON DELETE CASCADE,
  name              TEXT                    NOT NULL,
  asset_tag         TEXT,
  category_id       INTEGER                 REFERENCES public.categories(id),
  location_id       INTEGER                 REFERENCES public.locations(id),
  location_detail   TEXT,                   -- free-text e.g. "Shelf B-3"
  purchase_date     DATE                    NOT NULL,
  purchase_year     NUMERIC,
  quantity          INTEGER                 DEFAULT 1,
  unit_cost         NUMERIC(12,2)           DEFAULT 0,
  purchase_cost     NUMERIC                 NOT NULL,
  depreciation_rate DOUBLE PRECISION,
  status            TEXT                    DEFAULT 'Active',
  remarks           TEXT
);

-- CapEx additions attached to an asset (own dep rate / purchase date).
-- Cascades into "disposed" in reports when parent reaches qty = 0.
CREATE TABLE public.asset_additions (
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

-- Disposal log — full or partial. App decrements assets.quantity +
-- assets.purchase_cost on insert; flips status to 'Disposed' on full.
CREATE TABLE public.disposals (
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

-- RLS policies live in setup.sql.
