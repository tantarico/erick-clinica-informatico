-- LA CLINICA DEL INFORMATICO - Esquema completo para PostgreSQL 18
-- Ejecutar UNA VEZ en una base nueva y vacia, desde Query Tool de pgAdmin.
-- Crear primero la base clinica_informatica y conectarse a ella.
-- Este archivo no crea la base, no borra datos y no contiene contrasenas.
-- Si el backend ya aplico Flyway, NO ejecutar este archivo.
-- Incluye V1 y V2. Para conectar luego el backend, consultar SCRIPT_MANUAL.md.

BEGIN;
SET LOCAL search_path TO public;

-- PostgreSQL 18. UUID identifiers and timestamps in UTC (timestamptz).
CREATE TABLE roles (
 code varchar(40) PRIMARY KEY,
 name varchar(80) NOT NULL UNIQUE
);
CREATE TABLE permissions (
 code varchar(50) PRIMARY KEY,
 description varchar(120) NOT NULL
);
CREATE TABLE role_permissions (
 role_code varchar(40) NOT NULL REFERENCES roles(code),
 permission_code varchar(50) NOT NULL REFERENCES permissions(code),
 PRIMARY KEY (role_code, permission_code)
);
CREATE TABLE users (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 first_name varchar(100) NOT NULL CHECK (btrim(first_name) <> ''),
 last_name varchar(100) NOT NULL CHECK (btrim(last_name) <> ''),
 username varchar(80) NOT NULL CHECK (btrim(username) <> '' AND username = btrim(username)),
 password_hash varchar(100) NOT NULL,
 role_code varchar(40) NOT NULL REFERENCES roles(code),
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_username_unique ON users (lower(username));
CREATE INDEX users_role_idx ON users(role_code);
CREATE TABLE clients (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 document_type varchar(10) NOT NULL CHECK (document_type IN ('DNI','RUC','CE','Otro')),
 document_number varchar(25) NOT NULL CHECK (document_number = btrim(document_number)),
 first_name varchar(150) NOT NULL CHECK (btrim(first_name) <> ''),
 last_name varchar(100) NOT NULL DEFAULT '',
 phone varchar(30) NOT NULL CHECK (phone ~ '^\+?[0-9 ().-]+$' AND length(regexp_replace(phone, '[^0-9]', '', 'g')) BETWEEN 7 AND 15),
 email varchar(254) NOT NULL DEFAULT '' CHECK (email = '' OR email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
 address varchar(300) NOT NULL DEFAULT '',
 observations text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (document_type = 'RUC' OR btrim(last_name) <> ''),
 CHECK ((document_type = 'DNI' AND document_number ~ '^[0-9]{8}$')
 OR (document_type = 'RUC' AND document_number ~ '^[0-9]{11}$')
 OR (document_type = 'CE' AND document_number ~ '^[a-zA-Z0-9-]{5,20}$')
 OR (document_type = 'Otro' AND length(document_number) BETWEEN 1 AND 25))
);
CREATE UNIQUE INDEX clients_document_unique ON clients(lower(document_number));
CREATE TABLE equipment (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 client_id uuid NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
 type varchar(30) NOT NULL CHECK (type IN ('Laptop','PC','Impresora','Monitor','Tablet','Otro')),
 brand varchar(100) NOT NULL CHECK (btrim(brand) <> ''),
 model varchar(100) NOT NULL CHECK (btrim(model) <> ''),
 serial_number varchar(100) NOT NULL DEFAULT '' CHECK (serial_number = btrim(serial_number)),
 characteristics text NOT NULL DEFAULT '',
 accessories text NOT NULL DEFAULT '',
 observations text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (type = 'Otro' OR btrim(serial_number) <> '')
);
CREATE UNIQUE INDEX equipment_serial_unique ON equipment(lower(serial_number)) WHERE serial_number <> '';
CREATE INDEX equipment_client_idx ON equipment(client_id);
CREATE TABLE order_statuses (
 code varchar(30) PRIMARY KEY,
 name varchar(80) NOT NULL UNIQUE,
 terminal boolean NOT NULL DEFAULT false
);
CREATE TABLE order_status_transitions (
 from_status varchar(30) NOT NULL REFERENCES order_statuses(code),
 to_status varchar(30) NOT NULL REFERENCES order_statuses(code),
 PRIMARY KEY(from_status,to_status), CHECK(from_status <> to_status)
);
CREATE SEQUENCE service_order_number_seq;
CREATE TABLE service_orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 number bigint NOT NULL UNIQUE DEFAULT nextval('service_order_number_seq'),
 equipment_id uuid NOT NULL REFERENCES equipment(id) ON DELETE RESTRICT,
 client_id uuid NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
 received_by uuid NOT NULL REFERENCES users(id),
 reported_problem text NOT NULL CHECK (btrim(reported_problem) <> ''),
 intake_condition text NOT NULL DEFAULT '',
 intake_accessories text NOT NULL DEFAULT '',
 status_code varchar(30) NOT NULL DEFAULT 'PENDIENTE' REFERENCES order_statuses(code),
 priority varchar(10) NOT NULL DEFAULT 'NORMAL' CHECK(priority IN ('BAJA','NORMAL','ALTA','URGENTE')),
 estimated_delivery timestamptz,
 closed_at timestamptz,
 closure_summary text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (estimated_delivery IS NULL OR estimated_delivery >= created_at),
 CHECK ((status_code IN ('CERRADA','CANCELADA') AND closed_at IS NOT NULL AND closure_summary IS NOT NULL AND btrim(closure_summary) <> '')
 OR (status_code NOT IN ('CERRADA','CANCELADA') AND closed_at IS NULL))
);
CREATE INDEX service_orders_equipment_idx ON service_orders(equipment_id);
CREATE INDEX service_orders_client_idx ON service_orders(client_id);
CREATE INDEX service_orders_status_date_idx ON service_orders(status_code,created_at);
CREATE INDEX service_orders_receiver_idx ON service_orders(received_by);
CREATE TABLE technician_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE RESTRICT,
 technician_id uuid NOT NULL REFERENCES users(id),
 assigned_by uuid NOT NULL REFERENCES users(id),
 assigned_at timestamptz NOT NULL DEFAULT now(),
 ended_at timestamptz,
 notes text NOT NULL DEFAULT '',
 CHECK (ended_at IS NULL OR ended_at >= assigned_at)
);
CREATE UNIQUE INDEX assignments_one_current ON technician_assignments(order_id) WHERE ended_at IS NULL;
CREATE INDEX assignments_technician_idx ON technician_assignments(technician_id,assigned_at);
CREATE INDEX assignments_assigner_idx ON technician_assignments(assigned_by);
CREATE TABLE order_status_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE RESTRICT,
 from_status varchar(30) REFERENCES order_statuses(code),
 to_status varchar(30) NOT NULL REFERENCES order_statuses(code),
 changed_by uuid NOT NULL REFERENCES users(id),
 reason text NOT NULL DEFAULT '',
 changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX order_history_order_idx ON order_status_history(order_id,changed_at);
