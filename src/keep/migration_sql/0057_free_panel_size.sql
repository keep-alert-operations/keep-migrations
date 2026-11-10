-- Panel width is 3 through 12 columns and height 2 or more units (REV-50).
-- The x+w <= 12 and y+h <= 100 grid bound is unchanged; existing rows satisfy
-- the wider checks, so older API code that writes only the old sizes still works.
ALTER TABLE dashboard_panels
  DROP CONSTRAINT dashboard_panels_w_check,
  DROP CONSTRAINT dashboard_panels_h_check,
  ADD CONSTRAINT dashboard_panels_w_check CHECK (w BETWEEN 3 AND 12),
  ADD CONSTRAINT dashboard_panels_h_check CHECK (h >= 2);
