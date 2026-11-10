-- ServiceNow tickets on incidents (REV-70), after incident count panels (0068, REV-69). An incident can
-- carry one ServiceNow ticket: the link Keep opens, an optional ticket number and who
-- linked it when. Keep never calls ServiceNow, so these are plain nullable columns written
-- by the incident ticket command under the incident revision. The link is at most 2,048
-- characters; a number is upper-case letters then digits and requires a link; the time and
-- principal are present exactly when a link is. Existing incidents have no ticket.
ALTER TABLE incidents
 ADD COLUMN ticket_url text,
 ADD COLUMN ticket_number text,
 ADD COLUMN ticket_linked_at timestamptz,
 ADD COLUMN ticket_linked_by uuid REFERENCES principals(id),
 ADD CONSTRAINT incidents_ticket_url_length CHECK (ticket_url IS NULL OR length(ticket_url) BETWEEN 1 AND 2048),
 ADD CONSTRAINT incidents_ticket_number_format CHECK (ticket_number IS NULL OR (ticket_url IS NOT NULL AND ticket_number ~ '^[A-Z]{2,8}[0-9]{4,12}$')),
 ADD CONSTRAINT incidents_ticket_link_recorded CHECK ((ticket_url IS NULL) = (ticket_linked_at IS NULL) AND (ticket_url IS NULL) = (ticket_linked_by IS NULL));