CREATE INDEX order_history_user_idx ON order_status_history(changed_by);
CREATE TABLE technical_attentions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE RESTRICT,
 technician_id uuid NOT NULL REFERENCES users(id),
 diagnosis text NOT NULL CHECK (btrim(diagnosis) <> ''),
 actions_performed text NOT NULL CHECK (btrim(actions_performed) <> ''),
 recommendations text NOT NULL DEFAULT '',
 started_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (finished_at IS NULL OR finished_at >= started_at)
);
CREATE INDEX attentions_order_idx ON technical_attentions(order_id,created_at);
CREATE INDEX attentions_technician_idx ON technical_attentions(technician_id);
CREATE TABLE ai_prediagnoses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE RESTRICT,
 requested_by uuid NOT NULL REFERENCES users(id),
 provider varchar(40) NOT NULL DEFAULT 'gemini',
 model varchar(120) NOT NULL,
 input_data jsonb NOT NULL,
 generated_diagnosis text,
 status varchar(20) NOT NULL DEFAULT 'PENDIENTE' CHECK(status IN ('PENDIENTE','GENERADO','ERROR')),
 error_message text,
 requested_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 CHECK (jsonb_typeof(input_data) = 'object'),
 CHECK ((status = 'PENDIENTE' AND completed_at IS NULL)
 OR (status = 'GENERADO' AND completed_at IS NOT NULL AND generated_diagnosis IS NOT NULL AND btrim(generated_diagnosis) <> '')
 OR (status = 'ERROR' AND completed_at IS NOT NULL AND error_message IS NOT NULL AND btrim(error_message) <> ''))
);
CREATE INDEX prediagnoses_order_idx ON ai_prediagnoses(order_id,requested_at);
CREATE INDEX prediagnoses_requester_idx ON ai_prediagnoses(requested_by);
CREATE TABLE ai_validations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 prediagnosis_id uuid NOT NULL UNIQUE REFERENCES ai_prediagnoses(id) ON DELETE RESTRICT,
 technician_id uuid NOT NULL REFERENCES users(id),
 decision varchar(20) NOT NULL CHECK(decision IN ('ACEPTADO','MODIFICADO','RECHAZADO')),
 final_diagnosis text NOT NULL CHECK(btrim(final_diagnosis) <> ''),
 observations text NOT NULL DEFAULT '',
 validated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX validations_technician_idx ON ai_validations(technician_id);
