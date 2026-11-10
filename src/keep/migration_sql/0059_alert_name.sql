-- Optional v2 alert name (REV-54). The column holds only a sender-supplied name,
-- which is part of the alert's v2 identity and never changes. NULL means none:
-- readers name an unnamed v2 alert by its key_field, and v1 alerts have no name.
-- Adding a nullable column without a default rewrites no rows, and older code that
-- names its columns from the alert record leaves it NULL, which reads correctly.
ALTER TABLE alerts ADD COLUMN name text;
