INSERT INTO roles(code, name)
VALUES ('GERENTE', 'Gerente')
ON CONFLICT (code) DO NOTHING;

INSERT INTO permissions(code, description)
VALUES
    ('service-indicators', 'Consultar indicadores'),
    ('manage-deliveries', 'Gestionar entregas'),
    ('manage-quotations', 'Gestionar cotizaciones'),
    ('reports-export', 'Exportar reportes')
ON CONFLICT (code) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO role_permissions(role_code, permission_code)
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

CREATE TABLE quotation (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE RESTRICT,
    description text NOT NULL CHECK (btrim(description) <> ''),
    status varchar(20) NOT NULL DEFAULT 'PENDIENTE'
        CHECK (status IN ('PENDIENTE', 'AUTORIZADA', 'RECHAZADA')),
    total numeric(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    created_by uuid NOT NULL REFERENCES users(id),
    decided_by uuid REFERENCES users(id),
    decided_at timestamptz,
    decision_observations text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (status = 'PENDIENTE' AND decided_by IS NULL AND decided_at IS NULL)
        OR
        (status IN ('AUTORIZADA', 'RECHAZADA') AND decided_by IS NOT NULL
            AND decided_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX quotations_one_pending_per_order
    ON quotation(order_id) WHERE status = 'PENDIENTE';
CREATE INDEX quotations_order_idx ON quotation(order_id, created_at);

CREATE TABLE quotation_item (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    quotation_id uuid NOT NULL REFERENCES quotation(id) ON DELETE CASCADE,
    item_description text NOT NULL CHECK (btrim(item_description) <> ''),
    item_type varchar(20) NOT NULL CHECK (item_type IN ('SERVICIO', 'REPUESTO')),
    quantity numeric(12,3) NOT NULL CHECK (quantity > 0),
    unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    subtotal numeric(12,2) NOT NULL CHECK (subtotal >= 0)
);

CREATE INDEX quotation_items_quotation_idx ON quotation_item(quotation_id);

CREATE TABLE equipment_deliveries (
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