CREATE TABLE system_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 actor_id uuid REFERENCES users(id),
 event_type varchar(80) NOT NULL,
 entity_type varchar(80) NOT NULL,
 entity_id uuid,
 details jsonb NOT NULL DEFAULT '{}'::jsonb,
 occurred_at timestamptz NOT NULL DEFAULT now(),
 CHECK (jsonb_typeof(details) = 'object')
);
CREATE INDEX events_actor_idx ON system_events(actor_id);
CREATE INDEX events_date_idx ON system_events(occurred_at);
CREATE INDEX events_entity_idx ON system_events(entity_type,entity_id);
CREATE TABLE backup_runs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 requested_by uuid REFERENCES users(id),
 status varchar(20) NOT NULL DEFAULT 'EN_PROCESO' CHECK(status IN ('EN_PROCESO','COMPLETADO','ERROR')),
 file_path text,
 checksum_sha256 varchar(64),
 started_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 error_message text,
 CHECK (finished_at IS NULL OR finished_at >= started_at),
 CHECK ((status = 'EN_PROCESO' AND finished_at IS NULL)
 OR (status = 'COMPLETADO' AND finished_at IS NOT NULL AND file_path IS NOT NULL AND checksum_sha256 IS NOT NULL AND checksum_sha256 ~ '^[a-f0-9]{64}$')
 OR (status = 'ERROR' AND finished_at IS NOT NULL AND error_message IS NOT NULL))
);
CREATE INDEX backups_requester_idx ON backup_runs(requested_by);
CREATE TABLE monitoring_checks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 component varchar(80) NOT NULL,
 status varchar(10) NOT NULL CHECK(status IN ('OK','ALERTA','ERROR')),
 response_time_ms integer CHECK(response_time_ms >= 0),
 message text NOT NULL DEFAULT '',
 checked_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX monitoring_component_date_idx ON monitoring_checks(component,checked_at);
CREATE TABLE system_settings (
 key varchar(80) PRIMARY KEY,
 value jsonb NOT NULL,
 updated_by uuid REFERENCES users(id),
 updated_at timestamptz NOT NULL DEFAULT now()
);
-- Orders retain the client at reception even when equipment is subsequently reassigned.
CREATE FUNCTION validate_order_owner() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM equipment WHERE id = NEW.equipment_id AND client_id = NEW.client_id) THEN
  RAISE EXCEPTION 'El equipo no pertenece al cliente de la orden' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER service_order_owner BEFORE INSERT OR UPDATE OF equipment_id, client_id ON service_orders
 FOR EACH ROW EXECUTE FUNCTION validate_order_owner();
CREATE FUNCTION validate_technician() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.technician_id AND role_code = 'TÉCNICO' AND active) THEN
  RAISE EXCEPTION 'Se requiere un técnico activo' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER assignment_technician BEFORE INSERT OR UPDATE OF technician_id ON technician_assignments
 FOR EACH ROW EXECUTE FUNCTION validate_technician();
CREATE TRIGGER attention_technician BEFORE INSERT OR UPDATE OF technician_id ON technical_attentions
 FOR EACH ROW EXECUTE FUNCTION validate_technician();
CREATE TRIGGER validation_technician BEFORE INSERT OR UPDATE OF technician_id ON ai_validations
 FOR EACH ROW EXECUTE FUNCTION validate_technician();
CREATE FUNCTION validate_status_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.status_code <> OLD.status_code AND NOT EXISTS (
  SELECT 1 FROM order_status_transitions WHERE from_status = OLD.status_code AND to_status = NEW.status_code
 ) THEN
  RAISE EXCEPTION 'Transición de estado no permitida' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER order_transition BEFORE UPDATE OF status_code ON service_orders
 FOR EACH ROW EXECUTE FUNCTION validate_status_transition();
CREATE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['users','clients','equipment','service_orders','technical_attentions','system_settings'] LOOP
  EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION touch_updated_at()', t || '_updated_at', t);
 END LOOP;
END $$;
CREATE VIEW service_indicators AS
 SELECT status_code, count(*) AS total,
 avg(extract(epoch FROM (closed_at-created_at))/3600) FILTER (WHERE closed_at IS NOT NULL) AS average_duration_hours
 FROM service_orders GROUP BY status_code;


INSERT INTO roles(code,name) VALUES
 ('ADMINISTRADOR','Administrador'),('PERSONAL DE ATENCIÓN','Personal de Atención'),
 ('TÉCNICO','Técnico'),('GERENTE','Gerente')
 ON CONFLICT (code) DO NOTHING;
