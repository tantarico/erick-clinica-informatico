-- ============================================================
-- SCRIPT COMPLETO DE COTIZACIONES Y ENTREGAS
-- Compatible con "base de datos.sql" (PostgreSQL 18)
-- Base: clinica_informatica
-- Es seguro ejecutar varias veces: no elimina datos ni tablas.
-- ============================================================

SET search_path TO public;
BEGIN;

-- ----------------------------------------------------------------
-- 1. CATÁLOGOS Y PERMISOS NUEVOS
-- ----------------------------------------------------------------

INSERT INTO public.roles(code, name)
VALUES ('GERENTE', 'Gerente')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name;

INSERT INTO public.permissions(code, description)
VALUES
    ('manage-quotations', 'Gestionar cotizaciones'),
    ('manage-deliveries', 'Gestionar entregas'),
    ('reports-export', 'Exportar reportes'),
    ('service-indicators', 'Consultar indicadores')
ON CONFLICT (code) DO UPDATE
SET description = EXCLUDED.description;

INSERT INTO public.role_permissions(role_code, permission_code)
VALUES
    ('GERENTE', 'dashboard'),
    ('GERENTE', 'orders'),
    ('GERENTE', 'service-tracking'),
    ('GERENTE', 'service-indicators'),
    ('GERENTE', 'reports-export'),
    ('GERENTE', 'manage-deliveries'),
    ('GERENTE', 'manage-quotations'),
    ('ADMINISTRADOR', 'manage-deliveries'),
    ('ADMINISTRADOR', 'manage-quotations'),
    ('ADMINISTRADOR', 'reports-export'),
    ('PERSONAL DE ATENCIÓN', 'manage-deliveries'),
    ('PERSONAL DE ATENCIÓN', 'manage-quotations')
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------
-- 2. TABLA PRINCIPAL DE COTIZACIONES
-- Nombre real usado por el dump: public.quotation
-- ----------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.quotation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    description text NOT NULL,
    status character varying(20) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    total numeric(12,2) DEFAULT 0 NOT NULL,
    created_by uuid NOT NULL,
    decided_by uuid,
    decided_at timestamp with time zone,
    decision_observations text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.quotation
    ALTER COLUMN decision_observations SET DEFAULT ''::text,
    ALTER COLUMN decision_observations SET NOT NULL,
    ALTER COLUMN created_at SET DEFAULT now(),
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN updated_at SET DEFAULT now(),
    ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_description_check'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_description_check
            CHECK (btrim(description) <> '');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_status_check'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_status_check
            CHECK (status IN ('PENDIENTE', 'AUTORIZADA', 'RECHAZADA'));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_total_check'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_total_check
            CHECK (total >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_check'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_check
            CHECK (
                (status = 'PENDIENTE'
                    AND decided_by IS NULL
                    AND decided_at IS NULL)
                OR
                (status IN ('AUTORIZADA', 'RECHAZADA')
                    AND decided_by IS NOT NULL
                    AND decided_at IS NOT NULL)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_pkey'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_pkey PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_order_id_fkey'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_order_id_fkey
            FOREIGN KEY (order_id)
            REFERENCES public.service_orders(id)
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_created_by_fkey'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_created_by_fkey
            FOREIGN KEY (created_by) REFERENCES public.users(id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'quotation_decided_by_fkey'
          AND conrelid = 'public.quotation'::regclass
    ) THEN
        ALTER TABLE public.quotation
            ADD CONSTRAINT quotation_decided_by_fkey
            FOREIGN KEY (decided_by) REFERENCES public.users(id);
    END IF;
END $$;

-- ----------------------------------------------------------------
-- 3. DETALLE DE COTIZACIÓN: SERVICIOS Y REPUESTOS
-- ----------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.quotation_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    quotation_id uuid NOT NULL,
    item_description text NOT NULL,
    item_type character varying(20) NOT NULL,
    quantity numeric(12,3) NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    subtotal numeric(12,2) NOT NULL
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'quotation_item_pkey'
          AND conrelid = 'public.quotation_item'::regclass
    ) THEN
        ALTER TABLE public.quotation_item
            ADD CONSTRAINT quotation_item_pkey PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'quotation_item_quotation_id_fkey'
          AND conrelid = 'public.quotation_item'::regclass
    ) THEN
        ALTER TABLE public.quotation_item
            ADD CONSTRAINT quotation_item_quotation_id_fkey
            FOREIGN KEY (quotation_id)
            REFERENCES public.quotation(id)
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'quotation_item_item_description_check'
          AND conrelid = 'public.quotation_item'::regclass
    ) THEN
        ALTER TABLE public.quotation_item
            ADD CONSTRAINT quotation_item_item_description_check
            CHECK (btrim(item_description) <> '');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'quotation_item_item_type_check'
          AND conrelid = 'public.quotation_item'::regclass
    ) THEN
        ALTER TABLE public.quotation_item
            ADD CONSTRAINT quotation_item_item_type_check
            CHECK (item_type IN ('SERVICIO', 'REPUESTO'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'quotation_item_quantity_check'
          AND conrelid = 'public.quotation_item'::regclass
    ) THEN
        ALTER TABLE public.quotation_item
            ADD CONSTRAINT quotation_item_quantity_check
            CHECK (quantity > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'quotation_item_unit_price_check'
          AND conrelid = 'public.quotation_item'::regclass
    ) THEN
        ALTER TABLE public.quotation_item
            ADD CONSTRAINT quotation_item_unit_price_check
            CHECK (unit_price >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'quotation_item_subtotal_check'
          AND conrelid = 'public.quotation_item'::regclass
    ) THEN
        ALTER TABLE public.quotation_item
            ADD CONSTRAINT quotation_item_subtotal_check
            CHECK (subtotal >= 0);
    END IF;
END $$;

-- ----------------------------------------------------------------
-- 4. ÍNDICES EXACTOS DEL DUMP
-- ----------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS quotations_one_pending_per_order
    ON public.quotation(order_id)
    WHERE status = 'PENDIENTE';

CREATE INDEX IF NOT EXISTS quotations_order_idx
    ON public.quotation(order_id, created_at);

CREATE INDEX IF NOT EXISTS quotation_items_quotation_idx
    ON public.quotation_item(quotation_id);

-- ----------------------------------------------------------------
-- 5. TRIGGERS PARA SUBTOTAL Y COSTO TOTAL
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.quotation_calculate_item_subtotal()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.subtotal := round(NEW.quantity * NEW.unit_price, 2);
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.quotation_recalculate_total()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_quotation uuid;
BEGIN
    target_quotation := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.quotation_id
        ELSE NEW.quotation_id
    END;

    UPDATE public.quotation
    SET total = (
            SELECT coalesce(round(sum(subtotal), 2), 0)
            FROM public.quotation_item
            WHERE quotation_id = target_quotation
        ),
        updated_at = now()
    WHERE id = target_quotation;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_quotation_calculate_subtotal
    ON public.quotation_item;
CREATE TRIGGER trg_quotation_calculate_subtotal
BEFORE INSERT OR UPDATE OF quantity, unit_price
ON public.quotation_item
FOR EACH ROW
EXECUTE FUNCTION public.quotation_calculate_item_subtotal();

DROP TRIGGER IF EXISTS trg_quotation_recalculate_total
    ON public.quotation_item;
CREATE TRIGGER trg_quotation_recalculate_total
AFTER INSERT OR UPDATE OR DELETE
ON public.quotation_item
FOR EACH ROW
EXECUTE FUNCTION public.quotation_recalculate_total();

-- Actualiza las cotizaciones existentes sin reemplazar ni eliminar registros.
UPDATE public.quotation_item
SET subtotal = round(quantity * unit_price, 2);

UPDATE public.quotation q
SET total = coalesce((
        SELECT round(sum(i.subtotal), 2)
        FROM public.quotation_item i
        WHERE i.quotation_id = q.id
    ), 0),
    updated_at = now();

-- Actualiza la fecha de modificación al editar una cotización.
DROP TRIGGER IF EXISTS quotation_updated_at
    ON public.quotation;
CREATE TRIGGER quotation_updated_at
BEFORE UPDATE ON public.quotation
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

-- ----------------------------------------------------------------
-- 6. ENTREGA FORMAL YA EXISTENTE EN EL DUMP
-- public.equipment_deliveries
-- ----------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.equipment_deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    delivered_at timestamp with time zone NOT NULL,
    responsible_id uuid NOT NULL,
    client_confirmed boolean DEFAULT false NOT NULL,
    recipient_name character varying(200) NOT NULL,
    recipient_document character varying(50) DEFAULT ''::character varying NOT NULL,
    reception_signature text DEFAULT ''::text NOT NULL,
    reception_constancy text DEFAULT ''::text NOT NULL,
    observations text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'equipment_deliveries_pkey'
          AND conrelid = 'public.equipment_deliveries'::regclass
    ) THEN
        ALTER TABLE public.equipment_deliveries
            ADD CONSTRAINT equipment_deliveries_pkey PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'equipment_deliveries_order_id_key'
          AND conrelid = 'public.equipment_deliveries'::regclass
    ) THEN
        ALTER TABLE public.equipment_deliveries
            ADD CONSTRAINT equipment_deliveries_order_id_key UNIQUE (order_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'equipment_deliveries_order_id_fkey'
          AND conrelid = 'public.equipment_deliveries'::regclass
    ) THEN
        ALTER TABLE public.equipment_deliveries
            ADD CONSTRAINT equipment_deliveries_order_id_fkey
            FOREIGN KEY (order_id)
            REFERENCES public.service_orders(id)
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'equipment_deliveries_responsible_id_fkey'
          AND conrelid = 'public.equipment_deliveries'::regclass
    ) THEN
        ALTER TABLE public.equipment_deliveries
            ADD CONSTRAINT equipment_deliveries_responsible_id_fkey
            FOREIGN KEY (responsible_id) REFERENCES public.users(id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'equipment_deliveries_recipient_name_check'
          AND conrelid = 'public.equipment_deliveries'::regclass
    ) THEN
        ALTER TABLE public.equipment_deliveries
            ADD CONSTRAINT equipment_deliveries_recipient_name_check
            CHECK (btrim(recipient_name) <> '');
    END IF;
END $$;

-- ----------------------------------------------------------------
-- 7. VISTA COMPLETA PARA CONSULTAR COTIZACIONES
-- ----------------------------------------------------------------

CREATE OR REPLACE VIEW public.quotation_detail_view AS
SELECT
    q.id AS quotation_id,
    q.order_id,
    'OS-' || lpad(so.number::text, 6, '0') AS order_code,
    so.status_code AS order_status,
    so.received_at,
    c.id AS client_id,
    btrim(c.first_name || ' ' || c.last_name) AS client_name,
    c.document_type,
    c.document_number,
    c.phone AS client_phone,
    e.id AS equipment_id,
    e.type AS equipment_type,
    e.brand AS equipment_brand,
    e.model AS equipment_model,
    e.serial_number AS equipment_serial,
    q.description AS quotation_description,
    q.status AS quotation_status,
    q.total,
    q.created_at,
    q.updated_at,
    q.decided_at,
    q.decided_by,
    q.decision_observations,
    creator.username AS created_by_username,
    decided.username AS decided_by_username
FROM public.quotation q
JOIN public.service_orders so ON so.id = q.order_id
JOIN public.clients c ON c.id = so.client_id
JOIN public.equipment e ON e.id = so.equipment_id
JOIN public.users creator ON creator.id = q.created_by
LEFT JOIN public.users decided ON decided.id = q.decided_by;

-- ----------------------------------------------------------------
-- 8. COMPROBACIÓN FINAL
-- ----------------------------------------------------------------

DO $$
DECLARE
    pending_permissions bigint;
BEGIN
    SELECT count(*)
    INTO pending_permissions
    FROM (
        VALUES
            ('GERENTE', 'manage-quotations'),
            ('GERENTE', 'manage-deliveries'),
            ('ADMINISTRADOR', 'manage-quotations'),
            ('PERSONAL DE ATENCIÓN', 'manage-quotations')
    ) AS required(role_code, permission_code)
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.role_permissions rp
        WHERE rp.role_code = required.role_code
          AND rp.permission_code = required.permission_code
    );

    IF pending_permissions > 0 THEN
        RAISE EXCEPTION 'Faltan % permisos del módulo nuevo.', pending_permissions;
    END IF;
END $$;

COMMIT;