INSERT INTO permissions(code,description) VALUES
 ('dashboard','Ver dashboard'),('clients','Gestionar clientes'),('equipment','Gestionar equipos'),
 ('orders','Gestionar órdenes'),('assign-technicians','Asignar técnicos'),
 ('assigned-orders','Consultar órdenes asignadas'),('attend-orders','Atender órdenes'),
 ('ai-prediagnosis','Usar prediagnóstico IA'),('service-tracking','Consultar seguimiento'),
 ('service-indicators','Consultar indicadores'),('users','Gestionar usuarios'),('settings','Configuración'),
 ('manage-deliveries','Gestionar entregas'),('manage-quotations','Gestionar cotizaciones'),
 ('reports-export','Exportar reportes')
 ON CONFLICT (code) DO UPDATE SET description=EXCLUDED.description;
INSERT INTO role_permissions SELECT 'ADMINISTRADOR',code FROM permissions;
INSERT INTO role_permissions(role_code,permission_code) VALUES
 ('PERSONAL DE ATENCIÓN','dashboard'),('PERSONAL DE ATENCIÓN','clients'),
 ('PERSONAL DE ATENCIÓN','equipment'),('PERSONAL DE ATENCIÓN','orders'),
 ('PERSONAL DE ATENCIÓN','assign-technicians'),('PERSONAL DE ATENCIÓN','service-tracking'),
 ('TÉCNICO','dashboard'),('TÉCNICO','assigned-orders'),('TÉCNICO','attend-orders'),
 ('TÉCNICO','ai-prediagnosis'),('TÉCNICO','service-tracking');
INSERT INTO role_permissions(role_code,permission_code) VALUES
 ('GERENTE','dashboard'),('GERENTE','orders'),('GERENTE','service-tracking'),
 ('GERENTE','service-indicators'),('GERENTE','reports-export'),
 ('GERENTE','manage-deliveries'),('GERENTE','manage-quotations'),
 ('PERSONAL DE ATENCIÓN','manage-deliveries'),('PERSONAL DE ATENCIÓN','manage-quotations'),
 ('ADMINISTRADOR','manage-deliveries'),('ADMINISTRADOR','manage-quotations'),
 ('ADMINISTRADOR','reports-export')
 ON CONFLICT DO NOTHING;
INSERT INTO order_statuses(code,name,terminal) VALUES
 ('PENDIENTE','Pendiente',false),('ASIGNADA','Asignada',false),('EN_ATENCION','En atención',false),
 ('FINALIZADA','Finalizada',false),('CERRADA','Cerrada',true),('CANCELADA','Cancelada',true);
INSERT INTO order_status_transitions VALUES
 ('PENDIENTE','ASIGNADA'),('PENDIENTE','CANCELADA'),('ASIGNADA','EN_ATENCION'),('ASIGNADA','CANCELADA'),
 ('EN_ATENCION','FINALIZADA'),('EN_ATENCION','CANCELADA'),('FINALIZADA','EN_ATENCION'),('FINALIZADA','CERRADA');

CREATE TABLE IF NOT EXISTS quotation (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE RESTRICT,
 description text NOT NULL CHECK (btrim(description) <> ''),
 status varchar(20) NOT NULL DEFAULT 'PENDIENTE'
  CHECK (status IN ('PENDIENTE','AUTORIZADA','RECHAZADA')),
 total numeric(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
 created_by uuid NOT NULL REFERENCES users(id),
 decided_by uuid REFERENCES users(id),
 decided_at timestamptz,
 decision_observations text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS quotation_item (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 quotation_id uuid NOT NULL REFERENCES quotation(id) ON DELETE CASCADE,
 item_description text NOT NULL CHECK (btrim(item_description) <> ''),
 item_type varchar(20) NOT NULL CHECK (item_type IN ('SERVICIO','REPUESTO')),
 quantity numeric(12,3) NOT NULL CHECK (quantity > 0),
 unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
 subtotal numeric(12,2) NOT NULL CHECK (subtotal >= 0)
);
CREATE TABLE IF NOT EXISTS equipment_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL UNIQUE REFERENCES service_orders(id) ON DELETE RESTRICT,
 delivered_at timestamptz NOT NULL,
 responsible_id uuid NOT NULL REFERENCES users(id),
 client_confirmed boolean NOT NULL DEFAULT false,
 recipient_name varchar(200) NOT NULL CHECK (btrim(recipient_name) <> ''),
 recipient_document varchar(50) NOT NULL DEFAULT '',
 reception_signature text NOT NULL DEFAULT '',
 reception_constancy text NOT NULL DEFAULT '',
 observations text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now()
);

COMMIT;
