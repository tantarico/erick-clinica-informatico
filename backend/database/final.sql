--
-- PostgreSQL database dump
--

-- Started on 2026-11-24 00:44:20

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 247 (class 1255 OID 17463)
-- Name: touch_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;


ALTER FUNCTION public.touch_updated_at() OWNER TO postgres;

--
-- TOC entry 244 (class 1255 OID 17455)
-- Name: validate_order_owner(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_order_owner() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM equipment WHERE id = NEW.equipment_id AND client_id = NEW.client_id) THEN
  RAISE EXCEPTION 'El equipo no pertenece al cliente de la orden' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $$;


ALTER FUNCTION public.validate_order_owner() OWNER TO postgres;

--
-- TOC entry 246 (class 1255 OID 17461)
-- Name: validate_status_transition(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_status_transition() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF NEW.status_code <> OLD.status_code AND NOT EXISTS (
  SELECT 1 FROM order_status_transitions WHERE from_status = OLD.status_code AND to_status = NEW.status_code
 ) THEN
  RAISE EXCEPTION 'Transición de estado no permitida' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $$;


ALTER FUNCTION public.validate_status_transition() OWNER TO postgres;

--
-- TOC entry 245 (class 1255 OID 17457)
-- Name: validate_technician(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_technician() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.technician_id AND role_code = 'TÉCNICO' AND active) THEN
  RAISE EXCEPTION 'Se requiere un técnico activo' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $$;


ALTER FUNCTION public.validate_technician() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 233 (class 1259 OID 17309)
-- Name: ai_prediagnoses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ai_prediagnoses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    requested_by uuid NOT NULL,
    provider character varying(40) DEFAULT 'gemini'::character varying NOT NULL,
    model character varying(120) NOT NULL,
    input_data jsonb NOT NULL,
    generated_diagnosis text,
    status character varying(20) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    error_message text,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    result_data jsonb,
    CONSTRAINT ai_prediagnoses_check CHECK (((((status)::text = 'PENDIENTE'::text) AND (completed_at IS NULL)) OR (((status)::text = 'GENERADO'::text) AND (completed_at IS NOT NULL) AND (generated_diagnosis IS NOT NULL) AND (btrim(generated_diagnosis) <> ''::text)) OR (((status)::text = 'ERROR'::text) AND (completed_at IS NOT NULL) AND (error_message IS NOT NULL) AND (btrim(error_message) <> ''::text)))),
    CONSTRAINT ai_prediagnoses_input_data_check CHECK ((jsonb_typeof(input_data) = 'object'::text)),
    CONSTRAINT ai_prediagnoses_status_check CHECK (((status)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'GENERADO'::character varying, 'ERROR'::character varying])::text[])))
);


ALTER TABLE public.ai_prediagnoses OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 17343)
-- Name: ai_validations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ai_validations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    prediagnosis_id uuid NOT NULL,
    technician_id uuid NOT NULL,
    decision character varying(20) NOT NULL,
    final_diagnosis text,
    observations text DEFAULT ''::text NOT NULL,
    validated_at timestamp with time zone DEFAULT now() NOT NULL,
    modified_data jsonb,
    CONSTRAINT ai_validations_decision_check CHECK (((decision)::text = ANY ((ARRAY['ACEPTADO'::character varying, 'MODIFICADO'::character varying, 'DESCARTADO'::character varying, 'RECHAZADO'::character varying])::text[]))),
    CONSTRAINT ai_validations_final_diagnosis_check CHECK ((btrim(final_diagnosis) <> ''::text))
);


ALTER TABLE public.ai_validations OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 17399)
-- Name: backup_runs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.backup_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    requested_by uuid,
    status character varying(20) DEFAULT 'EN_PROCESO'::character varying NOT NULL,
    file_path text,
    checksum_sha256 character varying(64),
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    error_message text,
    CONSTRAINT backup_runs_check CHECK (((finished_at IS NULL) OR (finished_at >= started_at))),
    CONSTRAINT backup_runs_check1 CHECK (((((status)::text = 'EN_PROCESO'::text) AND (finished_at IS NULL)) OR (((status)::text = 'COMPLETADO'::text) AND (finished_at IS NOT NULL) AND (file_path IS NOT NULL) AND (checksum_sha256 IS NOT NULL) AND ((checksum_sha256)::text ~ '^[a-f0-9]{64}$'::text)) OR (((status)::text = 'ERROR'::text) AND (finished_at IS NOT NULL) AND (error_message IS NOT NULL)))),
    CONSTRAINT backup_runs_status_check CHECK (((status)::text = ANY ((ARRAY['EN_PROCESO'::character varying, 'COMPLETADO'::character varying, 'ERROR'::character varying])::text[])))
);


ALTER TABLE public.backup_runs OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 17043)
-- Name: clients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_type character varying(10) NOT NULL,
    document_number character varying(25) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(100) DEFAULT ''::character varying NOT NULL,
    phone character varying(30) NOT NULL,
    email character varying(254) DEFAULT ''::character varying NOT NULL,
    address character varying(300) DEFAULT ''::character varying NOT NULL,
    observations text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT clients_check CHECK ((((document_type)::text = 'RUC'::text) OR (btrim((last_name)::text) <> ''::text))),
    CONSTRAINT clients_check1 CHECK (((((document_type)::text = 'DNI'::text) AND ((document_number)::text ~ '^[0-9]{8}$'::text)) OR (((document_type)::text = 'RUC'::text) AND ((document_number)::text ~ '^[0-9]{11}$'::text)) OR (((document_type)::text = 'CE'::text) AND ((document_number)::text ~ '^[a-zA-Z0-9-]{5,20}$'::text)) OR (((document_type)::text = 'Otro'::text) AND ((length((document_number)::text) >= 1) AND (length((document_number)::text) <= 25))))),
    CONSTRAINT clients_document_number_check CHECK (((document_number)::text = btrim((document_number)::text))),
    CONSTRAINT clients_document_type_check CHECK (((document_type)::text = ANY ((ARRAY['DNI'::character varying, 'RUC'::character varying, 'CE'::character varying, 'Otro'::character varying])::text[]))),
    CONSTRAINT clients_email_check CHECK ((((email)::text = ''::text) OR ((email)::text ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::text))),
    CONSTRAINT clients_first_name_check CHECK ((btrim((first_name)::text) <> ''::text))
);


ALTER TABLE public.clients OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 17076)
-- Name: equipment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.equipment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    type character varying(30) NOT NULL,
    brand character varying(100) NOT NULL,
    model character varying(100) NOT NULL,
    serial_number character varying(100) DEFAULT ''::character varying NOT NULL,
    characteristics text DEFAULT ''::text NOT NULL,
    accessories text DEFAULT ''::text NOT NULL,
    observations text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT equipment_brand_check CHECK ((btrim((brand)::text) <> ''::text)),
    CONSTRAINT equipment_check CHECK ((((type)::text = 'Otro'::text) OR (btrim((serial_number)::text) <> ''::text))),
    CONSTRAINT equipment_model_check CHECK ((btrim((model)::text) <> ''::text)),
    CONSTRAINT equipment_serial_number_check CHECK (((serial_number)::text = btrim((serial_number)::text))),
    CONSTRAINT equipment_type_check CHECK (((type)::text = ANY ((ARRAY['Laptop'::character varying, 'PC'::character varying, 'Impresora'::character varying, 'Monitor'::character varying, 'Tablet'::character varying, 'Otro'::character varying])::text[])))
);


ALTER TABLE public.equipment OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 32869)
-- Name: equipment_deliveries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.equipment_deliveries (
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT equipment_deliveries_recipient_name_check CHECK ((btrim((recipient_name)::text) <> ''::text))
);


ALTER TABLE public.equipment_deliveries OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16965)
-- Name: flyway_schema_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.flyway_schema_history (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


ALTER TABLE public.flyway_schema_history OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 17421)
-- Name: monitoring_checks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.monitoring_checks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    component character varying(80) NOT NULL,
    status character varying(10) NOT NULL,
    response_time_ms integer,
    message text DEFAULT ''::text NOT NULL,
    checked_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT monitoring_checks_response_time_ms_check CHECK ((response_time_ms >= 0)),
    CONSTRAINT monitoring_checks_status_check CHECK (((status)::text = ANY ((ARRAY['OK'::character varying, 'ALERTA'::character varying, 'ERROR'::character varying])::text[])))
);


ALTER TABLE public.monitoring_checks OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 17235)
-- Name: order_status_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_status_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    from_status character varying(30),
    to_status character varying(30) NOT NULL,
    changed_by uuid NOT NULL,
    reason text DEFAULT ''::text NOT NULL,
    changed_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.order_status_history OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 17124)
-- Name: order_status_transitions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_status_transitions (
    from_status character varying(30) NOT NULL,
    to_status character varying(30) NOT NULL,
    CONSTRAINT order_status_transitions_check CHECK (((from_status)::text <> (to_status)::text))
);


ALTER TABLE public.order_status_transitions OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 17113)
-- Name: order_statuses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_statuses (
    code character varying(30) NOT NULL,
    name character varying(80) NOT NULL,
    terminal boolean DEFAULT false NOT NULL
);


ALTER TABLE public.order_statuses OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16991)
-- Name: permissions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.permissions (
    code character varying(50) NOT NULL,
    description character varying(120) NOT NULL
);


ALTER TABLE public.permissions OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 32800)
-- Name: quotation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.quotation (
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
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT quotation_check CHECK (((((status)::text = 'PENDIENTE'::text) AND (decided_by IS NULL) AND (decided_at IS NULL)) OR (((status)::text = ANY ((ARRAY['AUTORIZADA'::character varying, 'RECHAZADA'::character varying])::text[])) AND (decided_by IS NOT NULL) AND (decided_at IS NOT NULL)))),
    CONSTRAINT quotation_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT quotation_status_check CHECK (((status)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'AUTORIZADA'::character varying, 'RECHAZADA'::character varying])::text[]))),
    CONSTRAINT quotation_total_check CHECK ((total >= (0)::numeric))
);


ALTER TABLE public.quotation OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 17142)
-- Name: service_order_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.service_order_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.service_order_number_seq OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 17143)
-- Name: service_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.service_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    number bigint DEFAULT nextval('public.service_order_number_seq'::regclass) NOT NULL,
    equipment_id uuid NOT NULL,
    client_id uuid NOT NULL,
    received_by uuid NOT NULL,
    reported_problem text NOT NULL,
    intake_condition text DEFAULT ''::text NOT NULL,
    intake_accessories text DEFAULT ''::text NOT NULL,
    status_code character varying(30) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    priority character varying(10) DEFAULT 'NORMAL'::character varying NOT NULL,
    estimated_delivery timestamp with time zone,
    closed_at timestamp with time zone,
    closure_summary text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    received_at date DEFAULT CURRENT_DATE NOT NULL,
    finalized_at timestamp with time zone,
    finalized_by uuid,
    CONSTRAINT service_orders_check CHECK (((estimated_delivery IS NULL) OR (estimated_delivery >= created_at))),
    CONSTRAINT service_orders_check1 CHECK (((((status_code)::text = ANY ((ARRAY['CERRADA'::character varying, 'CANCELADA'::character varying])::text[])) AND (closed_at IS NOT NULL) AND (closure_summary IS NOT NULL) AND (btrim(closure_summary) <> ''::text)) OR (((status_code)::text <> ALL ((ARRAY['CERRADA'::character varying, 'CANCELADA'::character varying])::text[])) AND (closed_at IS NULL)))),
    CONSTRAINT service_orders_finalized_metadata CHECK (((((status_code)::text = 'FINALIZADA'::text) AND (finalized_at IS NOT NULL) AND (finalized_by IS NOT NULL)) OR (((status_code)::text <> 'FINALIZADA'::text) AND (finalized_at IS NULL) AND (finalized_by IS NULL)))),
    CONSTRAINT service_orders_priority_check CHECK (((priority)::text = ANY ((ARRAY['BAJA'::character varying, 'NORMAL'::character varying, 'ALTA'::character varying, 'URGENTE'::character varying])::text[]))),
    CONSTRAINT service_orders_reported_problem_check CHECK ((btrim(reported_problem) <> ''::text))
);


ALTER TABLE public.service_orders OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 17015)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    username character varying(80) NOT NULL,
    password_hash character varying(100) NOT NULL,
    role_code character varying(40) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_first_name_check CHECK ((btrim((first_name)::text) <> ''::text)),
    CONSTRAINT users_last_name_check CHECK ((btrim((last_name)::text) <> ''::text)),
    CONSTRAINT users_username_check CHECK (((btrim((username)::text) <> ''::text) AND ((username)::text = btrim((username)::text))))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 32920)
-- Name: quotation_detail_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.quotation_detail_view AS
 SELECT q.id AS quotation_id,
    q.order_id,
    ('OS-'::text || lpad((so.number)::text, 6, '0'::text)) AS order_code,
    so.status_code AS order_status,
    so.received_at,
    c.id AS client_id,
    btrim((((c.first_name)::text || ' '::text) || (c.last_name)::text)) AS client_name,
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
   FROM (((((public.quotation q
     JOIN public.service_orders so ON ((so.id = q.order_id)))
     JOIN public.clients c ON ((c.id = so.client_id)))
     JOIN public.equipment e ON ((e.id = so.equipment_id)))
     JOIN public.users creator ON ((creator.id = q.created_by)))
     LEFT JOIN public.users decided ON ((decided.id = q.decided_by)));


ALTER VIEW public.quotation_detail_view OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 32843)
-- Name: quotation_item; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.quotation_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    quotation_id uuid NOT NULL,
    item_description text NOT NULL,
    item_type character varying(20) NOT NULL,
    quantity numeric(12,3) NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    subtotal numeric(12,2) NOT NULL,
    CONSTRAINT quotation_item_item_description_check CHECK ((btrim(item_description) <> ''::text)),
    CONSTRAINT quotation_item_item_type_check CHECK (((item_type)::text = ANY ((ARRAY['SERVICIO'::character varying, 'REPUESTO'::character varying])::text[]))),
    CONSTRAINT quotation_item_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT quotation_item_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT quotation_item_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


ALTER TABLE public.quotation_item OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 16998)
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.role_permissions (
    role_code character varying(40) NOT NULL,
    permission_code character varying(50) NOT NULL
);


ALTER TABLE public.role_permissions OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 16982)
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    code character varying(40) NOT NULL,
    name character varying(80) NOT NULL
);


ALTER TABLE public.roles OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 17470)
-- Name: service_indicators; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.service_indicators AS
 SELECT status_code,
    count(*) AS total,
    avg((EXTRACT(epoch FROM (closed_at - created_at)) / (3600)::numeric)) FILTER (WHERE (closed_at IS NOT NULL)) AS average_duration_hours
   FROM public.service_orders
  GROUP BY status_code;


ALTER VIEW public.service_indicators OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 17375)
-- Name: system_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid,
    event_type character varying(80) NOT NULL,
    entity_type character varying(80) NOT NULL,
    entity_id uuid,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    result character varying(10) DEFAULT 'SUCCESS'::character varying NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    CONSTRAINT system_events_details_check CHECK ((jsonb_typeof(details) = 'object'::text)),
    CONSTRAINT system_events_result_check CHECK (((result)::text = ANY ((ARRAY['SUCCESS'::character varying, 'FAILED'::character varying])::text[])))
);


ALTER TABLE public.system_events OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 17439)
-- Name: system_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_settings (
    key character varying(80) NOT NULL,
    value jsonb NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.system_settings OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 17273)
-- Name: technical_attentions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.technical_attentions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    technician_id uuid NOT NULL,
    diagnosis text NOT NULL,
    actions_performed text NOT NULL,
    recommendations text DEFAULT ''::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    performed_tests text DEFAULT ''::text NOT NULL,
    parts_used text DEFAULT ''::text NOT NULL,
    observations text DEFAULT ''::text NOT NULL,
    result_summary text DEFAULT ''::text NOT NULL,
    updated_by uuid,
    CONSTRAINT technical_attentions_actions_performed_check CHECK ((btrim(actions_performed) <> ''::text)),
    CONSTRAINT technical_attentions_check CHECK (((finished_at IS NULL) OR (finished_at >= started_at))),
    CONSTRAINT technical_attentions_diagnosis_check CHECK ((btrim(diagnosis) <> ''::text))
);


ALTER TABLE public.technical_attentions OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 17200)
-- Name: technician_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.technician_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    technician_id uuid NOT NULL,
    assigned_by uuid NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    notes text DEFAULT ''::text NOT NULL,
    CONSTRAINT technician_assignments_check CHECK (((ended_at IS NULL) OR (ended_at >= assigned_at)))
);


ALTER TABLE public.technician_assignments OWNER TO postgres;

--
-- TOC entry 5370 (class 0 OID 17309)
-- Dependencies: 233
-- Data for Name: ai_prediagnoses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ai_prediagnoses (id, order_id, requested_by, provider, model, input_data, generated_diagnosis, status, error_message, requested_at, completed_at, result_data) FROM stdin;
05c9d944-2f16-41e0-babf-37a68fbf67ea	4eac7b12-84dc-4176-bc51-2e1807855335	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	gemini	gemini-3.8-flash	{"brand": "lenovo", "model": "g310", "observations": "se registra la laptop con pantalla azul", "equipmentType": "Laptop", "reportedProblem": "Error con el sistema, pantallazo azul con codigo de disco dañando", "additionalSymptoms": "", "initialObservations": "se registra la laptop con pantalla azul", "technicalCharacteristics": ""}	{\n  "classification": "Falla lógica o física de almacenamiento / Inestabilidad de sistema operativo (BSOD)",\n  "suggestedPriority": "ALTA",\n  "possibleCauses": [\n    "Degradación física o presencia de sectores defectuosos en la unidad de almacenamiento (HDD/SSD)",\n    "Corrupción del sistema de archivos o partición de arranque del sistema operativo",\n    "Falso contacto o degradación en el conector SATA/interfaz de la unidad",\n    "Inestabilidad o fallas en la memoria RAM que generen errores de paginación o lectura",\n    "Controladores de almacenamiento incompatibles o dañados tras actualización"\n  ],\n  "recommendedTests": [\n    "Ejecutar diagnóstico de salud SMART mediante un entorno Live USB sin iniciar el sistema operativo",\n    "Realizar prueba de diagnóstico de hardware Lenovo (Lenovo Diagnostics) mediante la tecla de función al arranque",\n    "Verificar la integridad del sistema de archivos mediante chkdsk en modo solo lectura desde la consola de recuperación",\n    "Ejecutar test de diagnóstico de memoria RAM (MemTest86 o diagnóstico integrado) para descartar fallas de memoria",\n    "Inspección física y reconexión segura de la unidad de almacenamiento para descartar falso contacto"\n  ],\n  "recommendations": [\n    "Priorizar el respaldo inmediato de información crítica antes de someter la unidad a pruebas de estrés o escritura intensiva",\n    "Evitar reintentos de arranque repetidos que puedan acelerar el daño en un disco mecánico con sectores dañados",\n    "Utilizar un entorno de arranque externo (PE/Live USB) para verificar si la unidad es detectable y legible",\n    "Evaluar el reemplazo por una unidad de estado sólido (SSD) en caso de confirmarse daño en el almacenamiento"\n  ],\n  "warnings": [\n    "No se especifica el código de error BSOD exacto ni el tipo de unidad instalada (HDD o SSD)",\n    "Intentar reparar sectores dañados con herramientas de escritura agresiva puede derivar en pérdida irreversible de datos",\n    "La manipulación interna de la laptop requiere desconectar previamente la batería y el adaptador de corriente para evitar cortocircuitos",\n    "Se requiere confirmación técnica mediante mediciones y lectura de registros para emitir un diagnóstico definitivo"\n  ]\n}	GENERADO	\N	2026-10-18 14:28:01.591992-05	2026-10-18 14:28:01.591992-05	{"warnings": ["No se especifica el código de error BSOD exacto ni el tipo de unidad instalada (HDD o SSD)", "Intentar reparar sectores dañados con herramientas de escritura agresiva puede derivar en pérdida irreversible de datos", "La manipulación interna de la laptop requiere desconectar previamente la batería y el adaptador de corriente para evitar cortocircuitos", "Se requiere confirmación técnica mediante mediciones y lectura de registros para emitir un diagnóstico definitivo"], "classification": "Falla lógica o física de almacenamiento / Inestabilidad de sistema operativo (BSOD)", "possibleCauses": ["Degradación física o presencia de sectores defectuosos en la unidad de almacenamiento (HDD/SSD)", "Corrupción del sistema de archivos o partición de arranque del sistema operativo", "Falso contacto o degradación en el conector SATA/interfaz de la unidad", "Inestabilidad o fallas en la memoria RAM que generen errores de paginación o lectura", "Controladores de almacenamiento incompatibles o dañados tras actualización"], "recommendations": ["Priorizar el respaldo inmediato de información crítica antes de someter la unidad a pruebas de estrés o escritura intensiva", "Evitar reintentos de arranque repetidos que puedan acelerar el daño en un disco mecánico con sectores dañados", "Utilizar un entorno de arranque externo (PE/Live USB) para verificar si la unidad es detectable y legible", "Evaluar el reemplazo por una unidad de estado sólido (SSD) en caso de confirmarse daño en el almacenamiento"], "recommendedTests": ["Ejecutar diagnóstico de salud SMART mediante un entorno Live USB sin iniciar el sistema operativo", "Realizar prueba de diagnóstico de hardware Lenovo (Lenovo Diagnostics) mediante la tecla de función al arranque", "Verificar la integridad del sistema de archivos mediante chkdsk en modo solo lectura desde la consola de recuperación", "Ejecutar test de diagnóstico de memoria RAM (MemTest86 o diagnóstico integrado) para descartar fallas de memoria", "Inspección física y reconexión segura de la unidad de almacenamiento para descartar falso contacto"], "suggestedPriority": "ALTA"}
4abad3be-3a48-4aac-899a-a5892f3164fb	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	ed8565ad-31a6-4bf7-bfaa-518602317906	gemini	gemini-3.8-flash	{"brand": "lenovo", "model": "ThinkPad E14", "observations": "Se reporta equipo sin energia y sin señales de encendido", "equipmentType": "Laptop", "reportedProblem": "Equipo no enciende", "additionalSymptoms": "", "initialObservations": "Se reporta equipo sin energia y sin señales de encendido", "technicalCharacteristics": "Semi nueva"}	\N	ERROR	Gemini no respondió con un prediagnóstico válido.	2026-11-06 21:54:03.911462-05	2026-11-06 21:54:03.911462-05	\N
fc5b0daa-ac16-411b-9b85-c8fe112f037f	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	ed8565ad-31a6-4bf7-bfaa-518602317906	gemini	gemini-3.8-flash	{"brand": "lenovo", "model": "ThinkPad E14", "observations": "Se reporta equipo sin energia y sin señales de encendido", "equipmentType": "Laptop", "reportedProblem": "Equipo no enciende", "additionalSymptoms": "", "initialObservations": "Se reporta equipo sin energia y sin señales de encendido", "technicalCharacteristics": "Semi nueva"}	{\n  "classification": "Falla de encendido / Ausencia total de alimentación (No Power)",\n  "suggestedPriority": "ALTA",\n  "possibleCauses": [\n    "Falla o daño en el cargador/adaptador de corriente USB-C",\n    "Batería principal completamente descargada o en estado de bloqueo/protección",\n    "Bloqueo lógico del controlador embebido (Embedded Controller / EC)",\n    "Daño físico o desprendimiento en el puerto de carga USB-C",\n    "Cortocircuito en la etapa de entrada de alimentación o línea principal (VBUS / VIN)",\n    "Falla en los MOSFETs de conmutación de entrada o en el circuito de gestión de energía (PMIC/Charger IC)"\n  ],\n  "recommendedTests": [\n    "Probar con un adaptador de corriente USB-C original y funcional de potencia adecuada (mínimo 65W)",\n    "Realizar un restablecimiento estático mediante el orificio de reinicio de emergencia (pinhole reset) en la base del chasis",\n    "Inspeccionar visualmente el puerto USB-C en busca de suciedad, pines doblados o daño físico",\n    "Observar si el LED de estado junto al conector de carga emite algún parpadeo o iluminación tenue",\n    "Desconectar la batería interna y comprobar si enciende solo con el adaptador conectado",\n    "Medir con multímetro la tensión de entrada USB-C (negociación de Power Delivery a 5V/20V)"\n  ],\n  "recommendations": [\n    "Verificar el estado de la garantía oficial de Lenovo antes de abrir el chasis",\n    "Comenzar el descarte por el botón de reinicio de emergencia antes de cualquier intervención física",\n    "Utilizar protección contra descargas electrostáticas (ESD) si se realiza apertura del chasis",\n    "Evitar el uso de cargadores universales no certificados para ThinkPad"\n  ],\n  "warnings": [\n    "No se dispone de mediciones eléctricas previas de voltaje o consumo de corriente",\n    "La manipulación interna del chasis puede anular la garantía de fábrica si aún está vigente",\n    "Las pruebas en placa base con multímetro requieren conocimientos técnicos y precauciones para no provocar cortocircuitos accidentales"\n  ]\n}	GENERADO	\N	2026-11-06 21:54:38.509376-05	2026-11-06 21:54:38.509376-05	{"warnings": ["No se dispone de mediciones eléctricas previas de voltaje o consumo de corriente", "La manipulación interna del chasis puede anular la garantía de fábrica si aún está vigente", "Las pruebas en placa base con multímetro requieren conocimientos técnicos y precauciones para no provocar cortocircuitos accidentales"], "classification": "Falla de encendido / Ausencia total de alimentación (No Power)", "possibleCauses": ["Falla o daño en el cargador/adaptador de corriente USB-C", "Batería principal completamente descargada o en estado de bloqueo/protección", "Bloqueo lógico del controlador embebido (Embedded Controller / EC)", "Daño físico o desprendimiento en el puerto de carga USB-C", "Cortocircuito en la etapa de entrada de alimentación o línea principal (VBUS / VIN)", "Falla en los MOSFETs de conmutación de entrada o en el circuito de gestión de energía (PMIC/Charger IC)"], "recommendations": ["Verificar el estado de la garantía oficial de Lenovo antes de abrir el chasis", "Comenzar el descarte por el botón de reinicio de emergencia antes de cualquier intervención física", "Utilizar protección contra descargas electrostáticas (ESD) si se realiza apertura del chasis", "Evitar el uso de cargadores universales no certificados para ThinkPad"], "recommendedTests": ["Probar con un adaptador de corriente USB-C original y funcional de potencia adecuada (mínimo 65W)", "Realizar un restablecimiento estático mediante el orificio de reinicio de emergencia (pinhole reset) en la base del chasis", "Inspeccionar visualmente el puerto USB-C en busca de suciedad, pines doblados o daño físico", "Observar si el LED de estado junto al conector de carga emite algún parpadeo o iluminación tenue", "Desconectar la batería interna y comprobar si enciende solo con el adaptador conectado", "Medir con multímetro la tensión de entrada USB-C (negociación de Power Delivery a 5V/20V)"], "suggestedPriority": "ALTA"}
ebb0bdfb-fb6e-4cab-ace1-3246439190b0	e90e9fde-5f78-464d-9ae3-e8236935baa1	ed8565ad-31a6-4bf7-bfaa-518602317906	gemini	gemini-3.8-flash	{"brand": "TEROS", "model": "T320", "observations": "", "equipmentType": "Monitor", "reportedProblem": "reyas y parpadeos", "additionalSymptoms": "", "initialObservations": "", "technicalCharacteristics": "negra con raspones"}	\N	ERROR	Gemini no respondió con un prediagnóstico válido.	2026-11-07 19:06:11.928853-05	2026-11-07 19:06:11.928853-05	\N
8893da80-a544-41df-9eed-9e8777ec66ee	e90e9fde-5f78-464d-9ae3-e8236935baa1	ed8565ad-31a6-4bf7-bfaa-518602317906	gemini	gemini-3.8-flash	{"brand": "TEROS", "model": "T320", "observations": "", "equipmentType": "Monitor", "reportedProblem": "reyas y parpadeos", "additionalSymptoms": "", "initialObservations": "", "technicalCharacteristics": "negra con raspones"}	\N	ERROR	Gemini no respondió con un prediagnóstico válido.	2026-11-07 19:06:31.663451-05	2026-11-07 19:06:31.663451-05	\N
6afd267f-f1cd-409c-9c95-307dbf39177b	e90e9fde-5f78-464d-9ae3-e8236935baa1	ed8565ad-31a6-4bf7-bfaa-518602317906	gemini	gemini-3.8-flash	{"brand": "TEROS", "model": "T320", "observations": "", "equipmentType": "Monitor", "reportedProblem": "reyas y parpadeos", "additionalSymptoms": "", "initialObservations": "", "technicalCharacteristics": "negra con raspones"}	\N	ERROR	Gemini no respondió con un prediagnóstico válido.	2026-11-07 19:09:11.810855-05	2026-11-07 19:09:11.810855-05	\N
3d72bc17-53e6-4294-a023-089aba1d8c01	e90e9fde-5f78-464d-9ae3-e8236935baa1	ed8565ad-31a6-4bf7-bfaa-518602317906	gemini	gemini-3.8-flash	{"brand": "TEROS", "model": "T320", "observations": "", "equipmentType": "Monitor", "reportedProblem": "reyas y parpadeos", "additionalSymptoms": "", "initialObservations": "", "technicalCharacteristics": "negra con raspones"}	\N	ERROR	Gemini no respondió con un prediagnóstico válido.	2026-11-07 19:22:01.251832-05	2026-11-07 19:22:01.251832-05	\N
\.


--
-- TOC entry 5371 (class 0 OID 17343)
-- Dependencies: 234
-- Data for Name: ai_validations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ai_validations (id, prediagnosis_id, technician_id, decision, final_diagnosis, observations, validated_at, modified_data) FROM stdin;
\.


--
-- TOC entry 5373 (class 0 OID 17399)
-- Dependencies: 236
-- Data for Name: backup_runs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.backup_runs (id, requested_by, status, file_path, checksum_sha256, started_at, finished_at, error_message) FROM stdin;
db8ab40a-d291-4259-8eff-2f1b53e14bc3	\N	ERROR	\N	\N	2026-11-21 21:00:00.01122-05	2026-11-21 21:00:00.034497-05	No se pudo generar un respaldo válido: Cannot run program "pg_dump": CreateProcess error=2, El sistema no puede encontrar el archivo especificado
\.


--
-- TOC entry 5361 (class 0 OID 17043)
-- Dependencies: 224
-- Data for Name: clients; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clients (id, document_type, document_number, first_name, last_name, phone, email, address, observations, created_at, updated_at) FROM stdin;
93253264-d08a-4a36-96c6-94034b8a9dce	DNI	76083706	ERICK MANUEL	RUIZ GUERRA	+5194120665	erickmruiz96@gmail.com	jiron 2 de mayo	prioridad	2026-10-03 18:32:15.305467-05	2026-10-03 18:44:32.026169-05
e96aea1a-4117-4cc7-a881-6ab2a3364824	DNI	75754808	Ruth Anai	Garcia Siancas	946806155	u22302585@utp.edu.pe	sullana		2026-10-09 19:20:59.746823-05	2026-10-09 19:20:59.746823-05
93fecc7d-8d2b-4764-9f02-cb0a07c2e986	DNI	72032456	Fiorela	Garcia Siancas	985678941	fiorisiancas@gmail.com	piura		2026-10-18 13:44:05.291543-05	2026-10-18 13:44:05.291543-05
4f971d71-646d-4ae7-802e-c9f5b20ae6db	DNI	87654321	Ana María	Vásquez Salazar	987654321	Anixmari.salazar@gmail.com	Los cabos verdes SN		2026-10-31 21:21:08.821607-05	2026-10-31 21:21:08.821607-05
0795be60-6fc9-4eb9-9623-cda31d0e328d	DNI	72586942	Melin	bueno arrascue	957633892	mjbaxk24@gmail.com	Canaan s/n		2026-11-06 22:06:57.213344-05	2026-11-06 22:06:57.213344-05
\.


--
-- TOC entry 5362 (class 0 OID 17076)
-- Dependencies: 225
-- Data for Name: equipment; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.equipment (id, client_id, type, brand, model, serial_number, characteristics, accessories, observations, created_at, updated_at) FROM stdin;
18913268-cece-4753-aa0d-d0e228958395	93253264-d08a-4a36-96c6-94034b8a9dce	Impresora	EPSON	L365	XR2546SDS		cable de poder y de datos	la impresion sale a rayas ademas de estar con derrame de tinta en los costados	2026-10-03 18:33:38.068254-05	2026-10-03 18:33:38.068254-05
a2a73b0b-e9ec-42d8-b27b-408ad4570df8	93fecc7d-8d2b-4764-9f02-cb0a07c2e986	Laptop	lenovo	g310	XR25264545		cargador y mouse	color palteado con un skim rojo	2026-10-18 13:45:15.203139-05	2026-10-18 13:45:15.203139-05
03022a24-38a0-42b2-9409-489d8ca65e7e	4f971d71-646d-4ae7-802e-c9f5b20ae6db	Laptop	lenovo	ThinkPad E14	QA-2026-001	Semi nueva	Cargador y caja		2026-10-31 21:46:27.82746-05	2026-10-31 21:46:27.82746-05
4372c874-dd4f-42ec-82f5-47c6d43400d8	0795be60-6fc9-4eb9-9623-cda31d0e328d	Impresora	EPSON	l3250	xv25sd52sd4	negra con raspones	cable de poder y de datos		2026-11-06 22:07:47.05464-05	2026-11-06 22:07:47.05464-05
686f9b48-1025-4319-ad41-f04f79a1c609	e96aea1a-4117-4cc7-a881-6ab2a3364824	Monitor	TEROS	T320	CXS52SR56S	negra con raspones	SIN ACCESORIOS		2026-11-06 22:34:28.530596-05	2026-11-06 22:34:28.530596-05
\.


--
-- TOC entry 5378 (class 0 OID 32869)
-- Dependencies: 242
-- Data for Name: equipment_deliveries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.equipment_deliveries (id, order_id, delivered_at, responsible_id, client_confirmed, recipient_name, recipient_document, reception_signature, reception_constancy, observations, created_at) FROM stdin;
\.


--
-- TOC entry 5356 (class 0 OID 16965)
-- Dependencies: 219
-- Data for Name: flyway_schema_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success) FROM stdin;
1	1	complete schema	SQL	V1__complete_schema.sql	-1719685787	postgres	2026-10-03 14:15:17.936418	155	t
2	2	catalogs	SQL	V2__catalogs.sql	-1853366414	postgres	2026-10-03 14:15:18.124425	10	t
3	3	validate client contact details	SQL	V3__validate_client_contact_details.sql	1251041768	postgres	2026-10-09 00:28:01.589933	76	t
4	4	service order intake date and transitions	SQL	V4__service_order_intake_date_and_transitions.sql	1240263402	postgres	2026-10-18 11:15:10.826987	111	t
5	5	technical attentions and ai validation	SQL	V5__technical_attentions_and_ai_validation.sql	313629292	postgres	2026-10-18 11:15:10.962784	35	t
6	6	sprint six audit outcomes	SQL	V6__sprint_six_audit_outcomes.sql	-928675762	postgres	2026-10-18 13:24:18.457969	101	t
7	7	allow service staff to assign technicians	SQL	V7__allow_service_staff_to_assign_technicians.sql	-257297432	postgres	2026-11-21 19:03:40.774931	20	t
8	8	quotations delivery manager and reports	SQL	V8__quotations_delivery_manager_and_reports.sql	41251688	postgres	2026-11-23 23:31:53.522923	153	t
\.


--
-- TOC entry 5374 (class 0 OID 17421)
-- Dependencies: 237
-- Data for Name: monitoring_checks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.monitoring_checks (id, component, status, response_time_ms, message, checked_at) FROM stdin;
d3188d87-6b5a-4208-8ecb-cbe3a89beb4c	backend	OK	0	Aplicación disponible	2026-10-18 13:25:41.440699-05
ac056c27-44cc-4894-9f4a-bc660b508b08	postgresql	OK	0	Conexión verificada	2026-10-18 13:25:41.440699-05
bc4836fc-040c-4119-8fa9-97ba5f69a283	gemini	ALERTA	0	No configurado.	2026-10-18 13:25:41.440699-05
624f259e-299a-430c-b0dd-04d9f540bcc4	backend	OK	0	Aplicación disponible	2026-10-18 13:30:18.554725-05
720df69e-6606-4a36-af23-930491de7d1e	postgresql	OK	0	Conexión verificada	2026-10-18 13:30:18.554725-05
a38cedd0-80f3-4177-9ec0-eb39d2214467	gemini	ALERTA	0	No configurado.	2026-10-18 13:30:18.554725-05
624c9a80-1972-4a8e-8584-0698a63321e6	backend	OK	0	Aplicación disponible	2026-10-18 13:39:28.869772-05
4b0f896a-2a46-4fe6-8830-d4d09b526eeb	postgresql	OK	0	Conexión verificada	2026-10-18 13:39:28.869772-05
bbdf0355-e37f-4e5c-8c7d-2b98a4232e30	backend	OK	0	Aplicación disponible	2026-10-18 14:00:37.731944-05
20518589-c35c-4c93-bcbc-e93b1a390fc5	postgresql	OK	0	Conexión verificada	2026-10-18 14:00:37.731944-05
c2152ccd-4d73-4168-a589-4f6732fa9e30	gemini	OK	\N	Solicitud Gemini completada	2026-10-18 14:28:01.596566-05
f9986889-02a7-48ce-8cbd-74b109a8a88c	backend	OK	0	Aplicación disponible	2026-10-18 14:29:48.756099-05
45b18bdf-844f-4594-9baf-c1c35e3f363a	postgresql	OK	0	Conexión verificada	2026-10-18 14:29:48.756099-05
9a0c7b2f-59e4-44f3-b9a9-57e1b77f6385	backend	OK	0	Aplicación disponible	2026-10-24 19:24:37.836353-05
e7c21f57-1688-4cdb-9fbb-6f217302f4ab	postgresql	OK	0	Conexión verificada	2026-10-24 19:24:37.836353-05
b8f66f3f-7688-491b-9078-f6bb62571ff3	gemini	ERROR	\N	Solicitud Gemini fallida	2026-11-06 21:54:03.905105-05
5ff17798-178a-4990-bacf-18f984775dee	gemini	OK	\N	Solicitud Gemini completada	2026-11-06 21:54:38.511389-05
9e8e5761-66e8-40f6-b249-09615ac5a9d4	gemini	ERROR	\N	Solicitud Gemini fallida	2026-11-07 19:06:11.922592-05
33851f7b-437f-45ab-973e-7aaac13f36bf	gemini	ERROR	\N	Solicitud Gemini fallida	2026-11-07 19:06:31.66272-05
99a8ca20-f765-4199-a4f1-7b50ca4cf1d9	backend	OK	0	Aplicación disponible	2026-11-07 19:07:28.31523-05
153549a8-e10f-425e-ad25-e902d1eab4d6	postgresql	OK	0	Conexión verificada	2026-11-07 19:07:28.31523-05
13dfe0e8-be04-4baf-a7bb-d4b38f7f6fdf	backend	OK	0	Aplicación disponible	2026-11-07 19:07:32.12319-05
11941f68-ac71-4ec1-a9db-91745692808b	postgresql	OK	0	Conexión verificada	2026-11-07 19:07:32.12319-05
129e51b6-5f31-4ba8-9a22-ee032ad1e977	backend	OK	0	Aplicación disponible	2026-11-07 19:07:33.07916-05
c801213f-3d50-4465-be61-18f1db1640ef	postgresql	OK	0	Conexión verificada	2026-11-07 19:07:33.07916-05
855310fc-79f9-46b9-96c0-ed6ce596c7b8	gemini	ERROR	\N	Solicitud Gemini fallida	2026-11-07 19:09:11.809238-05
fac9e909-b7f8-4b8c-a0ed-58a8a7cea676	gemini	ERROR	\N	Solicitud Gemini fallida	2026-11-07 19:22:01.249795-05
0332b3d0-9723-426e-960f-9518e10294bf	backend	OK	0	Aplicación disponible	2026-11-21 19:04:29.265841-05
87b74572-2110-4a5f-bfd5-b904539312a3	postgresql	OK	0	Conexión verificada	2026-11-21 19:04:29.265841-05
fdcdf547-b28f-49a1-a0c6-3bafeb3fe8ae	backend	OK	0	Aplicación disponible	2026-11-21 19:05:15.076784-05
805530c5-080f-40c9-a0fb-7e780adcc147	postgresql	OK	0	Conexión verificada	2026-11-21 19:05:15.076784-05
b5753add-6978-408a-a2f2-e56c56c05bf6	backend	OK	0	Aplicación disponible	2026-11-21 19:05:26.88639-05
4872f2b2-bee2-43c8-9b99-9dc2202f8a53	postgresql	OK	0	Conexión verificada	2026-11-21 19:05:26.88639-05
a9f8686e-b5d4-4e01-b7e6-dfb1a24fc3b2	backend	OK	0	Aplicación disponible	2026-11-21 19:05:29.209256-05
77b2c43b-339f-4640-b352-103b6b11bc8a	postgresql	OK	0	Conexión verificada	2026-11-21 19:05:29.209256-05
87d665dc-163b-4938-ba7f-5fb1a3c2f8a1	backend	OK	0	Aplicación disponible	2026-11-21 19:06:29.207078-05
9d8001fd-ae27-4762-859c-cc56a6e57c17	postgresql	OK	0	Conexión verificada	2026-11-21 19:06:29.207078-05
3740b2f8-44f1-4632-a88f-0b5b370f40c1	backend	OK	0	Aplicación disponible	2026-11-21 19:07:29.208854-05
2908b7bd-ff77-4785-904c-b07cd87c789b	postgresql	OK	0	Conexión verificada	2026-11-21 19:07:29.208854-05
dc88924a-2a89-44ee-ad97-933ddc6fdf51	backend	OK	0	Aplicación disponible	2026-11-21 19:08:29.197964-05
67eb6091-d0ae-4997-8f42-2e3195199e5c	postgresql	OK	0	Conexión verificada	2026-11-21 19:08:29.197964-05
36b73f64-7fb7-4671-a06f-ee155049dd84	backend	OK	0	Aplicación disponible	2026-11-21 19:09:29.218563-05
e5acc653-7e27-41a6-8842-0cef6f5d502b	postgresql	OK	0	Conexión verificada	2026-11-21 19:09:29.218563-05
16075d24-4df2-4999-b36c-1dc9562db17c	backend	OK	0	Aplicación disponible	2026-11-21 19:10:29.205135-05
90901329-5aee-4254-b511-c2d9418b9cbb	postgresql	OK	0	Conexión verificada	2026-11-21 19:10:29.205135-05
d2a88d0e-6a10-4508-b754-dd79309c82e7	backend	OK	0	Aplicación disponible	2026-11-21 19:11:29.203704-05
68b1e7e3-1414-4101-81c0-feb888397042	postgresql	OK	0	Conexión verificada	2026-11-21 19:11:29.203704-05
6f5df559-b187-4df5-b27b-55babd6c7126	backend	OK	0	Aplicación disponible	2026-11-21 19:12:29.198188-05
7448816a-1e04-4615-88af-493dc7acab5b	postgresql	OK	0	Conexión verificada	2026-11-21 19:12:29.198188-05
e18141ec-a798-4059-a503-7e518aa14029	backend	OK	0	Aplicación disponible	2026-11-21 19:13:29.631925-05
301cfd43-4b51-46e0-a406-a6a18e4ad257	postgresql	OK	0	Conexión verificada	2026-11-21 19:13:29.631925-05
2a4a88d5-f8c9-474d-aee6-cc1784960364	backend	OK	0	Aplicación disponible	2026-11-21 19:14:21.780707-05
9eb97601-0d46-4aea-8592-b77e498efd9a	postgresql	OK	0	Conexión verificada	2026-11-21 19:14:21.780707-05
cd1b8fd2-01f8-4cc8-b7f1-9e7df1b93780	backend	OK	0	Aplicación disponible	2026-11-21 19:14:29.629476-05
d7fc2843-fa39-458b-935b-9755b9e40e46	postgresql	OK	0	Conexión verificada	2026-11-21 19:14:29.629476-05
7194612b-1aff-40d0-a590-d29c34338321	backend	OK	0	Aplicación disponible	2026-11-21 19:15:29.210769-05
493194b5-dbb7-46e2-bd37-b8e336993365	postgresql	OK	0	Conexión verificada	2026-11-21 19:15:29.210769-05
38a59830-af23-44c0-9117-9859dd7c5385	backend	OK	0	Aplicación disponible	2026-11-21 19:16:29.209751-05
a6c7a447-5c29-4054-a61c-1d53a35086af	postgresql	OK	0	Conexión verificada	2026-11-21 19:16:29.209751-05
1fe04c6e-e66b-4d88-a6f7-4a4e78458778	backend	OK	0	Aplicación disponible	2026-11-21 19:17:29.195272-05
ee65dcd6-1c3a-493f-ba3b-81f125dc3a35	postgresql	OK	0	Conexión verificada	2026-11-21 19:17:29.195272-05
3b9b9437-96cb-4c37-b938-9e7deec1f9bf	backend	OK	0	Aplicación disponible	2026-11-21 19:18:29.640143-05
2622b8c2-e638-402b-b880-49905b1c0025	postgresql	OK	0	Conexión verificada	2026-11-21 19:18:29.640143-05
4520f1d8-1ac5-475c-8488-019028c50011	backend	OK	0	Aplicación disponible	2026-11-21 19:20:16.661705-05
e343a0e7-3f82-45f4-a327-4a657a9d62ed	postgresql	OK	0	Conexión verificada	2026-11-21 19:20:16.661705-05
3aa130e3-ef47-407b-85ff-ca21ec765071	backend	OK	1	Aplicación disponible	2026-11-21 19:21:16.653643-05
31af7bd3-8ad8-4cc3-aab0-bc77016e24f5	postgresql	OK	1	Conexión verificada	2026-11-21 19:21:16.653643-05
e1854a07-e251-4459-a2d6-a0e05fef38c9	backend	OK	0	Aplicación disponible	2026-11-21 19:22:16.63108-05
85e7fa54-d303-41ba-b301-d05a70e2b7a4	postgresql	OK	0	Conexión verificada	2026-11-21 19:22:16.63108-05
1fb5719d-3634-47ac-863d-ac2d416210ef	backend	OK	0	Aplicación disponible	2026-11-21 19:23:16.641717-05
498e115c-c68f-4cf1-a0d2-8d6107a3e069	postgresql	OK	0	Conexión verificada	2026-11-21 19:23:16.641717-05
1d703f36-f723-47ed-9be7-788d962810be	backend	OK	0	Aplicación disponible	2026-11-21 19:24:16.648821-05
baad2bf0-334e-4fcd-bb33-f081c90e0ebc	postgresql	OK	0	Conexión verificada	2026-11-21 19:24:16.648821-05
b9ec8afb-790d-4a25-b70e-00d5266e4129	backend	OK	0	Aplicación disponible	2026-11-21 19:25:16.643887-05
22f538ba-c923-4553-9f8d-2305eddff37f	postgresql	OK	0	Conexión verificada	2026-11-21 19:25:16.643887-05
723f7486-8fef-4a3e-b1fe-c7c46d68f42d	backend	OK	0	Aplicación disponible	2026-11-21 19:26:16.645518-05
c0c96a6c-f97c-46d3-ae97-45d450677fe2	postgresql	OK	0	Conexión verificada	2026-11-21 19:26:16.645518-05
9b11bb23-1ee5-4f42-a35e-1af366a13ff1	backend	OK	0	Aplicación disponible	2026-11-21 19:27:16.6517-05
aeb3e471-5965-42cb-94cd-f05d56ea4e7e	postgresql	OK	0	Conexión verificada	2026-11-21 19:27:16.6517-05
103d8da8-0c71-437a-beff-509c7ffa9c06	backend	OK	0	Aplicación disponible	2026-11-21 19:28:16.645062-05
19d05ff5-9f32-4705-8c97-625746c1f555	postgresql	OK	0	Conexión verificada	2026-11-21 19:28:16.645062-05
bab49e95-169c-462f-b21e-1e342d06cd9b	backend	OK	0	Aplicación disponible	2026-11-21 19:29:16.636084-05
763cb507-d75c-4f6f-aaf8-816f900bddf2	postgresql	OK	0	Conexión verificada	2026-11-21 19:29:16.636084-05
b91611b0-4670-43ad-bc41-5465a2a215c5	backend	OK	0	Aplicación disponible	2026-11-21 19:30:16.637666-05
e030a125-39d3-436e-81df-d2e0828f7a4f	postgresql	OK	0	Conexión verificada	2026-11-21 19:30:16.637666-05
3394b99f-d685-47ba-998a-e52eacf39112	backend	OK	0	Aplicación disponible	2026-11-21 19:31:16.644126-05
a19356dc-2353-4e0d-a784-2105cc52a500	postgresql	OK	0	Conexión verificada	2026-11-21 19:31:16.644126-05
ca9399f4-cd7b-44e4-b88f-988ea4b1a903	backend	OK	0	Aplicación disponible	2026-11-21 19:32:16.63313-05
433ca77b-d131-439a-a7a7-05d0d84ca7eb	postgresql	OK	0	Conexión verificada	2026-11-21 19:32:16.63313-05
0a0664d8-fad2-44ab-81ea-5dd29aab6d74	backend	OK	0	Aplicación disponible	2026-11-21 19:33:16.63896-05
0fb899f6-cac4-404b-a3f8-5fb45ffc9803	postgresql	OK	0	Conexión verificada	2026-11-21 19:33:16.63896-05
771c4727-f866-43b0-b3c6-9b3e50749f22	backend	OK	0	Aplicación disponible	2026-11-21 19:34:16.657674-05
611ad652-79dc-4d70-9c50-131c9e64b35c	postgresql	OK	0	Conexión verificada	2026-11-21 19:34:16.657674-05
84b1a374-8478-45d1-a24d-0c08a79d1586	backend	OK	0	Aplicación disponible	2026-11-21 19:35:16.637645-05
087b4434-a562-40af-b7d8-b88bb3e92a6a	postgresql	OK	0	Conexión verificada	2026-11-21 19:35:16.637645-05
1f4f467d-0c17-4537-b7c2-2e36bd9eef4e	backend	OK	0	Aplicación disponible	2026-11-21 19:36:16.642761-05
274c689f-bf00-45e1-bb8d-2662545cb5d5	postgresql	OK	0	Conexión verificada	2026-11-21 19:36:16.642761-05
56af2cec-b775-4d08-b95f-8950ee8b6c4b	backend	OK	0	Aplicación disponible	2026-11-21 19:37:16.639801-05
3ef7f5b3-724f-4537-8eea-422bd4b34585	postgresql	OK	0	Conexión verificada	2026-11-21 19:37:16.639801-05
2db80a5a-2130-4094-9d9c-60471271fd56	backend	OK	0	Aplicación disponible	2026-11-21 19:38:16.643405-05
5a9c13e5-7093-4d51-add1-ce63fbd2837d	postgresql	OK	0	Conexión verificada	2026-11-21 19:38:16.643405-05
6b1a7195-18c9-4562-bf13-cae2e0b4d2cc	backend	OK	0	Aplicación disponible	2026-11-21 19:39:16.645968-05
b98c0014-fb7a-41c7-9e4a-b1f20830c4da	postgresql	OK	0	Conexión verificada	2026-11-21 19:39:16.645968-05
493eff67-8bbc-4241-a219-b07c012adc93	backend	OK	0	Aplicación disponible	2026-11-21 19:40:16.658859-05
9b1accbb-d9a3-4d4b-b28c-d96833d0ced2	postgresql	OK	0	Conexión verificada	2026-11-21 19:40:16.658859-05
26f094b5-0f76-47cf-9d13-976a48cc79cc	backend	OK	0	Aplicación disponible	2026-11-21 19:41:16.631072-05
cf733eba-71ae-45d8-85df-b80929bcbcb2	postgresql	OK	0	Conexión verificada	2026-11-21 19:41:16.631072-05
dc983a11-864f-4579-9a27-b95906798fd6	backend	OK	0	Aplicación disponible	2026-11-21 19:42:16.640988-05
6946165b-8974-481a-9c2d-0a77f4297ae4	postgresql	OK	0	Conexión verificada	2026-11-21 19:42:16.640988-05
d80b8c68-35c0-4e2e-8776-cdf3a65f1fa4	backend	OK	0	Aplicación disponible	2026-11-21 19:43:16.636814-05
5940438c-a2bf-49e5-bf9a-58e71c20d95f	postgresql	OK	0	Conexión verificada	2026-11-21 19:43:16.636814-05
ff572ef0-efe8-47e3-b7e7-ba94b873e3ca	backend	OK	0	Aplicación disponible	2026-11-21 19:44:16.649717-05
caf85640-5776-4cb1-8ebf-d2c794fa246f	postgresql	OK	0	Conexión verificada	2026-11-21 19:44:16.649717-05
d57324ea-3e8d-4fae-930b-3bec9c362f5b	backend	OK	0	Aplicación disponible	2026-11-21 19:45:16.638991-05
5fc989dc-1c63-4788-b0f0-404f67e6f352	postgresql	OK	0	Conexión verificada	2026-11-21 19:45:16.638991-05
1d7ab909-773b-4087-88fd-7053a0352d48	backend	OK	0	Aplicación disponible	2026-11-21 19:46:16.629656-05
32edab5c-4945-4a5d-a9b7-a1ed6e97b93a	postgresql	OK	0	Conexión verificada	2026-11-21 19:46:16.629656-05
83a9946d-0ef9-472d-bf12-4357bb9d6fb3	backend	OK	0	Aplicación disponible	2026-11-21 19:47:16.647749-05
cb3d351b-d9b2-4d23-96fc-00c85c1654f9	postgresql	OK	0	Conexión verificada	2026-11-21 19:47:16.647749-05
890cbd17-f135-4ef9-a550-f2a217d73f57	backend	OK	0	Aplicación disponible	2026-11-21 19:48:16.636385-05
99515f9b-0a9f-461e-855c-3bf76618371f	postgresql	OK	0	Conexión verificada	2026-11-21 19:48:16.636385-05
80d1d0de-3e4d-4f41-a953-534568aeb43a	backend	OK	0	Aplicación disponible	2026-11-21 19:49:16.65837-05
aa5d5ed7-f111-4b0a-b896-042e05846ec0	postgresql	OK	0	Conexión verificada	2026-11-21 19:49:16.65837-05
6efcff53-468a-4f98-bae7-d7f5302ce058	backend	OK	0	Aplicación disponible	2026-11-21 19:50:16.645496-05
22fcb8cf-740d-4087-9f9f-a99e1a3552eb	postgresql	OK	0	Conexión verificada	2026-11-21 19:50:16.645496-05
67dfd3dd-036a-417d-8a30-914b4d9da47e	backend	OK	0	Aplicación disponible	2026-11-21 19:51:16.649652-05
649b9aca-7f14-4390-9caf-6089858c0268	postgresql	OK	0	Conexión verificada	2026-11-21 19:51:16.649652-05
fc2c3beb-8a0a-4f1a-b9c0-47f86fac2452	backend	OK	0	Aplicación disponible	2026-11-21 19:52:16.630095-05
fdba4f2c-a91d-459c-9f99-f236f081c9c4	postgresql	OK	0	Conexión verificada	2026-11-21 19:52:16.630095-05
52c0293d-1737-42a8-888e-e41068a2ac68	backend	OK	0	Aplicación disponible	2026-11-21 19:53:16.643436-05
9b063d99-0f3d-4e05-be4e-dcab65329dfb	postgresql	OK	0	Conexión verificada	2026-11-21 19:53:16.643436-05
765fca50-cfa8-45c5-8105-4a10ac15215d	backend	OK	0	Aplicación disponible	2026-11-21 19:54:16.650355-05
fb67f354-5200-4708-964d-da146b61d34e	postgresql	OK	0	Conexión verificada	2026-11-21 19:54:16.650355-05
a30faf1c-027d-4320-a877-984be4bb865a	backend	OK	0	Aplicación disponible	2026-11-21 19:55:16.634785-05
a4fbc9e4-6555-45fa-bbb5-3738bbf5ce23	postgresql	OK	0	Conexión verificada	2026-11-21 19:55:16.634785-05
bd7fef7b-c4bb-46c5-ada6-18e0c8aac2cb	backend	OK	0	Aplicación disponible	2026-11-21 19:56:16.647497-05
f7cec0b3-94ab-4a72-8a3d-d5d088cc6232	postgresql	OK	0	Conexión verificada	2026-11-21 19:56:16.647497-05
4a40c7bd-1e91-4204-9be7-55109ddfccb2	backend	OK	0	Aplicación disponible	2026-11-21 19:57:16.653782-05
ccb3f442-14e0-4587-8c1b-21892c546fba	postgresql	OK	0	Conexión verificada	2026-11-21 19:57:16.653782-05
730b1aad-401b-4139-8975-bf07f4013b41	backend	OK	0	Aplicación disponible	2026-11-21 19:58:16.640727-05
cebe4563-64a8-4e4b-b775-187fc5e838c7	postgresql	OK	0	Conexión verificada	2026-11-21 19:58:16.640727-05
196c0551-3f75-4ae0-92f0-289465165301	backend	OK	0	Aplicación disponible	2026-11-21 19:59:16.645937-05
aac534c7-de91-4e21-a327-80916a6660f7	postgresql	OK	0	Conexión verificada	2026-11-21 19:59:16.645937-05
baac8f6d-b604-4b16-8f04-2eb49aff1f9a	backend	OK	0	Aplicación disponible	2026-11-21 20:00:16.64835-05
bbde235c-7639-4650-be83-cffde3bcc17b	postgresql	OK	0	Conexión verificada	2026-11-21 20:00:16.64835-05
7078932d-74c5-4689-84a3-e71239f32bb9	backend	OK	1	Aplicación disponible	2026-11-23 23:32:22.786639-05
e996939d-0d3c-4f94-b95d-1bb3b6bab213	postgresql	OK	1	Conexión verificada	2026-11-23 23:32:22.786639-05
3f0919f9-897b-4f8e-88f9-81a581c2b355	backend	OK	0	Aplicación disponible	2026-11-23 23:33:22.73367-05
863ef20c-0cbb-491f-b2c8-d18e7f28d519	postgresql	OK	0	Conexión verificada	2026-11-23 23:33:22.73367-05
cc589966-e3f3-48c5-b926-0863d7d05f23	backend	OK	1	Aplicación disponible	2026-11-23 23:33:39.835128-05
46ac739f-6d7c-4ceb-a02e-86548a429889	postgresql	OK	1	Conexión verificada	2026-11-23 23:33:39.835128-05
2ff59fe4-72f3-4be3-bcaf-d5ba9db651fc	backend	OK	0	Aplicación disponible	2026-11-23 23:34:23.226248-05
17390b1e-bf22-4033-a69f-9048b6b31c8c	postgresql	OK	0	Conexión verificada	2026-11-23 23:34:23.226248-05
f9c6dccc-b7cd-4144-acf7-5ebee0dcd9a8	backend	OK	0	Aplicación disponible	2026-11-23 23:35:23.223311-05
fa8b6105-7ee1-44e6-94bf-2f1a2e94a842	postgresql	OK	0	Conexión verificada	2026-11-23 23:35:23.223311-05
79c72530-efc6-44ef-86e6-5d7c9e896072	backend	OK	0	Aplicación disponible	2026-11-23 23:36:23.232061-05
65b2c6a8-1a15-4823-a818-7bb3b2bd72f1	postgresql	OK	0	Conexión verificada	2026-11-23 23:36:23.232061-05
c3158fdd-8a21-4e7a-a94b-48b70f0b2e82	backend	OK	0	Aplicación disponible	2026-11-23 23:37:23.232151-05
ee422cac-fccc-40fa-899a-43f6811424b2	postgresql	OK	0	Conexión verificada	2026-11-23 23:37:23.232151-05
f095f137-ddcf-4c1e-91a7-62ea244f909d	backend	OK	0	Aplicación disponible	2026-11-23 23:37:59.330201-05
f0e735bc-f695-426a-abca-ca31093f2918	postgresql	OK	0	Conexión verificada	2026-11-23 23:37:59.330201-05
4ce1396f-1ef7-4d70-a488-0fa158832564	backend	OK	0	Aplicación disponible	2026-11-23 23:39:00.222047-05
3109587a-8bb7-41ad-a0d9-d3e3002f6ea8	postgresql	OK	0	Conexión verificada	2026-11-23 23:39:00.222047-05
559b55ac-31ad-4368-bb8f-8f018fea4a02	backend	OK	0	Aplicación disponible	2026-11-23 23:40:00.223751-05
006cf807-e0e1-4c31-97cb-c56d01325543	postgresql	OK	0	Conexión verificada	2026-11-23 23:40:00.223751-05
dc3d7915-618a-482b-a05e-f250ad1a75cf	backend	OK	0	Aplicación disponible	2026-11-23 23:40:59.315955-05
f724d7a1-5be1-48c9-89d2-9d738d7f9ecc	postgresql	OK	0	Conexión verificada	2026-11-23 23:40:59.315955-05
db9d269d-621e-4aaa-bffc-fe114c3b14ac	backend	OK	0	Aplicación disponible	2026-11-23 23:42:00.233457-05
080852a7-0be4-4e80-ae29-c6c61bb16de1	postgresql	OK	0	Conexión verificada	2026-11-23 23:42:00.233457-05
d364c451-50c0-4a3b-94aa-42bdfbbfcf71	backend	OK	0	Aplicación disponible	2026-11-23 23:43:00.223673-05
da973e9f-f6da-4397-a6d9-67471b722ef6	postgresql	OK	0	Conexión verificada	2026-11-23 23:43:00.223673-05
efb5ec51-f354-4adc-84c0-b050069a7974	backend	OK	0	Aplicación disponible	2026-11-23 23:47:00.223836-05
b0df39cc-d134-44b3-a50f-cd9118ff3f2f	postgresql	OK	0	Conexión verificada	2026-11-23 23:47:00.223836-05
1cdf5e1f-61bb-494e-a5a5-eff9c4372b44	backend	OK	0	Aplicación disponible	2026-11-23 23:50:23.776167-05
ffdafdc7-6d72-47d4-9ed4-10b4999ef94b	postgresql	OK	0	Conexión verificada	2026-11-23 23:50:23.776167-05
5a5fadaa-48b7-4525-b715-2a6c87fd5971	backend	OK	0	Aplicación disponible	2026-11-23 23:51:18.822159-05
6524c895-93be-43c3-a0f2-8b8a616542c4	postgresql	OK	0	Conexión verificada	2026-11-23 23:51:18.822159-05
ad08fee9-03a8-4038-867b-ecadaca0054c	backend	OK	0	Aplicación disponible	2026-11-23 23:53:48.936107-05
048ec576-aa36-46d5-8f18-c00524b9222d	postgresql	OK	0	Conexión verificada	2026-11-23 23:53:48.936107-05
340f58d7-46b5-457b-b7e7-260fcd74615b	backend	OK	0	Aplicación disponible	2026-11-23 23:44:00.226384-05
a44f4f4e-9271-4b76-821d-7275624fe103	postgresql	OK	0	Conexión verificada	2026-11-23 23:44:00.226384-05
f907780e-c7ef-4e7d-9c43-14a19220bacd	backend	OK	0	Aplicación disponible	2026-11-23 23:46:00.288024-05
5a09858e-a96e-468f-8529-4931ca1e9c5d	postgresql	OK	0	Conexión verificada	2026-11-23 23:46:00.288024-05
8f0893f0-5917-4f94-a5ea-56161b69c3a8	backend	OK	0	Aplicación disponible	2026-11-23 23:49:00.228367-05
f461bb8a-d07c-4fcc-8c83-5f1bcb6934d4	postgresql	OK	0	Conexión verificada	2026-11-23 23:49:00.228367-05
a1219716-2314-474e-9bad-dede20d0749f	backend	OK	0	Aplicación disponible	2026-11-23 23:49:23.780727-05
71dda58b-94b0-433c-965b-513d44d58b1d	postgresql	OK	0	Conexión verificada	2026-11-23 23:49:23.780727-05
14306d01-98d1-4098-a13b-3be290bd8649	backend	OK	0	Aplicación disponible	2026-11-23 23:54:31.266497-05
8a47b345-946d-415d-977e-40277dd311ca	postgresql	OK	0	Conexión verificada	2026-11-23 23:54:31.266497-05
588f873e-5017-4032-8e0e-4a9320f56eb2	backend	OK	0	Aplicación disponible	2026-11-23 23:56:32.226747-05
896118ae-e9b6-442f-b095-c4e3b060670c	postgresql	OK	0	Conexión verificada	2026-11-23 23:56:32.226747-05
1f6342fd-8aca-4377-9b46-3eecf63d333a	backend	OK	0	Aplicación disponible	2026-11-23 23:45:00.223712-05
447b2868-ddaf-4f33-8b48-4d5886663465	postgresql	OK	0	Conexión verificada	2026-11-23 23:45:00.223712-05
358cb035-661e-417e-bfb3-dc8b033a2040	backend	OK	0	Aplicación disponible	2026-11-23 23:48:00.229794-05
303262c4-841e-48d7-b96d-63de72e27306	postgresql	OK	0	Conexión verificada	2026-11-23 23:48:00.229794-05
b6cc18b7-96e9-4bfa-ad4f-18b283bea2a6	backend	OK	0	Aplicación disponible	2026-11-23 23:49:57.924402-05
d3428762-611a-4526-8018-3dad114ffe97	postgresql	OK	0	Conexión verificada	2026-11-23 23:49:57.924402-05
0c0b4002-818e-4ee8-94a8-755e4ab443ce	backend	OK	0	Aplicación disponible	2026-11-23 23:52:18.794681-05
0c243937-2e6d-4162-94c4-328c41c6ce9b	postgresql	OK	0	Conexión verificada	2026-11-23 23:52:18.794681-05
38d5f5ca-92db-4751-b3e5-2f5e47fe2f81	backend	OK	0	Aplicación disponible	2026-11-23 23:55:32.227441-05
bad0cd28-3f2b-4e03-a208-4dc8d867db9c	postgresql	OK	0	Conexión verificada	2026-11-23 23:55:32.227441-05
b541189a-8972-4003-b2c2-e010f87c4f8b	backend	OK	0	Aplicación disponible	2026-11-23 23:57:32.316209-05
0737f680-db48-4b48-a7fd-e1b21960f144	postgresql	OK	0	Conexión verificada	2026-11-23 23:57:32.316209-05
a619684c-dcc9-4e83-9dc5-ba763815bf9d	backend	OK	0	Aplicación disponible	2026-11-23 23:58:32.22101-05
50515bec-3332-4c13-88f6-f7ad350c0736	postgresql	OK	0	Conexión verificada	2026-11-23 23:58:32.22101-05
89b9ff5b-7b2a-4494-842d-17d746c045f3	backend	OK	0	Aplicación disponible	2026-11-23 23:59:32.225978-05
71bf132b-70b1-40c8-96fc-934a8c08cffb	postgresql	OK	0	Conexión verificada	2026-11-23 23:59:32.225978-05
8a1c0756-fe71-43c2-9ee3-9264218c9d90	backend	OK	0	Aplicación disponible	2026-11-24 00:00:32.223329-05
8a0c4e22-323d-40f6-b678-06f13d0c0930	postgresql	OK	0	Conexión verificada	2026-11-24 00:00:32.223329-05
54fddad1-3430-4df7-b8d1-29b5ad07de86	backend	OK	0	Aplicación disponible	2026-11-24 00:02:01.238153-05
e8dc3459-2126-4849-8f25-4574b464d1c0	postgresql	OK	0	Conexión verificada	2026-11-24 00:02:01.238153-05
06a41cc9-18d0-4a9c-a2e5-e0d8544c3f14	backend	OK	0	Aplicación disponible	2026-11-24 00:03:01.217383-05
4e5ce246-3f9f-4f40-be82-35b6518b60b4	postgresql	OK	0	Conexión verificada	2026-11-24 00:03:01.217383-05
7a21b8f6-26b8-4077-93a7-9e43f12f0391	backend	OK	0	Aplicación disponible	2026-11-24 00:04:01.226848-05
866fa9a5-62e1-4bac-8963-4650003d4601	postgresql	OK	0	Conexión verificada	2026-11-24 00:04:01.226848-05
6f6bd412-6357-4339-acec-9429c5ebdbb6	backend	OK	0	Aplicación disponible	2026-11-24 00:05:01.22653-05
65077ecb-0c2e-4768-a671-c641547fddda	postgresql	OK	0	Conexión verificada	2026-11-24 00:05:01.22653-05
dbf9b7c1-9220-4232-861f-250ff8d5dccb	backend	OK	0	Aplicación disponible	2026-11-24 00:06:01.224156-05
c4613368-04ec-4bab-b159-033326d05143	postgresql	OK	0	Conexión verificada	2026-11-24 00:06:01.224156-05
8a907569-b71b-4248-9b10-1c9045a68557	backend	OK	0	Aplicación disponible	2026-11-24 00:07:01.22475-05
12a82f78-ac2f-4601-aa0e-8fcf0af1dc03	postgresql	OK	0	Conexión verificada	2026-11-24 00:07:01.22475-05
012982ea-9de6-4f38-b699-bb13476ccda8	backend	OK	0	Aplicación disponible	2026-11-24 00:08:01.22688-05
856d2d8d-3621-4c08-bd91-388bb707727c	postgresql	OK	0	Conexión verificada	2026-11-24 00:08:01.22688-05
3dc86ae9-274d-4e45-8bb1-84a364a52c1a	backend	OK	0	Aplicación disponible	2026-11-24 00:09:01.221619-05
00be801b-e11f-430a-bd60-7bb1e55be1a8	postgresql	OK	0	Conexión verificada	2026-11-24 00:09:01.221619-05
6ffd213e-1af4-4f70-88f7-c50a30178d43	backend	OK	0	Aplicación disponible	2026-11-24 00:10:01.233707-05
6ccc4b7c-457a-4e1b-876a-1e35d460e56f	postgresql	OK	0	Conexión verificada	2026-11-24 00:10:01.233707-05
24c7673c-66e7-4202-a3b7-152b5d06d667	backend	OK	0	Aplicación disponible	2026-11-24 00:11:01.215485-05
0d5c3967-c9e7-49d1-9e70-95d39822e215	postgresql	OK	0	Conexión verificada	2026-11-24 00:11:01.215485-05
ebba0c9c-245b-47d9-b383-6d70d12aab70	backend	OK	0	Aplicación disponible	2026-11-24 00:12:01.228358-05
a27044d0-c78b-43fb-8526-b7708cb7dabc	postgresql	OK	0	Conexión verificada	2026-11-24 00:12:01.228358-05
707e1c03-080a-40e2-8287-d414b74790ef	backend	OK	0	Aplicación disponible	2026-11-24 00:13:01.23158-05
89b7eeac-77cc-40c4-a722-f860cd246dbc	postgresql	OK	0	Conexión verificada	2026-11-24 00:13:01.23158-05
797f13a0-048c-4740-86f0-ca09d7a09fec	backend	OK	1	Aplicación disponible	2026-11-24 00:14:01.233489-05
a42f9a76-d5ef-4d55-a1b2-69eb9bc8e91d	postgresql	OK	1	Conexión verificada	2026-11-24 00:14:01.233489-05
5d62b2b0-9568-4ca4-b475-68f491accdaf	backend	OK	0	Aplicación disponible	2026-11-24 00:15:01.225332-05
512b245b-f56b-4b13-9639-56bd940cb014	postgresql	OK	0	Conexión verificada	2026-11-24 00:15:01.225332-05
2742ca7f-61a6-4c8a-886d-72a99e96bef8	backend	OK	0	Aplicación disponible	2026-11-24 00:16:01.234073-05
12eba69c-9c15-4364-a9c5-3f096917795e	postgresql	OK	0	Conexión verificada	2026-11-24 00:16:01.234073-05
8765dc25-c7dd-4eda-a436-6d2dea543cf0	backend	OK	0	Aplicación disponible	2026-11-24 00:17:01.21935-05
8a69f663-528d-49e5-b9ea-c56c27661f6c	postgresql	OK	0	Conexión verificada	2026-11-24 00:17:01.21935-05
fe3726bd-19c7-4227-a5ba-762bcc2627cc	backend	OK	0	Aplicación disponible	2026-11-24 00:18:01.223889-05
6f88789d-9166-4883-8bc6-e910e827a9c7	postgresql	OK	0	Conexión verificada	2026-11-24 00:18:01.223889-05
6f8e3bbc-3fae-45d3-8f0e-9f61cbf96f97	backend	OK	0	Aplicación disponible	2026-11-24 00:19:01.228404-05
71299638-866b-4184-9f8c-912f31740783	postgresql	OK	0	Conexión verificada	2026-11-24 00:19:01.228404-05
f8ba0729-4557-41b0-9899-aa4bf879826e	backend	OK	0	Aplicación disponible	2026-11-24 00:20:01.234222-05
4875e09e-dd32-44bf-b8de-fbd12425f2a2	postgresql	OK	0	Conexión verificada	2026-11-24 00:20:01.234222-05
df6b1042-1014-4d31-96ce-fdc048e500dc	backend	OK	0	Aplicación disponible	2026-11-24 00:21:01.219915-05
50eae68d-fb8f-4100-8cdb-52a9335053cc	postgresql	OK	0	Conexión verificada	2026-11-24 00:21:01.219915-05
8aa9ba1b-3e82-440c-9709-b86e76c54104	backend	OK	0	Aplicación disponible	2026-11-24 00:22:01.219871-05
18136cae-d62d-43e6-9c0f-e3becf058974	postgresql	OK	0	Conexión verificada	2026-11-24 00:22:01.219871-05
1a8bbee5-f98e-4ba2-86bb-1d3c511502db	backend	OK	0	Aplicación disponible	2026-11-24 00:23:04.970152-05
e45017d0-a97f-431d-aec0-560320b8bf4b	postgresql	OK	0	Conexión verificada	2026-11-24 00:23:04.970152-05
2e8178d5-29a5-4a6e-a057-04cb4deca162	backend	OK	0	Aplicación disponible	2026-11-24 00:24:04.882245-05
de9925f1-e2ea-4d08-95fa-6adc7b19388e	postgresql	OK	0	Conexión verificada	2026-11-24 00:24:04.882245-05
dfcfec1b-882f-4cd5-82ad-8a376289b912	backend	OK	0	Aplicación disponible	2026-11-24 00:25:04.860363-05
746b90c9-8206-4bde-a7e3-06ea5199aa1b	postgresql	OK	0	Conexión verificada	2026-11-24 00:25:04.860363-05
419acb2e-5622-4708-9633-ad3e2aa86048	backend	OK	0	Aplicación disponible	2026-11-24 00:26:05.226602-05
608059c8-36b8-47ea-8341-5df5005c2f5c	postgresql	OK	0	Conexión verificada	2026-11-24 00:26:05.226602-05
c9c1e93f-97c6-48ac-9d14-8b63f8e49823	backend	OK	0	Aplicación disponible	2026-11-24 00:27:05.217512-05
018164e7-704a-4f9b-8dc3-973c27f7a02e	postgresql	OK	0	Conexión verificada	2026-11-24 00:27:05.217512-05
5b6200d9-bf5c-4c30-abd4-078293edc23c	backend	OK	0	Aplicación disponible	2026-11-24 00:28:05.221009-05
b60b6527-c6d4-48cc-b681-1de5d076cad2	postgresql	OK	0	Conexión verificada	2026-11-24 00:28:05.221009-05
d86a71ff-c8e6-47e6-a0c3-e3491175b3a6	backend	OK	0	Aplicación disponible	2026-11-24 00:28:16.549237-05
223a1fba-ae4d-445b-9a1f-dcc55f6ef109	postgresql	OK	0	Conexión verificada	2026-11-24 00:28:16.549237-05
a679ef13-5f5b-4bb4-a25b-22273e4697ab	backend	OK	0	Aplicación disponible	2026-11-24 00:29:17.222567-05
38383316-cb7d-4e1f-bc6a-6967496ff64b	postgresql	OK	0	Conexión verificada	2026-11-24 00:29:17.222567-05
fde86af1-1149-4075-948c-d0d75188d46d	backend	OK	0	Aplicación disponible	2026-11-24 00:30:17.217351-05
aa6fa10d-4dab-488c-be7e-dc348a4e6884	postgresql	OK	0	Conexión verificada	2026-11-24 00:30:17.217351-05
6d8bc777-f9ad-4ccb-bbd6-c00ee7297b37	backend	OK	0	Aplicación disponible	2026-11-24 00:31:17.221934-05
dbe15a7f-c283-4638-8d85-fa60b0c7be7c	postgresql	OK	0	Conexión verificada	2026-11-24 00:31:17.221934-05
0425f142-35ec-4853-9beb-0bf36ed60cd5	backend	OK	0	Aplicación disponible	2026-11-24 00:32:17.216646-05
40cf6af1-42b9-4bdd-90a0-d0e918e3cf3e	postgresql	OK	0	Conexión verificada	2026-11-24 00:32:17.216646-05
891ef52a-dd48-41e2-8ad6-6273831e0b8e	backend	OK	0	Aplicación disponible	2026-11-24 00:33:17.229747-05
50bdb9c3-de56-4a7e-ba74-c3e8653e2895	postgresql	OK	0	Conexión verificada	2026-11-24 00:33:17.229747-05
46115eff-a5ed-4283-a0eb-e1c3367df09d	backend	OK	0	Aplicación disponible	2026-11-24 00:34:17.219032-05
28c482da-37c4-479a-a949-8ae6fba8d542	postgresql	OK	0	Conexión verificada	2026-11-24 00:34:17.219032-05
4b04e591-134b-401e-9ae7-50647815b6ae	backend	OK	0	Aplicación disponible	2026-11-24 00:36:01.223506-05
fe2cb78f-461f-4173-bdda-2c735bb62bbc	postgresql	OK	0	Conexión verificada	2026-11-24 00:36:01.223506-05
4f3e608c-2d4b-42ff-a577-29d21bcf13b2	backend	OK	0	Aplicación disponible	2026-11-24 00:37:01.237236-05
140b0294-2a37-4a05-92b7-81131c2b7047	postgresql	OK	0	Conexión verificada	2026-11-24 00:37:01.237236-05
85958255-0816-4cd3-b583-17b8091ebc3f	backend	OK	0	Aplicación disponible	2026-11-24 00:38:01.217116-05
2cf422fe-17d3-4b80-99b2-4751832e6526	postgresql	OK	0	Conexión verificada	2026-11-24 00:38:01.217116-05
e7fb25fa-5c8e-4c4c-8233-380d299da531	backend	OK	0	Aplicación disponible	2026-11-24 00:39:01.231165-05
16689fce-fbe7-4ff2-91f6-e72afe201624	postgresql	OK	0	Conexión verificada	2026-11-24 00:39:01.231165-05
5b5db8b7-0136-438d-bb6d-685d91a51f74	backend	OK	0	Aplicación disponible	2026-11-24 00:41:01.232375-05
973ef16a-066c-450f-8ef6-e68a6cc17b55	postgresql	OK	0	Conexión verificada	2026-11-24 00:41:01.232375-05
28cceebc-b3da-4ccd-8ec7-4a5c5b39a4c2	backend	OK	0	Aplicación disponible	2026-11-24 00:42:01.227287-05
a1548c39-3467-434e-b2c8-d563d18a5f0f	postgresql	OK	0	Conexión verificada	2026-11-24 00:42:01.227287-05
6d5c79e8-d312-49b3-a01c-e56772692543	backend	OK	0	Aplicación disponible	2026-11-24 00:42:16.557881-05
3e1f24b1-0a01-4bc8-b62e-fc3e0e4bad48	postgresql	OK	0	Conexión verificada	2026-11-24 00:42:16.557881-05
bfe1e2b1-3fc1-4060-bebe-355c923fbdb9	backend	OK	0	Aplicación disponible	2026-11-24 00:40:01.239849-05
c31782c5-2ac9-48be-8369-4475bbe96069	postgresql	OK	0	Conexión verificada	2026-11-24 00:40:01.239849-05
8fbb66fe-0ffc-4d68-969a-042f030e8dac	backend	OK	0	Aplicación disponible	2026-11-24 00:43:16.552258-05
49419748-4d0f-437f-bf32-bed47f98404e	postgresql	OK	0	Conexión verificada	2026-11-24 00:43:16.552258-05
\.


--
-- TOC entry 5368 (class 0 OID 17235)
-- Dependencies: 231
-- Data for Name: order_status_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_status_history (id, order_id, from_status, to_status, changed_by, reason, changed_at) FROM stdin;
bb99a932-0534-4c33-8f4b-36849457a5c6	4eac7b12-84dc-4176-bc51-2e1807855335	\N	PENDIENTE	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	Registro de orden	2026-10-18 13:46:29.937956-05
7d63046d-3405-49f0-98ab-4897dd82fe76	4eac7b12-84dc-4176-bc51-2e1807855335	PENDIENTE	EN_ATENCION	3b5b21e1-2d91-4a99-8eb6-37f67b06522b		2026-10-18 17:05:25.087783-05
52de6261-66bd-4c66-8d6b-002bd64a84c5	4eac7b12-84dc-4176-bc51-2e1807855335	EN_ATENCION	FINALIZADA	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	Atención técnica finalizada	2026-10-18 17:47:12.522959-05
9b9e9d9c-c9a6-4843-b7ab-e76d9dc91914	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	\N	PENDIENTE	ed8565ad-31a6-4bf7-bfaa-518602317906	Registro de orden	2026-11-02 23:43:36.774227-05
e8675138-8709-432f-a802-80c5478694fa	7b4a854d-825e-46e4-b401-9d6fad370dc3	\N	PENDIENTE	ed8565ad-31a6-4bf7-bfaa-518602317906	Registro de orden	2026-11-06 22:08:42.756415-05
bec4e671-d20a-489e-98ba-a67557777c45	e90e9fde-5f78-464d-9ae3-e8236935baa1	\N	PENDIENTE	ed8565ad-31a6-4bf7-bfaa-518602317906	Registro de orden	2026-11-06 22:36:31.215789-05
8bb2405a-e341-4b85-a3bb-70e55c402770	7b4a854d-825e-46e4-b401-9d6fad370dc3	PENDIENTE	EN_ATENCION	3b5b21e1-2d91-4a99-8eb6-37f67b06522b		2026-11-06 23:00:23.292237-05
f41cabe6-1f3b-4799-9a0a-ac939663e512	7b4a854d-825e-46e4-b401-9d6fad370dc3	EN_ATENCION	FINALIZADA	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	Atención técnica finalizada	2026-11-06 23:05:15.065028-05
53e4ddb3-2223-4e80-b7f2-da4803243ee9	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	PENDIENTE	EN_ATENCION	b31dd59d-f191-48a3-9970-7e3803b86707		2026-11-07 19:28:25.909213-05
6fed1d8c-4686-442c-8e93-7388a89b317c	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	EN_ATENCION	FINALIZADA	b31dd59d-f191-48a3-9970-7e3803b86707	Atención técnica finalizada	2026-11-07 19:29:37.747092-05
\.


--
-- TOC entry 5364 (class 0 OID 17124)
-- Dependencies: 227
-- Data for Name: order_status_transitions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_status_transitions (from_status, to_status) FROM stdin;
PENDIENTE	ASIGNADA
PENDIENTE	CANCELADA
ASIGNADA	EN_ATENCION
ASIGNADA	CANCELADA
EN_ATENCION	FINALIZADA
EN_ATENCION	CANCELADA
FINALIZADA	EN_ATENCION
FINALIZADA	CERRADA
PENDIENTE	EN_ATENCION
\.


--
-- TOC entry 5363 (class 0 OID 17113)
-- Dependencies: 226
-- Data for Name: order_statuses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_statuses (code, name, terminal) FROM stdin;
PENDIENTE	Pendiente	f
ASIGNADA	Asignada	f
EN_ATENCION	En atención	f
FINALIZADA	Finalizada	f
CERRADA	Cerrada	t
CANCELADA	Cancelada	t
\.


--
-- TOC entry 5358 (class 0 OID 16991)
-- Dependencies: 221
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.permissions (code, description) FROM stdin;
dashboard	Ver dashboard
clients	Gestionar clientes
equipment	Gestionar equipos
orders	Gestionar órdenes
assign-technicians	Asignar técnicos
assigned-orders	Consultar órdenes asignadas
attend-orders	Atender órdenes
ai-prediagnosis	Usar prediagnóstico IA
service-tracking	Consultar seguimiento
users	Gestionar usuarios
settings	Configuración
manage-quotations	Gestionar cotizaciones
manage-deliveries	Gestionar entregas
reports-export	Exportar reportes
service-indicators	Consultar indicadores
\.


--
-- TOC entry 5376 (class 0 OID 32800)
-- Dependencies: 240
-- Data for Name: quotation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.quotation (id, order_id, description, status, total, created_by, decided_by, decided_at, decision_observations, created_at, updated_at) FROM stdin;
2e9edc32-851d-4795-99d5-b2b06742456b	e90e9fde-5f78-464d-9ae3-e8236935baa1	asd	RECHAZADA	250.00	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	2026-11-24 00:23:51.142895-05		2026-11-23 23:41:18.951609-05	2026-11-24 00:23:51.142895-05
4cfe5bb5-a2a3-4b6f-a592-fe4e450d4a9c	e90e9fde-5f78-464d-9ae3-e8236935baa1	sadsd	AUTORIZADA	50.00	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	2026-11-24 00:43:04.482029-05		2026-11-24 00:43:01.952969-05	2026-11-24 00:43:04.482029-05
\.


--
-- TOC entry 5377 (class 0 OID 32843)
-- Dependencies: 241
-- Data for Name: quotation_item; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.quotation_item (id, quotation_id, item_description, item_type, quantity, unit_price, subtotal) FROM stdin;
10b9e112-8173-480c-b677-1026ef5c5ba3	2e9edc32-851d-4795-99d5-b2b06742456b	asds	REPUESTO	1.000	250.00	250.00
1705f8ff-b059-428d-9fbf-167658717673	4cfe5bb5-a2a3-4b6f-a592-fe4e450d4a9c	asdad	SERVICIO	1.000	50.00	50.00
\.


--
-- TOC entry 5359 (class 0 OID 16998)
-- Dependencies: 222
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.role_permissions (role_code, permission_code) FROM stdin;
ADMINISTRADOR	dashboard
ADMINISTRADOR	clients
ADMINISTRADOR	equipment
ADMINISTRADOR	orders
ADMINISTRADOR	assign-technicians
ADMINISTRADOR	assigned-orders
ADMINISTRADOR	attend-orders
ADMINISTRADOR	ai-prediagnosis
ADMINISTRADOR	service-tracking
ADMINISTRADOR	service-indicators
ADMINISTRADOR	users
ADMINISTRADOR	settings
PERSONAL DE ATENCIÓN	dashboard
PERSONAL DE ATENCIÓN	clients
PERSONAL DE ATENCIÓN	equipment
PERSONAL DE ATENCIÓN	orders
PERSONAL DE ATENCIÓN	service-tracking
TÉCNICO	dashboard
TÉCNICO	assigned-orders
TÉCNICO	attend-orders
TÉCNICO	ai-prediagnosis
TÉCNICO	service-tracking
PERSONAL DE ATENCIÓN	assign-technicians
GERENTE	dashboard
GERENTE	orders
GERENTE	service-tracking
GERENTE	service-indicators
GERENTE	reports-export
GERENTE	manage-deliveries
GERENTE	manage-quotations
ADMINISTRADOR	manage-deliveries
ADMINISTRADOR	manage-quotations
ADMINISTRADOR	reports-export
PERSONAL DE ATENCIÓN	manage-deliveries
PERSONAL DE ATENCIÓN	manage-quotations
\.


--
-- TOC entry 5357 (class 0 OID 16982)
-- Dependencies: 220
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (code, name) FROM stdin;
ADMINISTRADOR	Administrador
PERSONAL DE ATENCIÓN	Personal de Atención
TÉCNICO	Técnico
GERENTE	Gerente
\.


--
-- TOC entry 5366 (class 0 OID 17143)
-- Dependencies: 229
-- Data for Name: service_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.service_orders (id, number, equipment_id, client_id, received_by, reported_problem, intake_condition, intake_accessories, status_code, priority, estimated_delivery, closed_at, closure_summary, created_at, updated_at, received_at, finalized_at, finalized_by) FROM stdin;
4eac7b12-84dc-4176-bc51-2e1807855335	1	a2a73b0b-e9ec-42d8-b27b-408ad4570df8	93fecc7d-8d2b-4764-9f02-cb0a07c2e986	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	Error con el sistema, pantallazo azul con codigo de disco dañando	se registra la laptop con pantalla azul		FINALIZADA	NORMAL	\N	\N	\N	2026-10-18 13:46:29.937956-05	2026-10-18 17:47:12.522959-05	2026-10-18	2026-10-18 17:47:12.522959-05	3b5b21e1-2d91-4a99-8eb6-37f67b06522b
e90e9fde-5f78-464d-9ae3-e8236935baa1	4	686f9b48-1025-4319-ad41-f04f79a1c609	e96aea1a-4117-4cc7-a881-6ab2a3364824	ed8565ad-31a6-4bf7-bfaa-518602317906	reyas y parpadeos			PENDIENTE	ALTA	\N	\N	\N	2026-11-06 22:36:31.215789-05	2026-11-06 22:36:31.215789-05	2026-11-06	\N	\N
7b4a854d-825e-46e4-b401-9d6fad370dc3	3	4372c874-dd4f-42ec-82f5-47c6d43400d8	0795be60-6fc9-4eb9-9623-cda31d0e328d	ed8565ad-31a6-4bf7-bfaa-518602317906	Impresion defectuosa ademas de ahcer ruidos al jalar el papel tambien es escaner no funciona correctamente			FINALIZADA	NORMAL	\N	\N	\N	2026-11-06 22:08:42.756415-05	2026-11-06 23:05:15.065028-05	2026-11-06	2026-11-06 23:05:15.065028-05	3b5b21e1-2d91-4a99-8eb6-37f67b06522b
e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	2	03022a24-38a0-42b2-9409-489d8ca65e7e	4f971d71-646d-4ae7-802e-c9f5b20ae6db	ed8565ad-31a6-4bf7-bfaa-518602317906	Equipo no enciende	Se reporta equipo sin energia y sin señales de encendido		FINALIZADA	ALTA	\N	\N	\N	2026-11-02 23:43:36.774227-05	2026-11-07 19:29:37.747092-05	2026-11-02	2026-11-07 19:29:37.747092-05	b31dd59d-f191-48a3-9970-7e3803b86707
\.


--
-- TOC entry 5372 (class 0 OID 17375)
-- Dependencies: 235
-- Data for Name: system_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_events (id, actor_id, event_type, entity_type, entity_id, details, occurred_at, result, description) FROM stdin;
59c90895-8f86-4585-94c1-a0c7619ee17c	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 14:26:38.692252-05	SUCCESS	
2cb14f3e-bfcd-48b2-8f29-92b449cfd866	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	UPDATE	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 14:27:10.734237-05	SUCCESS	
da7d9310-5eb4-425a-b106-e5c3d6490d21	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 14:53:04.004216-05	SUCCESS	
4c3bed59-afad-47c7-a9b5-56744973ed09	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 15:40:54.369778-05	SUCCESS	
ab6db56d-8717-41b4-97cf-6bfb822e7a40	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 18:30:24.399993-05	SUCCESS	
f203b264-f403-4e18-ba53-ba2b72ff819f	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	clients	93253264-d08a-4a36-96c6-94034b8a9dce	{}	2026-10-03 18:32:15.305467-05	SUCCESS	
a874f72e-f942-4dfc-b4ab-9afb3d18db2e	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	equipment	18913268-cece-4753-aa0d-d0e228958395	{}	2026-10-03 18:33:38.068254-05	SUCCESS	
1378f3a0-a3ae-4a64-a962-dc01f27f4f80	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 18:43:36.07248-05	SUCCESS	
65c9acd1-f479-48a3-acab-eea756358f8e	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	UPDATE	clients	93253264-d08a-4a36-96c6-94034b8a9dce	{}	2026-10-03 18:44:32.026169-05	SUCCESS	
ec3b3103-80df-4b49-8284-1c2eb3d41760	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	PERMISSIONS_CHANGE	roles	\N	{}	2026-10-03 18:45:41.966668-05	SUCCESS	
bbe05962-9573-40ac-bc6d-ff0c08274f83	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	PERMISSIONS_CHANGE	roles	\N	{}	2026-10-03 18:45:43.040151-05	SUCCESS	
75e7cb3f-4e81-4bf5-81b0-18ddcb077a77	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-10-03 18:52:39.099246-05	SUCCESS	
6e3192e8-1dce-47f2-8309-1628f839c7f3	b31dd59d-f191-48a3-9970-7e3803b86707	LOGIN	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-10-03 18:53:02.397017-05	SUCCESS	
eb0dd559-00c8-4b5d-9fcf-c8a4de5f6c21	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 18:53:44.66403-05	SUCCESS	
a8ced50f-4d7c-41a7-ab64-b545e5b15291	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 19:20:57.357422-05	SUCCESS	
88a44bb9-2bff-40f5-b8d5-a129e1a6e27f	b31dd59d-f191-48a3-9970-7e3803b86707	LOGIN	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-10-03 19:26:24.260021-05	SUCCESS	
b57553ba-048c-4870-b273-7f985fbdcc62	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-03 19:30:34.412733-05	SUCCESS	
6026778c-9b82-4dfd-9d79-cfe5340f459f	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-09 00:31:09.476865-05	SUCCESS	
30475e7d-9010-47d9-acc1-fb2e010c1367	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	clients	62443e22-29eb-4b53-a709-1c3a6823db8d	{}	2026-10-09 00:55:25.989352-05	SUCCESS	
39c3d286-ec83-4ead-8ab7-af3f55c0caf7	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	DELETE	clients	62443e22-29eb-4b53-a709-1c3a6823db8d	{}	2026-10-09 01:12:28.56099-05	SUCCESS	
56717e1e-8de8-4a13-8507-a215c283a00b	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	ACTIVE_CHANGE	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-10-09 01:12:50.009412-05	SUCCESS	
ad33fdc6-2687-4112-ad54-48777793baf2	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	ACTIVE_CHANGE	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-10-09 01:12:55.796356-05	SUCCESS	
bba4cf18-f373-48e8-828d-d9a7048c06ee	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-09 01:13:48.289292-05	SUCCESS	
ac3af6dc-a27d-42e1-bd3c-8430dc9e8ce3	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-09 01:14:07.679296-05	SUCCESS	
817ffe52-5f51-4e56-9ca6-f17553b6a1cd	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-09 01:36:49.874973-05	SUCCESS	
c9d8a57a-a1a3-4184-88a7-ab66de1c3a52	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-09 01:39:20.900425-05	SUCCESS	
f0ba6da5-82f2-41a7-b300-f8b70c9784ca	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-09 18:00:49.035053-05	SUCCESS	
a4ce4a2e-7d20-49e1-afa8-152e9b09036c	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-09 19:19:12.588176-05	SUCCESS	
74717f2a-591e-49f7-b38e-e972febe859e	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	clients	e96aea1a-4117-4cc7-a881-6ab2a3364824	{}	2026-10-09 19:20:59.746823-05	SUCCESS	
d455d196-c0f8-4561-971d-770e744ec7fa	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-09 19:21:40.684068-05	SUCCESS	
cb67740a-78ff-4c06-b1a7-5fa7215ecd61	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-09 19:22:52.393719-05	SUCCESS	
0bc703ef-699a-436b-abcc-20ae156f5286	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-10 18:44:19.379262-05	SUCCESS	
85aec562-e553-4a53-b4c1-518591e160bc	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-10 18:44:57.751127-05	SUCCESS	
977c67ba-8629-49a3-b284-fc5089795d54	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 11:39:53.559033-05	SUCCESS	
a6e57673-6847-4398-a044-aedcfe8b14ba	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 13:11:45.634096-05	SUCCESS	
272cf88d-e9c6-409d-826e-248f6e69c1cd	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 13:25:00.450267-05	SUCCESS	login
c1675f1e-51e5-41cb-9f11-e4d78f6f1da2	\N	LOGIN_FAILED	users	\N	{}	2026-10-18 13:39:16.913543-05	FAILED	Intento de inicio de sesión fallido
71060b9c-0dc0-4d0e-8971-abf20e938045	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 13:39:26.108343-05	SUCCESS	login
d200e0fe-8b3f-4b59-bb1f-ede440a849b2	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	clients	93fecc7d-8d2b-4764-9f02-cb0a07c2e986	{}	2026-10-18 13:44:05.291543-05	SUCCESS	create
5d930eba-e30b-466b-b229-1c80e5a8b8ae	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	REQUEST_FAILED	equipment	\N	{}	2026-10-18 13:45:05.944148-05	FAILED	La solicitud POST /api/equipment terminó con HTTP 409.
fa788fbd-a764-4abe-b4bb-83481e3392dc	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	equipment	a2a73b0b-e9ec-42d8-b27b-408ad4570df8	{}	2026-10-18 13:45:15.203139-05	SUCCESS	create
1c01dbdd-0970-4ee6-aab1-a9587e9d335a	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	service_orders	4eac7b12-84dc-4176-bc51-2e1807855335	{}	2026-10-18 13:46:29.937956-05	SUCCESS	create
f5c66020-cf8e-4b23-a2b8-608192efcd07	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	ASSIGN_TECHNICIAN	service_orders	4eac7b12-84dc-4176-bc51-2e1807855335	{}	2026-10-18 13:46:46.968835-05	SUCCESS	assign technician
e4999642-a41e-455f-ac1f-a517578763a7	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 13:59:44.267588-05	SUCCESS	login
dff8e08b-202c-4549-b3a2-f2f2585027c7	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 14:00:40.923975-05	SUCCESS	Cierre de sesión
9cd9ddcd-8671-4c58-bf38-bfc71d3898ba	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-18 14:00:49.391166-05	SUCCESS	login
007740da-183b-4548-bc35-8663ab6a0179	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGOUT	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-18 14:02:06.46333-05	SUCCESS	Cierre de sesión
47fc2885-0b41-4952-a76c-34e206811490	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 14:02:14.896391-05	SUCCESS	login
0afe152e-76db-460c-9229-e1dfc3d4523a	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 14:02:33.188605-05	SUCCESS	Cierre de sesión
3e856309-a246-4cd6-b65a-5e82f1636e9d	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 14:02:57.431674-05	SUCCESS	login
8cfba25e-6478-44bf-9f0f-ff1b9e64acc5	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 14:03:17.290943-05	SUCCESS	Cierre de sesión
d7cf7fbd-27c0-4642-b9ef-2c44707bf09f	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 14:27:46.285269-05	SUCCESS	login
a6cfe581-471a-46d2-bd77-246746c090b4	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	GENERATE_PREDIAGNOSIS	ai_prediagnoses	05c9d944-2f16-41e0-babf-37a68fbf67ea	{}	2026-10-18 14:28:01.599155-05	SUCCESS	Prediagnóstico generado
3de5b862-202e-40f6-8dfc-d188ed8b8f6b	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 17:04:08.213939-05	SUCCESS	login
ed4659e3-ae87-466d-8307-1015202c42f0	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-18 17:05:03.675215-05	SUCCESS	Cierre de sesión
a10b8e10-a2ed-4f7a-8a3f-ef9329c13301	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-18 17:05:12.682236-05	SUCCESS	login
3cce0c27-9585-4859-9515-c4472bd2bda2	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	CHANGE_STATUS	service_orders	4eac7b12-84dc-4176-bc51-2e1807855335	{}	2026-10-18 17:05:25.087783-05	SUCCESS	change status
2a49df33-2491-4d8a-950c-3f247e806839	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-18 17:44:31.149543-05	SUCCESS	login
475609e7-be67-4709-adb2-0a266c85372b	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	SAVE_TECHNICAL_ATTENTION	technical_attentions	0665c9c3-6098-4aa1-a787-4d313c938b32	{}	2026-10-18 17:47:12.502693-05	SUCCESS	Registro o actualización de atención técnica
aca1c62b-107f-43b2-9f70-2b1b9bbdfd96	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	FINALIZE_SERVICE_ORDER	service_orders	4eac7b12-84dc-4176-bc51-2e1807855335	{}	2026-10-18 17:47:12.522959-05	SUCCESS	finalize service order
87ca1324-fb9d-4306-812b-7c5ebbb06a75	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGOUT	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-10-18 17:48:11.105003-05	SUCCESS	Cierre de sesión
6d3534d3-c4be-4024-b7a0-a848c0333fbb	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-24 19:03:05.900743-05	SUCCESS	login
3175bb55-4aef-4e83-bceb-e8114f5c3460	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-24 19:34:28.686156-05	SUCCESS	Cierre de sesión
dac1823a-28d2-45c0-bd9d-77a5344f1bae	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-24 19:35:35.359517-05	SUCCESS	login
cb440428-38aa-4667-9802-61334bcdc9da	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-24 19:37:31.299739-05	SUCCESS	Cierre de sesión
19548909-a418-4a17-90f0-5027bac1d3b7	\N	LOGIN_FAILED	users	\N	{}	2026-10-24 19:38:55.147499-05	FAILED	Intento de inicio de sesión fallido
d1ae7d3c-b868-4331-ae37-e4f63a0bca2c	\N	LOGIN_FAILED	users	\N	{}	2026-10-24 19:39:00.112098-05	FAILED	Intento de inicio de sesión fallido
7bf9470c-83ec-47dd-8df8-f5b40f36f2bc	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-24 19:39:04.950514-05	SUCCESS	login
e4adfa98-d821-4e4a-8187-a1990c8f943b	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-24 19:43:04.549634-05	SUCCESS	Cierre de sesión
53cb9de7-cb10-4371-9499-5a62c80368a1	\N	LOGIN_FAILED	users	\N	{}	2026-10-24 19:43:14.781274-05	FAILED	Intento de inicio de sesión fallido
2c08f66d-c6c8-4288-a599-a5607f545ca1	b31dd59d-f191-48a3-9970-7e3803b86707	LOGIN	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-10-24 19:43:21.287485-05	SUCCESS	login
0c19786f-4161-471b-96fc-acf6bc385a4b	b31dd59d-f191-48a3-9970-7e3803b86707	LOGOUT	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-10-24 19:43:29.835361-05	SUCCESS	Cierre de sesión
d0a7d045-3a8f-4e61-9a05-5f0cd0878c80	\N	LOGIN_FAILED	users	\N	{}	2026-10-24 19:55:31.433233-05	FAILED	Intento de inicio de sesión fallido
c9f1af33-b33c-406a-af87-76eaef002909	\N	LOGIN_FAILED	users	\N	{}	2026-10-31 20:21:24.563777-05	FAILED	Intento de inicio de sesión fallido
af82b420-0349-4f6f-8637-a4a96046c190	\N	LOGIN_FAILED	users	\N	{}	2026-10-31 20:46:39.780493-05	FAILED	Intento de inicio de sesión fallido
cf5bd5fa-a498-4e47-b1e6-458c60dd2be7	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-31 20:46:47.719187-05	SUCCESS	login
6c8ec5d4-594f-4b5e-ae8e-be6a7983d91f	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:50:18.297851-05	SUCCESS	create
1816c4c4-a018-43c1-b90a-3ada37e082e5	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	users	a0c876e3-bec6-42b5-b41d-61820615ebf5	{}	2026-10-31 20:50:56.043893-05	SUCCESS	create
7ab27034-cfd9-46d9-b198-8c3f372884de	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-10-31 20:51:01.856792-05	SUCCESS	Cierre de sesión
630d1c56-e6c4-4560-8c90-6883956c9e84	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:52:20.552388-05	SUCCESS	login
fad9b1ca-cb65-4e07-9843-a8fb0c5f79a5	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:52:57.042591-05	SUCCESS	Cierre de sesión
0f1954d6-a5d6-4c22-9d60-3e9c09a5e830	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:53:12.335326-05	SUCCESS	login
8b2c9e74-23fc-4413-bb68-1e96001e6b7f	ed8565ad-31a6-4bf7-bfaa-518602317906	UPDATE	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:53:52.546359-05	SUCCESS	update
8e9e0282-7da9-4c55-ba1c-2af461288a03	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:53:55.61255-05	SUCCESS	Cierre de sesión
c5311013-9b93-48a7-8cbc-c4300be1275a	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:54:07.145856-05	SUCCESS	login
82215a83-dda8-46b4-996d-95e7ecb66e22	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:54:09.141227-05	SUCCESS	Cierre de sesión
12be432b-065c-462c-bb94-9441da6e9bed	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-10-31 20:55:18.433704-05	SUCCESS	login
877767c9-259c-4557-a685-49670c173960	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	clients	4f971d71-646d-4ae7-802e-c9f5b20ae6db	{}	2026-10-31 21:21:08.821607-05	SUCCESS	create
b8d31811-32aa-445b-b20c-b7cbde29046e	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	equipment	03022a24-38a0-42b2-9409-489d8ca65e7e	{}	2026-10-31 21:46:27.82746-05	SUCCESS	create
20ead1c6-5c31-4185-8b51-99b75168b2a0	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-02 23:18:38.750324-05	SUCCESS	login
3d39c09a-d843-4b30-8102-759f5c165893	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	service_orders	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	{}	2026-11-02 23:43:36.774227-05	SUCCESS	create
2a3216fb-2fb5-4e25-989f-c903f0092efb	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-02 23:52:07.596103-05	SUCCESS	Cierre de sesión
dbc2ea79-744d-4db6-a6f4-8a19cb251749	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:28:39.304173-05	FAILED	Intento de inicio de sesión fallido
6b89b7ff-e0a6-4dbd-973a-d1c452a4a566	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.556602-05	FAILED	Intento de inicio de sesión fallido
6df0ce2d-767b-4389-a355-27018257ee51	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.570869-05	FAILED	Intento de inicio de sesión fallido
4262a0ec-53c6-4beb-b11d-e4d109e5c4f2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.58384-05	FAILED	Intento de inicio de sesión fallido
93798caa-6cf1-4c02-a72d-bacb6f7fe645	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.591663-05	FAILED	Intento de inicio de sesión fallido
23b91697-2b3f-42ed-983a-909a9b8f457b	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.603682-05	FAILED	Intento de inicio de sesión fallido
9f096331-d61b-41cd-ab5b-2fd662cb1223	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.632862-05	FAILED	Intento de inicio de sesión fallido
5b23073c-a854-4132-b75a-a6de520d0a5d	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.660109-05	FAILED	Intento de inicio de sesión fallido
671627dd-9449-44a9-8f47-5cd83a68770f	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.684844-05	FAILED	Intento de inicio de sesión fallido
b8183d03-c727-4549-9d44-61a7c1629003	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:21.691144-05	FAILED	Intento de inicio de sesión fallido
9488d6e8-2090-48c2-9e33-272392b06f91	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.042828-05	FAILED	Intento de inicio de sesión fallido
add0e060-69e1-4739-9958-4b9c03c57293	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.049049-05	FAILED	Intento de inicio de sesión fallido
386fb28e-6c16-4069-a97c-5a4b574d964c	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.066397-05	FAILED	Intento de inicio de sesión fallido
94b45ca7-ac3d-4652-bfaf-fbded3b5b601	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.080696-05	FAILED	Intento de inicio de sesión fallido
3205a1c8-fba7-4cf5-a0c2-60889887ed4a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.079513-05	FAILED	Intento de inicio de sesión fallido
e165f3ec-1242-4335-b952-9f4233b93dbf	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.086491-05	FAILED	Intento de inicio de sesión fallido
13d12fa2-a08b-423b-8eb9-c87c2c4ff1bf	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.08878-05	FAILED	Intento de inicio de sesión fallido
b96e9d62-adcb-42ee-bbde-f1f270f5a5f1	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.095225-05	FAILED	Intento de inicio de sesión fallido
4041a047-c4b6-4359-8771-5e6b7a003059	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.102359-05	FAILED	Intento de inicio de sesión fallido
69f85b04-c648-4f5c-bb90-9713d4e10eb5	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.109453-05	FAILED	Intento de inicio de sesión fallido
7b017c29-6fbb-4768-91e0-2097a3424935	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.113299-05	FAILED	Intento de inicio de sesión fallido
c1f8a8cf-128b-4ad9-9310-02ee88f9995c	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.669916-05	FAILED	Intento de inicio de sesión fallido
9e60642b-cbcc-4802-814a-14c408d3f81a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.68001-05	FAILED	Intento de inicio de sesión fallido
34a77041-467f-43ce-b86e-54e5d5b8f542	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.685565-05	FAILED	Intento de inicio de sesión fallido
ff901ddb-a406-4a69-8c9b-431efe80d4ad	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.70937-05	FAILED	Intento de inicio de sesión fallido
69e2177d-87b4-4f1c-8bdc-4af1872bce65	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.751354-05	FAILED	Intento de inicio de sesión fallido
a9e9db20-1a35-454b-a3e5-2f751a78fdb9	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.765692-05	FAILED	Intento de inicio de sesión fallido
0ebf7d8c-6fc4-49c4-afdc-904c97b33db4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.848708-05	FAILED	Intento de inicio de sesión fallido
1d3a22ef-c90f-47c9-ba91-04a22712ef81	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.907463-05	FAILED	Intento de inicio de sesión fallido
9ced265c-2c8f-408c-bca7-bea824e94bd3	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:22.946062-05	FAILED	Intento de inicio de sesión fallido
ac562208-d1d3-4245-95ca-d15c9baaeecf	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.14779-05	FAILED	Intento de inicio de sesión fallido
45e3b769-c2d0-46be-ba84-cc46da048774	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.18667-05	FAILED	Intento de inicio de sesión fallido
07352e0a-0dca-4fb4-ab5c-1eff58725f53	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.19342-05	FAILED	Intento de inicio de sesión fallido
6b7e7315-4b81-4cef-b78e-210ff3bd92bc	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.197238-05	FAILED	Intento de inicio de sesión fallido
a73aa243-4bab-4498-b6db-0a6e35f9d95a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.200996-05	FAILED	Intento de inicio de sesión fallido
90a2f3c3-d342-4291-84a5-8774b2c2fc2a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.406196-05	FAILED	Intento de inicio de sesión fallido
98230002-2c02-4371-b0a4-f366e35519fb	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.406834-05	FAILED	Intento de inicio de sesión fallido
97c75685-911e-4859-9670-ab1ae185af8d	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.430479-05	FAILED	Intento de inicio de sesión fallido
93675482-3d32-41cd-9d79-1891e13be085	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.057865-05	FAILED	Intento de inicio de sesión fallido
7be573c4-38d4-41f1-8a98-3a129fa78880	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.00866-05	FAILED	Intento de inicio de sesión fallido
98aebb81-3482-4b6b-8662-421a3f8d69a9	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.712983-05	FAILED	Intento de inicio de sesión fallido
03e52af5-3383-4e7c-a0a8-480d0aeb9bcd	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.035481-05	FAILED	Intento de inicio de sesión fallido
134bdf66-5667-46d7-98d8-1dc778d7b739	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.85221-05	FAILED	Intento de inicio de sesión fallido
170f72f8-edf7-4a51-8544-3faf9ffd62b0	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.38438-05	FAILED	Intento de inicio de sesión fallido
64107c9a-12c4-4e9b-938d-f039fdee653e	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.590564-05	FAILED	Intento de inicio de sesión fallido
c141a615-5a89-4e32-be2d-d91224b3b0f4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.195548-05	FAILED	Intento de inicio de sesión fallido
1d856969-d33d-472a-b1d2-f3dc55cff689	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.789178-05	FAILED	Intento de inicio de sesión fallido
987c39f4-a1b9-416c-a5e5-61be4a82077a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.441404-05	FAILED	Intento de inicio de sesión fallido
85aa1e5b-c55d-4332-a86b-f2d9d3e5ecb4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.128278-05	FAILED	Intento de inicio de sesión fallido
119681c1-04f5-4c62-a14a-4e3af6c622c2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.622047-05	FAILED	Intento de inicio de sesión fallido
2b0198ed-d66b-4fb8-9937-7c843191cf60	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.232227-05	FAILED	Intento de inicio de sesión fallido
b51ebb29-3794-416a-a88f-33dbb9ed47e6	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.099546-05	FAILED	Intento de inicio de sesión fallido
ebe00205-ef8f-4406-a649-32e7a8acb391	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.558793-05	FAILED	Intento de inicio de sesión fallido
4b2771d8-24b7-4b0e-81a7-434382a987c5	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.137625-05	FAILED	Intento de inicio de sesión fallido
469a2802-c76b-4d52-9cc6-127df6d35a15	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.727872-05	FAILED	Intento de inicio de sesión fallido
fb3cdb7e-67bd-4e35-b2a0-88aa4121784a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.852835-05	FAILED	Intento de inicio de sesión fallido
1b0cb05c-1a35-42e9-822d-b474f2f54b1b	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.434841-05	FAILED	Intento de inicio de sesión fallido
b2b8420e-fa1c-4dd1-b008-114dfdd2c4fb	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.722845-05	FAILED	Intento de inicio de sesión fallido
2e8f1ce5-6a82-4153-88ca-9b95deaadd2a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.021184-05	FAILED	Intento de inicio de sesión fallido
5205659f-a6e4-40cf-9169-7cff4bcec73f	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.056068-05	FAILED	Intento de inicio de sesión fallido
13875657-a76e-4e2c-9f07-c067a18d0785	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.396702-05	FAILED	Intento de inicio de sesión fallido
97d630e2-e4eb-4610-996a-57474ed14193	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.454076-05	FAILED	Intento de inicio de sesión fallido
fccd8318-bdb5-4502-a96b-5de15938ad92	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.708692-05	FAILED	Intento de inicio de sesión fallido
902debb4-78c5-44ce-a015-aed5178400c4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.075378-05	FAILED	Intento de inicio de sesión fallido
b4d76684-0d9f-4b49-a890-fef24e24f9e4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.397669-05	FAILED	Intento de inicio de sesión fallido
04454f4d-0445-431d-9ab8-1e8288ab07ac	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.497576-05	FAILED	Intento de inicio de sesión fallido
e03a25c6-04e0-4dea-a28c-302802d2e0a9	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.580587-05	FAILED	Intento de inicio de sesión fallido
7e740519-5b04-4054-9111-3fe8591646b5	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.799636-05	FAILED	Intento de inicio de sesión fallido
6ebac709-36f2-4b5e-b893-1b4afac5e017	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.830348-05	FAILED	Intento de inicio de sesión fallido
5245c786-8106-4f2e-b733-8305b815fcaa	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.990888-05	FAILED	Intento de inicio de sesión fallido
34058ffc-b61f-44df-a7c3-74045478961a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.105727-05	FAILED	Intento de inicio de sesión fallido
6a3e47d4-d6e4-4362-a420-6f87d8f310ea	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.113962-05	FAILED	Intento de inicio de sesión fallido
2a83ad74-b5f3-44ad-b604-3e63b17b6ee2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.146067-05	FAILED	Intento de inicio de sesión fallido
4307b4ab-a851-43be-b8b2-93524030f184	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.605357-05	FAILED	Intento de inicio de sesión fallido
ab59d969-fe59-406c-bfc7-c4d8e564a1d0	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.919867-05	FAILED	Intento de inicio de sesión fallido
56afb71f-3c05-4f90-a535-04e25abe9c43	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.943126-05	FAILED	Intento de inicio de sesión fallido
d2d5e64e-7e59-4b1a-89a5-e7dd47c845c3	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.048732-05	FAILED	Intento de inicio de sesión fallido
b9f343b3-ab3e-491c-916c-ff26a4b30894	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.460647-05	FAILED	Intento de inicio de sesión fallido
2ec59253-ec10-4ea9-8042-8d3143dc70c2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.479496-05	FAILED	Intento de inicio de sesión fallido
65be397a-eab4-4bd6-9dd2-fbc96be58102	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.510366-05	FAILED	Intento de inicio de sesión fallido
7c2088ae-7e41-4d63-a3c1-9ac7572c4ffe	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.579471-05	FAILED	Intento de inicio de sesión fallido
aee79d59-0da9-432d-ac99-cf12300545fd	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.952442-05	FAILED	Intento de inicio de sesión fallido
ab2fcacf-355a-45a2-9f5e-ef1e42ad3b3d	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.986543-05	FAILED	Intento de inicio de sesión fallido
54aaa480-3730-418e-b91b-90366b3f2bcf	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.028414-05	FAILED	Intento de inicio de sesión fallido
422a0ad6-8e75-454e-a203-645f0969bfd8	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.076637-05	FAILED	Intento de inicio de sesión fallido
1319f582-c325-41a4-9283-1a4c01b5ecff	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.520016-05	FAILED	Intento de inicio de sesión fallido
6c683bbb-2475-49f6-b9d9-2baa658b7d40	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.541078-05	FAILED	Intento de inicio de sesión fallido
f2aec5ee-ea81-4ebe-b9d4-3f11558501e4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.67706-05	FAILED	Intento de inicio de sesión fallido
9f805c23-8884-4e4b-bb61-20a688dd79dd	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.690685-05	FAILED	Intento de inicio de sesión fallido
3252bf32-42d7-48ab-9f94-dbd1842faaab	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.919661-05	FAILED	Intento de inicio de sesión fallido
f0cf5f87-d0b0-465f-923f-488408a8598e	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.970824-05	FAILED	Intento de inicio de sesión fallido
68eda37b-c024-43f5-825a-5f6225f4c2de	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.104105-05	FAILED	Intento de inicio de sesión fallido
7a25c8b7-790d-4785-be29-4f67fccda165	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.449505-05	FAILED	Intento de inicio de sesión fallido
0544871e-058b-4cfd-a238-6eedb1412d3c	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.471753-05	FAILED	Intento de inicio de sesión fallido
753d832d-f432-445d-9668-98c067884ace	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.590544-05	FAILED	Intento de inicio de sesión fallido
0a8beb46-0137-4325-8f64-d2ca99dae323	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.645458-05	FAILED	Intento de inicio de sesión fallido
1e6c8764-087c-428d-89be-f518362111c7	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.694882-05	FAILED	Intento de inicio de sesión fallido
52e3de6f-f777-4460-86de-ebfd6d0bdc01	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.852293-05	FAILED	Intento de inicio de sesión fallido
e4fb42a0-f750-458b-b4c8-9b37e4b2c8e9	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.979625-05	FAILED	Intento de inicio de sesión fallido
4a1e88b6-5815-4a9f-8a8e-57a4c7095079	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.084192-05	FAILED	Intento de inicio de sesión fallido
7b692982-45d2-4026-8d98-5dcf3abf5c79	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.53479-05	FAILED	Intento de inicio de sesión fallido
d1ba3191-8c58-4e01-b989-79f01ffb99ec	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.620795-05	FAILED	Intento de inicio de sesión fallido
0d10b8a5-999b-493c-b4e6-a2b2fed7f9ea	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.914761-05	FAILED	Intento de inicio de sesión fallido
ab13e0dc-a70c-4ef8-9f52-b5f442d022c3	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.990971-05	FAILED	Intento de inicio de sesión fallido
608a9a50-718b-413c-9d99-782701dde18e	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.012921-05	FAILED	Intento de inicio de sesión fallido
fa8764e4-6f91-4e8d-b1c2-755d5af0239f	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.049409-05	FAILED	Intento de inicio de sesión fallido
37e6c995-d292-4012-8789-c1cac301e032	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.171209-05	FAILED	Intento de inicio de sesión fallido
82680a87-49ee-4c5a-8236-21c2c0315b25	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.298882-05	FAILED	Intento de inicio de sesión fallido
2341861b-ef9d-4031-aafe-cae7eaecf066	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.355723-05	FAILED	Intento de inicio de sesión fallido
9c187449-955d-459e-b1d1-f10709d68a00	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.502481-05	FAILED	Intento de inicio de sesión fallido
a55d7d25-89cc-4173-a5cc-4cee070fefad	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.541905-05	FAILED	Intento de inicio de sesión fallido
6f28c690-fb6d-41b3-ac66-8d56d09dba4a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.60588-05	FAILED	Intento de inicio de sesión fallido
2e2ea310-a23d-4691-86c0-28104ed0150d	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.770516-05	FAILED	Intento de inicio de sesión fallido
b38a1bd8-139e-4636-9745-bd283008d38b	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.206478-05	FAILED	Intento de inicio de sesión fallido
cdf7442c-2c6b-4533-bac0-0a5aafcf1af7	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.217619-05	FAILED	Intento de inicio de sesión fallido
318f36ff-0d88-46e2-aa63-c6ebfc56eb3a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.411593-05	FAILED	Intento de inicio de sesión fallido
1958b04a-df8d-4cb7-af98-1803fb5b57bf	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.423257-05	FAILED	Intento de inicio de sesión fallido
fbcb8482-97de-4e7c-9eb2-6556e8b0faef	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.436179-05	FAILED	Intento de inicio de sesión fallido
56d523d5-aa0d-440c-936f-7b7187e0cc40	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.753646-05	FAILED	Intento de inicio de sesión fallido
fd43d373-66ba-487f-9ddc-a4ce20203191	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.465459-05	FAILED	Intento de inicio de sesión fallido
3727f699-a887-450a-85ea-f64c189a685a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.882347-05	FAILED	Intento de inicio de sesión fallido
c720c372-cebd-4054-9453-473aa3ccb824	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.813106-05	FAILED	Intento de inicio de sesión fallido
47e4a5bc-32a8-459d-992e-fb4089c3986e	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.640674-05	FAILED	Intento de inicio de sesión fallido
22f8b67e-1a4d-453f-b8ad-8f779ebea81b	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.47007-05	FAILED	Intento de inicio de sesión fallido
8dbb217f-bafd-4836-b622-fefde35bba69	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:23.940592-05	FAILED	Intento de inicio de sesión fallido
960b607f-9535-4d00-9a0f-b6418a921513	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.009533-05	FAILED	Intento de inicio de sesión fallido
0670a0ea-8418-4281-b7d5-28f9069afa66	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.040022-05	FAILED	Intento de inicio de sesión fallido
51465f63-ee82-47d3-b0d0-77962abcf455	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.044655-05	FAILED	Intento de inicio de sesión fallido
93a5c0b5-7b3c-4240-be1c-3914e54d65b8	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.086858-05	FAILED	Intento de inicio de sesión fallido
fb3755b5-ae65-47d0-a583-ea26ce36a80c	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.432196-05	FAILED	Intento de inicio de sesión fallido
fb7aed64-63ec-495f-b0f3-1f79b60fef5f	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.441211-05	FAILED	Intento de inicio de sesión fallido
4ceec560-d7f5-4d8e-8e40-850ef84f612f	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.599089-05	FAILED	Intento de inicio de sesión fallido
6648b6ad-372e-46da-b39c-016ac4144c89	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.703839-05	FAILED	Intento de inicio de sesión fallido
7e10665a-8ed3-4de4-8653-5c9cbcbd657f	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.706598-05	FAILED	Intento de inicio de sesión fallido
963bff7c-28ff-40da-a4e7-c53a41e41a06	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.718984-05	FAILED	Intento de inicio de sesión fallido
0b089f48-b744-46dc-9916-5c38ed06f165	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:24.724127-05	FAILED	Intento de inicio de sesión fallido
e61071fb-6726-451a-8a33-a6e24efddd73	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.080691-05	FAILED	Intento de inicio de sesión fallido
5719f1ef-a13b-4dcc-9f5b-47597bc385d1	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.090109-05	FAILED	Intento de inicio de sesión fallido
f2a6b2b3-c082-4694-9759-84ff279f885a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.466899-05	FAILED	Intento de inicio de sesión fallido
ed4435da-5c3b-4420-9086-cf85e4b2b153	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.583895-05	FAILED	Intento de inicio de sesión fallido
6c021b59-0034-4b4f-9904-492091d1a615	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.817097-05	FAILED	Intento de inicio de sesión fallido
55dd0b3e-e6f4-4b47-9c69-5cec072b5e7b	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:25.997589-05	FAILED	Intento de inicio de sesión fallido
c3b70ff3-2d94-431f-8510-a518f37defde	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.006077-05	FAILED	Intento de inicio de sesión fallido
dd41b07e-74c9-4d2b-bed7-a80f28e4e19c	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.011115-05	FAILED	Intento de inicio de sesión fallido
7e18c6bb-f5e1-4067-bbe0-9d5ee6dfe6ee	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.111274-05	FAILED	Intento de inicio de sesión fallido
42b8f9eb-300c-4294-87f2-0bd725c40ff5	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.124628-05	FAILED	Intento de inicio de sesión fallido
1940f582-41dd-43d5-8f0e-858d8faf70cc	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.481954-05	FAILED	Intento de inicio de sesión fallido
dc03c745-5ba1-4205-ab35-e8662c2cf7c0	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.655942-05	FAILED	Intento de inicio de sesión fallido
0669d956-3a5b-414f-9fad-0ca553d2ed6d	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.670311-05	FAILED	Intento de inicio de sesión fallido
8337244a-46b5-4fb6-bfe3-fa48db7d23c1	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.898301-05	FAILED	Intento de inicio de sesión fallido
e31dc450-940b-41ff-b610-736406ec494a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:26.931514-05	FAILED	Intento de inicio de sesión fallido
34a51082-9500-43fa-bea1-d806420f19de	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.092211-05	FAILED	Intento de inicio de sesión fallido
7d00fb97-881b-43d7-bc5b-96b62693ed78	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.460857-05	FAILED	Intento de inicio de sesión fallido
cba044bb-43a5-4c3b-b65a-18c7a5d0cbaa	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.567277-05	FAILED	Intento de inicio de sesión fallido
287e2e85-2bb2-4a14-b3e6-5cee7c9e4dc4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.610918-05	FAILED	Intento de inicio de sesión fallido
a9874aec-c388-4944-84e7-4c85f7191885	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.71079-05	FAILED	Intento de inicio de sesión fallido
a2c18031-5f70-450b-85b7-6e944df58703	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.981514-05	FAILED	Intento de inicio de sesión fallido
95c29865-8c63-44ef-9529-ed2dd17e4560	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:27.98738-05	FAILED	Intento de inicio de sesión fallido
f2767913-3872-43aa-b714-7d110afbf95b	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.02527-05	FAILED	Intento de inicio de sesión fallido
1503a6ed-513a-4489-a7f6-9b096ec67805	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.233949-05	FAILED	Intento de inicio de sesión fallido
1bb8cfda-065e-4529-afc9-abed9a67bcea	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.534068-05	FAILED	Intento de inicio de sesión fallido
a7122d01-96d8-4c96-8113-c4ba47e08036	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.600904-05	FAILED	Intento de inicio de sesión fallido
d1142a51-b4f6-4ccf-9456-2cd85015b1a6	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.826293-05	FAILED	Intento de inicio de sesión fallido
96bd2a08-1487-4890-93d1-b5e5c3e83d40	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:28.972739-05	FAILED	Intento de inicio de sesión fallido
d4dbfd17-9d98-4f6a-916e-526b010c9a31	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.006506-05	FAILED	Intento de inicio de sesión fallido
1cd3cceb-85dd-46e3-b137-8ec8daed0e40	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.270246-05	FAILED	Intento de inicio de sesión fallido
f07d335f-d095-498b-83f7-860c540ad8c2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.438167-05	FAILED	Intento de inicio de sesión fallido
ab4aa835-fa15-44ea-94ab-59c7fca77206	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.830881-05	FAILED	Intento de inicio de sesión fallido
ab40c584-3c8c-4a25-9c09-1ed4ad25574a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:29.936016-05	FAILED	Intento de inicio de sesión fallido
c47b34d9-d42d-48ec-8cb6-7ee0bc97429a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.012538-05	FAILED	Intento de inicio de sesión fallido
a27b4a00-80bd-43ce-a6b5-1eec9a46cb72	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.038245-05	FAILED	Intento de inicio de sesión fallido
58795d5b-ade2-424f-a4d1-61fdeabced65	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.518782-05	FAILED	Intento de inicio de sesión fallido
88d9a6cd-a4d8-4a55-95df-142b29440309	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.543997-05	FAILED	Intento de inicio de sesión fallido
bebf23f0-cdb5-4cc0-a850-c15e06b175f2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.600625-05	FAILED	Intento de inicio de sesión fallido
a0f9d09e-dc6c-4ee0-a9b6-322f37c5f727	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:30.714155-05	FAILED	Intento de inicio de sesión fallido
b398e51f-22ea-4da2-8b76-d440805ef4b4	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.085349-05	FAILED	Intento de inicio de sesión fallido
55c92d33-5d32-4137-9f6d-8810efe4b227	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.148749-05	FAILED	Intento de inicio de sesión fallido
72926d3b-6b94-4038-aa36-a9b8140def16	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.193563-05	FAILED	Intento de inicio de sesión fallido
14682972-cbb0-4918-8ccf-a1c2b14f61ff	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.559444-05	FAILED	Intento de inicio de sesión fallido
f95d260f-66b8-4feb-9768-69dd4bfd3d82	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.672577-05	FAILED	Intento de inicio de sesión fallido
632ed730-e374-4d8d-b647-443e98dc48cb	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:31.875204-05	FAILED	Intento de inicio de sesión fallido
6a4db491-6115-486a-bac6-427f6364fda6	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.069599-05	FAILED	Intento de inicio de sesión fallido
2147fc15-4571-4269-bcd2-d9acb8facdbf	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.149547-05	FAILED	Intento de inicio de sesión fallido
c4f2b7bd-0c73-47ff-b51d-c25d55f501c3	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.29655-05	FAILED	Intento de inicio de sesión fallido
c283689c-d9cf-4c31-ad42-4e44692d0d84	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.432285-05	FAILED	Intento de inicio de sesión fallido
8f766ea5-a07d-49a0-8a1a-ed7be46159b9	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.51811-05	FAILED	Intento de inicio de sesión fallido
ce772d54-1fe4-4bfd-9544-d455fdd4e7e1	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.590912-05	FAILED	Intento de inicio de sesión fallido
2f671ccd-d937-4faf-ab91-010ec6e42698	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.016961-05	FAILED	Intento de inicio de sesión fallido
f4f98278-0b46-43b4-ba6c-695ded9e9964	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.251939-05	FAILED	Intento de inicio de sesión fallido
ee9c5085-adfe-4b5c-b320-f7ea8c7773d6	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.349421-05	FAILED	Intento de inicio de sesión fallido
c3e99e3a-256b-4f4f-b4e6-25d7c754842b	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.42196-05	FAILED	Intento de inicio de sesión fallido
85292d21-b53c-4de9-b9d5-80c344fb62e2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.571774-05	FAILED	Intento de inicio de sesión fallido
52879f4c-1290-487b-8543-884d3c97116f	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.618907-05	FAILED	Intento de inicio de sesión fallido
49f0767d-c536-4464-8703-c9b332c60e46	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.674042-05	FAILED	Intento de inicio de sesión fallido
835acc85-f7b5-4daf-acda-6f0bf3f90610	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.725936-05	FAILED	Intento de inicio de sesión fallido
78c4aba3-4cbf-446c-9a95-56a8af30aa44	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.886626-05	FAILED	Intento de inicio de sesión fallido
cfe32601-b5b2-4aa9-b90a-26f49056417a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:31:02.961932-05	FAILED	Intento de inicio de sesión fallido
eab5751d-48d8-4b3b-a60d-7c9195a976e2	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:32.718045-05	FAILED	Intento de inicio de sesión fallido
df6db5d2-3c4e-459d-b2f5-592fa707bd88	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.012617-05	FAILED	Intento de inicio de sesión fallido
5c2c8298-779e-4aea-b631-b1896f128fe7	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.186057-05	FAILED	Intento de inicio de sesión fallido
6a2e694d-ea26-4ddd-b538-95a4352aedea	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.251585-05	FAILED	Intento de inicio de sesión fallido
ec9947d0-d340-4b9b-9362-585aea285888	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.291084-05	FAILED	Intento de inicio de sesión fallido
27a34fd1-68ca-40ad-95ac-0dca04349d6a	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.329018-05	FAILED	Intento de inicio de sesión fallido
ed32b85a-acfa-4fca-a8de-c2cd62e17d5c	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.421976-05	FAILED	Intento de inicio de sesión fallido
e60790f6-9b7c-43f6-b140-8163c5595fce	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.570807-05	FAILED	Intento de inicio de sesión fallido
d9b0cbe1-3637-4e83-a8bd-0a302d2ea054	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.611457-05	FAILED	Intento de inicio de sesión fallido
72b16a94-6346-4ad6-9882-04c04183db97	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.647913-05	FAILED	Intento de inicio de sesión fallido
00a690f3-075d-4b2e-89ed-1947e32268f3	\N	LOGIN_FAILED	users	\N	{}	2026-11-04 00:30:33.783535-05	FAILED	Intento de inicio de sesión fallido
dd1e9f35-726c-4701-a0cb-f71c9ebe5fee	\N	LOGIN_FAILED	users	\N	{}	2026-11-06 20:25:28.76789-05	FAILED	Intento de inicio de sesión fallido
fa68c8b1-bad0-4ddd-a6a5-d4a27f592b79	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-06 20:31:56.293111-05	SUCCESS	login
f864a8c1-5c5d-48ae-898d-9185f890b8f2	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	equipment	\N	{}	2026-11-06 20:34:30.398077-05	FAILED	La solicitud POST /api/equipment terminó con HTTP 409.
4d14c4d9-4670-4fe7-b4ad-1b8b2e246510	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-06 21:27:49.209793-05	SUCCESS	login
2db64d2a-5964-4e37-9f5b-f3dc3bebcd38	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-06 21:43:28.355008-05	SUCCESS	login
0a83bfa7-4c46-4b8e-8677-696ff496fa05	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-06 21:46:23.399492-05	SUCCESS	login
cd90366b-6de0-409e-8d1b-cbc035bc4286	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-06 21:51:44.24416-05	SUCCESS	login
738bdcf1-1b2b-4244-8246-14aff2a844df	ed8565ad-31a6-4bf7-bfaa-518602317906	GENERATE_PREDIAGNOSIS	ai_prediagnoses	4abad3be-3a48-4aac-899a-a5892f3164fb	{}	2026-11-06 21:54:03.91498-05	FAILED	Falló la generación del prediagnóstico
e28c2368-e9a1-4e29-ae24-bb4d15f94731	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	orders/{id}/prediagnoses	\N	{}	2026-11-06 21:54:03.918348-05	FAILED	La solicitud POST /api/orders/{id}/prediagnoses terminó con HTTP 502.
8cade987-ddf5-4218-a221-5be49479cbdd	ed8565ad-31a6-4bf7-bfaa-518602317906	GENERATE_PREDIAGNOSIS	ai_prediagnoses	fc5b0daa-ac16-411b-9b85-c8fe112f037f	{}	2026-11-06 21:54:38.51189-05	SUCCESS	Prediagnóstico generado
842ea22f-f3d7-426a-89bb-5ad332751e3b	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	clients	0795be60-6fc9-4eb9-9623-cda31d0e328d	{}	2026-11-06 22:06:57.213344-05	SUCCESS	create
bbbc2804-ab64-4add-a092-76651df44ae4	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	equipment	4372c874-dd4f-42ec-82f5-47c6d43400d8	{}	2026-11-06 22:07:47.05464-05	SUCCESS	create
b1437dec-9a88-450d-b0fc-8c0773a016cc	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	service_orders	7b4a854d-825e-46e4-b401-9d6fad370dc3	{}	2026-11-06 22:08:42.756415-05	SUCCESS	create
697d2c5c-19fe-4292-a96c-ffa3a1e3636f	ed8565ad-31a6-4bf7-bfaa-518602317906	ASSIGN_TECHNICIAN	service_orders	7b4a854d-825e-46e4-b401-9d6fad370dc3	{}	2026-11-06 22:09:05.30923-05	SUCCESS	assign technician
f8dbed1e-7ce6-4795-b80b-9246a4f86fb9	ed8565ad-31a6-4bf7-bfaa-518602317906	ASSIGN_TECHNICIAN	service_orders	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	{}	2026-11-06 22:09:19.308211-05	SUCCESS	assign technician
bcf9b486-d76c-4f6c-9d37-10c2c75101f6	ed8565ad-31a6-4bf7-bfaa-518602317906	ACTIVE_CHANGE	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-11-06 22:10:06.379404-05	SUCCESS	active change
20bfaf46-228c-4564-928d-312eb5a694f0	ed8565ad-31a6-4bf7-bfaa-518602317906	ACTIVE_CHANGE	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-11-06 22:10:39.870277-05	SUCCESS	active change
540d09d1-3360-4e00-b081-ca03c9f4455d	ed8565ad-31a6-4bf7-bfaa-518602317906	ASSIGN_TECHNICIAN	service_orders	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	{}	2026-11-06 22:10:55.42995-05	SUCCESS	assign technician
46f144d0-5195-4270-bb15-d79b236c05a3	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	equipment	686f9b48-1025-4319-ad41-f04f79a1c609	{}	2026-11-06 22:34:28.530596-05	SUCCESS	create
517bce8b-c739-4e78-a94f-46205f78bb93	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	orders	\N	{}	2026-11-06 22:35:22.006775-05	FAILED	La solicitud POST /api/orders terminó con HTTP 400.
bd325ea3-eb6e-4c00-928f-e1e38b26d040	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	orders	\N	{}	2026-11-06 22:35:59.157901-05	FAILED	La solicitud POST /api/orders terminó con HTTP 400.
f8810d11-43a8-47a1-99e9-8bd25a2fc529	ed8565ad-31a6-4bf7-bfaa-518602317906	CREATE	service_orders	e90e9fde-5f78-464d-9ae3-e8236935baa1	{}	2026-11-06 22:36:31.215789-05	SUCCESS	create
e9454271-211d-4a3a-8f12-6acfa153e85a	\N	LOGIN_FAILED	users	\N	{}	2026-11-06 22:56:58.205572-05	FAILED	Intento de inicio de sesión fallido
badeaeac-3aaa-4f77-a1c5-dd7fb463ac50	\N	LOGIN_FAILED	users	\N	{}	2026-11-06 22:57:52.353097-05	FAILED	Intento de inicio de sesión fallido
11a4c3ab-0737-41db-bd80-3e1c22a63b1d	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-06 22:58:12.929273-05	SUCCESS	login
657d7041-7472-4b45-a269-d51250f9144e	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-06 22:59:31.677004-05	SUCCESS	Cierre de sesión
1d134292-c962-44f0-89b3-677c70a262f8	\N	LOGIN_FAILED	users	\N	{}	2026-11-06 22:59:38.033349-05	FAILED	Intento de inicio de sesión fallido
863dc299-bab0-4280-aea6-b3085fbfddea	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-11-06 22:59:42.13937-05	SUCCESS	login
1cccabc6-41ea-4ddf-adf2-cb0930d6380b	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	CHANGE_STATUS	service_orders	7b4a854d-825e-46e4-b401-9d6fad370dc3	{}	2026-11-06 23:00:23.292237-05	SUCCESS	change status
3958b11f-a336-4d00-8744-44701fb70a9f	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	SAVE_TECHNICAL_ATTENTION	technical_attentions	13f75d6e-024e-4e77-a1c0-20f02845ea54	{}	2026-11-06 23:05:15.034821-05	SUCCESS	Registro o actualización de atención técnica
43a121c9-a9b3-47f6-8627-f10767628588	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	FINALIZE_SERVICE_ORDER	service_orders	7b4a854d-825e-46e4-b401-9d6fad370dc3	{}	2026-11-06 23:05:15.065028-05	SUCCESS	finalize service order
be93b80c-bef1-447b-bd99-44319bf4a726	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGOUT	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-11-06 23:05:53.092848-05	SUCCESS	Cierre de sesión
d6f9e8b0-b4f1-4ee7-8856-75c5cdc74140	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-06 23:06:38.015868-05	SUCCESS	login
c0b84818-3411-4908-9126-144031a669d2	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-11-07 12:49:22.691516-05	SUCCESS	login
c2811839-83f8-47be-8afd-d689325c33bd	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 18:04:26.06936-05	FAILED	Intento de inicio de sesión fallido
fb1a322b-55b9-4e13-aaa8-81d60c88dff5	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-07 18:04:36.444331-05	SUCCESS	login
e625e648-63a7-4a29-9142-86707ae502a3	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-07 18:13:23.267517-05	SUCCESS	login
0fe012c2-e5f8-4690-8e1a-e57f7c4bda39	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-07 19:01:19.7059-05	SUCCESS	login
4ac41852-d49e-400c-93f3-de3ac1e1335d	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:02:00.226845-05	FAILED	Intento de inicio de sesión fallido
d50bdc0c-61f8-44f1-a444-8d63bca8f8e0	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:02:47.259438-05	FAILED	Intento de inicio de sesión fallido
ffd08d6d-c8f8-446e-b585-c155e6f67406	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:03:22.158116-05	FAILED	Intento de inicio de sesión fallido
8440e27a-99a7-4e7b-96c1-1c818ae4761a	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:03:30.593079-05	SUCCESS	login
1f63e9dd-b9db-45a4-9c8c-1b2d4eb79b0b	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:05:00.685553-05	SUCCESS	Cierre de sesión
85d34e51-ac1c-4611-b0ed-826de50079d7	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:05:51.549971-05	FAILED	Intento de inicio de sesión fallido
4a0c90d9-71d5-4fc4-8f8f-8fb64812b2dd	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:06:06.901607-05	FAILED	Intento de inicio de sesión fallido
6293f4f4-d358-4a9f-a9bc-476efaa6127f	ed8565ad-31a6-4bf7-bfaa-518602317906	GENERATE_PREDIAGNOSIS	ai_prediagnoses	ebb0bdfb-fb6e-4cab-ace1-3246439190b0	{}	2026-11-07 19:06:11.931226-05	FAILED	Falló la generación del prediagnóstico
e512ad79-afbf-4ba3-b494-b165dbb56f4d	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	orders/{id}/prediagnoses	\N	{}	2026-11-07 19:06:11.93357-05	FAILED	La solicitud POST /api/orders/{id}/prediagnoses terminó con HTTP 502.
5be6d405-4f5f-486c-af2f-206d2dfae66e	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:06:12.020675-05	SUCCESS	login
83ffa403-0b21-47eb-b772-d5d5a8adafa6	ed8565ad-31a6-4bf7-bfaa-518602317906	GENERATE_PREDIAGNOSIS	ai_prediagnoses	8893da80-a544-41df-9eed-9e8777ec66ee	{}	2026-11-07 19:06:31.664161-05	FAILED	Falló la generación del prediagnóstico
bd913a53-21f1-4b54-b602-8543452927cf	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	orders/{id}/prediagnoses	\N	{}	2026-11-07 19:06:31.665448-05	FAILED	La solicitud POST /api/orders/{id}/prediagnoses terminó con HTTP 502.
383e3d5b-8f6d-426f-aaa4-888a43cd03ab	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:07:57.175936-05	SUCCESS	Cierre de sesión
98b2dbc8-7b71-44b9-81e5-442f94e4faa3	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-11-07 19:08:16.619512-05	SUCCESS	login
31023852-b2de-4fc3-ac2c-9941ed1359e6	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGOUT	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-11-07 19:08:55.549267-05	SUCCESS	Cierre de sesión
9917241c-ddda-4884-8362-9fa41afaca17	ed8565ad-31a6-4bf7-bfaa-518602317906	GENERATE_PREDIAGNOSIS	ai_prediagnoses	6afd267f-f1cd-409c-9c95-307dbf39177b	{}	2026-11-07 19:09:11.812023-05	FAILED	Falló la generación del prediagnóstico
82e19c49-63a2-44e7-b938-81ca0343412a	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	orders/{id}/prediagnoses	\N	{}	2026-11-07 19:09:11.814107-05	FAILED	La solicitud POST /api/orders/{id}/prediagnoses terminó con HTTP 502.
7a90ce0e-5749-4c5a-a785-a6fe55864a52	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:18:53.902244-05	SUCCESS	login
0a8e7200-af1e-46d1-aa59-4d541c6a2606	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:20:39.763285-05	SUCCESS	Cierre de sesión
c7cb7f52-9d41-4974-a5ae-fbcd74fa497e	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:20:56.848912-05	FAILED	Intento de inicio de sesión fallido
2f97fa1f-7a01-49f4-a450-279dfe324373	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:21:13.928527-05	FAILED	Intento de inicio de sesión fallido
bd4c3229-a3c3-4c9b-8787-f6b925aa5ad8	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:21:19.383325-05	SUCCESS	login
2da79536-1642-475a-ac00-19e4212b80fe	ed8565ad-31a6-4bf7-bfaa-518602317906	GENERATE_PREDIAGNOSIS	ai_prediagnoses	3d72bc17-53e6-4294-a023-089aba1d8c01	{}	2026-11-07 19:22:01.253443-05	FAILED	Falló la generación del prediagnóstico
b2b1ee12-c172-4f3f-92e5-26d8df3b02af	ed8565ad-31a6-4bf7-bfaa-518602317906	REQUEST_FAILED	orders/{id}/prediagnoses	\N	{}	2026-11-07 19:22:01.254625-05	FAILED	La solicitud POST /api/orders/{id}/prediagnoses terminó con HTTP 502.
f670b877-bb8d-4200-88cf-b4f709c98499	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:22:27.573337-05	SUCCESS	Cierre de sesión
8a74de9d-435d-4ec6-ac24-d3cf7328d46c	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGIN	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-11-07 19:22:36.481898-05	SUCCESS	login
2218a706-cfe7-449e-9ba0-afb17b8ef2ae	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	LOGOUT	users	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	{}	2026-11-07 19:22:45.669033-05	SUCCESS	Cierre de sesión
f8401e7e-526b-4aaf-9be6-849eb038b4a0	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:22:55.854046-05	FAILED	Intento de inicio de sesión fallido
a7d12e9d-ab57-421e-aca8-d1366d20558f	b31dd59d-f191-48a3-9970-7e3803b86707	LOGIN	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-11-07 19:23:01.509983-05	SUCCESS	login
7f844ca7-d1b9-4953-b568-1122a9abc102	b31dd59d-f191-48a3-9970-7e3803b86707	LOGOUT	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-11-07 19:23:39.264582-05	SUCCESS	Cierre de sesión
d4754671-2975-4843-a64c-4c6ee5401e80	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:25:19.617974-05	FAILED	Intento de inicio de sesión fallido
8c497d18-8384-4330-98c1-9d79d02a7c4b	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-07 19:25:48.258666-05	SUCCESS	login
5affbcf3-75d7-4e7b-b8b5-aa053f6b2d91	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:26:30.12045-05	FAILED	Intento de inicio de sesión fallido
e7b8bf6b-edc0-4f85-98b6-dd750ebd68d8	\N	LOGIN_FAILED	users	\N	{}	2026-11-07 19:26:41.921591-05	FAILED	Intento de inicio de sesión fallido
3c2526f6-2285-4960-875c-43d2004230ee	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGIN	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:26:45.923703-05	SUCCESS	login
dad34aa8-765d-495b-9afe-129a910a68dd	ed8565ad-31a6-4bf7-bfaa-518602317906	LOGOUT	users	ed8565ad-31a6-4bf7-bfaa-518602317906	{}	2026-11-07 19:27:55.789521-05	SUCCESS	Cierre de sesión
ca5916bb-4a40-4eb8-9629-d301d90be481	b31dd59d-f191-48a3-9970-7e3803b86707	LOGIN	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-11-07 19:28:05.550647-05	SUCCESS	login
40dbff90-3430-44ba-ba13-6352c5bfe912	b31dd59d-f191-48a3-9970-7e3803b86707	CHANGE_STATUS	service_orders	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	{}	2026-11-07 19:28:25.909213-05	SUCCESS	change status
932bbafc-09b6-4987-9983-76d599165f6d	b31dd59d-f191-48a3-9970-7e3803b86707	SAVE_TECHNICAL_ATTENTION	technical_attentions	ae74f69c-d04b-435e-8beb-fab1f59ff99a	{}	2026-11-07 19:29:37.713071-05	SUCCESS	Registro o actualización de atención técnica
d1866e3b-f9b0-44f0-b84c-d2969c7c4c82	b31dd59d-f191-48a3-9970-7e3803b86707	FINALIZE_SERVICE_ORDER	service_orders	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	{}	2026-11-07 19:29:37.747092-05	SUCCESS	finalize service order
be300ac3-b83f-49ea-9f32-517b9c33be1a	b31dd59d-f191-48a3-9970-7e3803b86707	LOGOUT	users	b31dd59d-f191-48a3-9970-7e3803b86707	{}	2026-11-07 19:29:53.964256-05	SUCCESS	Cierre de sesión
0ffbc60d-e348-4032-9750-c70855c0239a	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-21 19:04:29.104814-05	SUCCESS	login
2f56130a-997a-4ada-b62b-c5e22453a9b4	\N	BACKUP	backup_runs	db8ab40a-d291-4259-8eff-2f1b53e14bc3	{}	2026-11-21 21:00:00.041417-05	FAILED	Falló la generación del respaldo
690834f7-3961-484a-894d-0c0fb959ce8c	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-23 23:32:22.65631-05	SUCCESS	login
bd57bd32-7adc-4a36-bdde-b33a14a1e411	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE_QUOTATION	quotation	2e9edc32-851d-4795-99d5-b2b06742456b	{}	2026-11-23 23:41:18.951609-05	SUCCESS	Cotización creada para la orden e90e9fde-5f78-464d-9ae3-e8236935baa1
a3d65467-4b95-4773-8e12-1c0010c2f32a	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-23 23:50:40.852979-05	SUCCESS	Cierre de sesión
68d8a549-9264-4ec0-8d13-532728c5b436	\N	LOGIN_FAILED	users	\N	{}	2026-11-23 23:50:56.619872-05	FAILED	Intento de inicio de sesión fallido
fce4aae5-f6e2-4a9b-aa60-f13f6552625b	\N	LOGIN_FAILED	users	\N	{}	2026-11-23 23:51:04.729084-05	FAILED	Intento de inicio de sesión fallido
032bb940-5e22-493f-934a-548d6b5a80cd	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-23 23:51:18.769666-05	SUCCESS	login
f4622ee0-4566-428e-932a-f826ff50693f	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE	users	1772db5f-a271-4cc9-a084-5a4eb784a9ab	{}	2026-11-23 23:52:38.412226-05	SUCCESS	create
5bb9ec13-e81f-4612-ac2b-0df8f3a637c1	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-23 23:52:40.495291-05	SUCCESS	Cierre de sesión
6b50fa02-231f-4486-b3bb-351c6a6a30da	1772db5f-a271-4cc9-a084-5a4eb784a9ab	LOGIN	users	1772db5f-a271-4cc9-a084-5a4eb784a9ab	{}	2026-11-23 23:52:51.546846-05	SUCCESS	login
3f7c0628-6439-416a-b68a-e6d02c2b1b26	1772db5f-a271-4cc9-a084-5a4eb784a9ab	LOGOUT	users	1772db5f-a271-4cc9-a084-5a4eb784a9ab	{}	2026-11-23 23:53:09.171301-05	SUCCESS	Cierre de sesión
eaf38fd9-b66c-4c21-b045-2bc40b28ddf1	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-23 23:53:48.888822-05	SUCCESS	login
966b84c5-22e7-4dde-9057-8af6270a2952	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-24 00:23:04.866169-05	SUCCESS	login
a970f50c-aa43-45d4-a0cb-aaa48f4021b7	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	DECIDE_QUOTATION	quotation	2e9edc32-851d-4795-99d5-b2b06742456b	{}	2026-11-24 00:23:51.142895-05	SUCCESS	Cotización rechazada para la orden e90e9fde-5f78-464d-9ae3-e8236935baa1
76688c92-abfd-4be0-b430-05bd957074a7	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGOUT	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-24 00:23:58.921253-05	SUCCESS	Cierre de sesión
3b002a25-7638-47c5-b9f0-84d5c03b5559	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	LOGIN	users	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	{}	2026-11-24 00:24:04.836171-05	SUCCESS	login
505229aa-5944-4af3-b5ce-e6a3f94709c6	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	CREATE_QUOTATION	quotation	4cfe5bb5-a2a3-4b6f-a592-fe4e450d4a9c	{}	2026-11-24 00:43:01.952969-05	SUCCESS	Cotización creada para la orden e90e9fde-5f78-464d-9ae3-e8236935baa1
619ff5b0-3284-4d88-b66b-64e8b5212922	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	DECIDE_QUOTATION	quotation	4cfe5bb5-a2a3-4b6f-a592-fe4e450d4a9c	{}	2026-11-24 00:43:04.482029-05	SUCCESS	Cotización autorizada para la orden e90e9fde-5f78-464d-9ae3-e8236935baa1
\.


--
-- TOC entry 5375 (class 0 OID 17439)
-- Dependencies: 238
-- Data for Name: system_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_settings (key, value, updated_by, updated_at) FROM stdin;
\.


--
-- TOC entry 5369 (class 0 OID 17273)
-- Dependencies: 232
-- Data for Name: technical_attentions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.technical_attentions (id, order_id, technician_id, diagnosis, actions_performed, recommendations, started_at, finished_at, created_at, updated_at, performed_tests, parts_used, observations, result_summary, updated_by) FROM stdin;
0665c9c3-6098-4aa1-a787-4d313c938b32	4eac7b12-84dc-4176-bc51-2e1807855335	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	pantallazo azul del sistema operativo	se procedio a revisar el sistema y ver si se restaura		2026-10-18 00:00:00-05	2026-10-18 17:47:12.522959-05	2026-10-18 17:47:12.502693-05	2026-10-18 17:47:12.522959-05	se hizo el inicio con un mini sistema para realizar verificaciones		se procedio al cambio de disco duroi tambien se observo falta de mantenimeinto	se hizo el cambio del disco duro ya que era el responsable del problema ademas se hizo la nueva instalacion del sistema mas sus programas basicos en el disco	3b5b21e1-2d91-4a99-8eb6-37f67b06522b
13f75d6e-024e-4e77-a1c0-20f02845ea54	7b4a854d-825e-46e4-b401-9d6fad370dc3	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	Cabezal de impresion obstruido, suciedad en los rodillo y el los sensores del jalado del papel y pro ultimo escaner en deterioro	se hizo el lavado del cabezal de impresion, se procedio a dar mantenimiento interno a toda la impresora y se hizo el cambio de escaner		2026-11-06 00:00:00-05	2026-11-06 23:05:15.065028-05	2026-11-06 23:05:15.034821-05	2026-11-06 23:05:15.065028-05	se realizo impresiones a colores  con varios tipos de papel ademas de escanos a color y blanco y negro	escaner de impresora	efectura mantenimiento cada 6 meses de acuerdo a l uso	se soluciono correctamente el detalle que se registro ademas se verifico el contador de impresion y se resetio para que el cliente no tenga dificutades mas adelante	3b5b21e1-2d91-4a99-8eb6-37f67b06522b
ae74f69c-d04b-435e-8beb-fab1f59ff99a	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	b31dd59d-f191-48a3-9970-7e3803b86707	error en la entrada de corriente	se cambio el conector		2026-11-07 00:00:00-05	2026-11-07 19:29:37.747092-05	2026-11-07 19:29:37.713071-05	2026-11-07 19:29:37.747092-05	se probo y verifico la carga	conecion interna de corriente	placa en mal estado	quedo operativo	b31dd59d-f191-48a3-9970-7e3803b86707
\.


--
-- TOC entry 5367 (class 0 OID 17200)
-- Dependencies: 230
-- Data for Name: technician_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.technician_assignments (id, order_id, technician_id, assigned_by, assigned_at, ended_at, notes) FROM stdin;
963afc15-5060-44be-9c6e-0f20b0a5985a	4eac7b12-84dc-4176-bc51-2e1807855335	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	2026-10-18 13:46:46.968835-05	\N	
ab4a487c-5ee0-49f4-9029-91139fa1beaf	7b4a854d-825e-46e4-b401-9d6fad370dc3	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	ed8565ad-31a6-4bf7-bfaa-518602317906	2026-11-06 22:09:05.30923-05	\N	revision de manera obligatoria limpieza
822f6a54-cd4b-4721-a678-cc3781384070	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	3b5b21e1-2d91-4a99-8eb6-37f67b06522b	ed8565ad-31a6-4bf7-bfaa-518602317906	2026-11-06 22:09:19.308211-05	2026-11-06 22:10:55.42995-05	
c94de395-e31a-4dd5-857a-e939cdfb7c15	e05a6517-c7d2-40a4-bfdc-8d27b085e5eb	b31dd59d-f191-48a3-9970-7e3803b86707	ed8565ad-31a6-4bf7-bfaa-518602317906	2026-11-06 22:10:55.42995-05	\N	
\.


--
-- TOC entry 5360 (class 0 OID 17015)
-- Dependencies: 223
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, first_name, last_name, username, password_hash, role_code, active, created_at, updated_at) FROM stdin;
b06d57c8-b2a0-4ca2-8dd8-f2fd5f2a65b1	Administrador	Sistema	admin	$2a$12$qzpBtt0yUo3ExAhtkx5/f.MmiCGdVymwKJryoqlQYBWgrYjpIVvju	ADMINISTRADOR	t	2026-10-03 14:26:11.662849-05	2026-10-03 14:27:10.734237-05
3b5b21e1-2d91-4a99-8eb6-37f67b06522b	Erick Manuel	Ruiz Guerra	eruiz	$2a$12$OGQhx9QLUv1SRA4v7doTyegS8mTqPBy.k83kHihQzX7fAJXWTaMcq	TÉCNICO	t	2026-10-09 01:13:48.289292-05	2026-10-09 01:13:48.289292-05
a0c876e3-bec6-42b5-b41d-61820615ebf5	Practicas	Sistema	sis	$2a$12$a49GP9KThtnBdWingvNk..W3/qeaIPfkAJiejPcMmAhmDsxxzmFNG	PERSONAL DE ATENCIÓN	t	2026-10-31 20:50:56.043893-05	2026-10-31 20:50:56.043893-05
ed8565ad-31a6-4bf7-bfaa-518602317906	Usuario	tester	QA	$2a$12$XzvGh66PnZh3IhJ9UUZQX.KB7.lDyyOlfiozxLAXUkNS79eaM2PVS	ADMINISTRADOR	t	2026-10-31 20:50:18.297851-05	2026-10-31 20:53:52.546359-05
b31dd59d-f191-48a3-9970-7e3803b86707	Jean	Celiz Paredes	jceliz	$2a$12$SJVu.JFH/AM/9w.Nm3/2MOHBNe9AgwcxWrKAXtSD0qpCc2wDXF8YC	TÉCNICO	t	2026-10-03 18:52:39.099246-05	2026-11-06 22:10:39.870277-05
1772db5f-a271-4cc9-a084-5a4eb784a9ab	Maria	ruiz	mruiz	$2a$12$mq2VbNaM/y25Jq.tjvQyYeMozLIkPi9Wd66ieuwpda4px/8wyIOnK	PERSONAL DE ATENCIÓN	t	2026-11-23 23:52:38.412226-05	2026-11-23 23:52:38.412226-05
\.


--
-- TOC entry 5384 (class 0 OID 0)
-- Dependencies: 228
-- Name: service_order_number_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.service_order_number_seq', 4, true);


--
-- TOC entry 5128 (class 2606 OID 17330)
-- Name: ai_prediagnoses ai_prediagnoses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_prediagnoses
    ADD CONSTRAINT ai_prediagnoses_pkey PRIMARY KEY (id);


--
-- TOC entry 5132 (class 2606 OID 17361)
-- Name: ai_validations ai_validations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_validations
    ADD CONSTRAINT ai_validations_pkey PRIMARY KEY (id);


--
-- TOC entry 5134 (class 2606 OID 17363)
-- Name: ai_validations ai_validations_prediagnosis_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_validations
    ADD CONSTRAINT ai_validations_prediagnosis_id_key UNIQUE (prediagnosis_id);


--
-- TOC entry 5143 (class 2606 OID 17414)
-- Name: backup_runs backup_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.backup_runs
    ADD CONSTRAINT backup_runs_pkey PRIMARY KEY (id);


--
-- TOC entry 5037 (class 2606 OID 24577)
-- Name: clients clients_email_required_and_valid; Type: CHECK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE public.clients
    ADD CONSTRAINT clients_email_required_and_valid CHECK ((((email)::text = btrim((email)::text)) AND ((email)::text <> ''::text) AND ((email)::text ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::text))) NOT VALID;


--
-- TOC entry 5039 (class 2606 OID 24576)
-- Name: clients clients_phone_nine_digits; Type: CHECK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE public.clients
    ADD CONSTRAINT clients_phone_nine_digits CHECK (((phone)::text ~ '^[0-9]{9}$'::text)) NOT VALID;


--
-- TOC entry 5095 (class 2606 OID 17074)
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- TOC entry 5158 (class 2606 OID 32896)
-- Name: equipment_deliveries equipment_deliveries_order_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipment_deliveries
    ADD CONSTRAINT equipment_deliveries_order_id_key UNIQUE (order_id);


--
-- TOC entry 5160 (class 2606 OID 32894)
-- Name: equipment_deliveries equipment_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipment_deliveries
    ADD CONSTRAINT equipment_deliveries_pkey PRIMARY KEY (id);


--
-- TOC entry 5098 (class 2606 OID 17105)
-- Name: equipment equipment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipment
    ADD CONSTRAINT equipment_pkey PRIMARY KEY (id);


--
-- TOC entry 5078 (class 2606 OID 16980)
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


--
-- TOC entry 5146 (class 2606 OID 17437)
-- Name: monitoring_checks monitoring_checks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monitoring_checks
    ADD CONSTRAINT monitoring_checks_pkey PRIMARY KEY (id);


--
-- TOC entry 5122 (class 2606 OID 17250)
-- Name: order_status_history order_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5105 (class 2606 OID 17131)
-- Name: order_status_transitions order_status_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_transitions
    ADD CONSTRAINT order_status_transitions_pkey PRIMARY KEY (from_status, to_status);


--
-- TOC entry 5101 (class 2606 OID 17123)
-- Name: order_statuses order_statuses_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_statuses
    ADD CONSTRAINT order_statuses_name_key UNIQUE (name);


--
-- TOC entry 5103 (class 2606 OID 17121)
-- Name: order_statuses order_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_statuses
    ADD CONSTRAINT order_statuses_pkey PRIMARY KEY (code);


--
-- TOC entry 5085 (class 2606 OID 16997)
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (code);


--
-- TOC entry 5155 (class 2606 OID 32862)
-- Name: quotation_item quotation_item_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quotation_item
    ADD CONSTRAINT quotation_item_pkey PRIMARY KEY (id);


--
-- TOC entry 5151 (class 2606 OID 32825)
-- Name: quotation quotation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quotation
    ADD CONSTRAINT quotation_pkey PRIMARY KEY (id);


--
-- TOC entry 5087 (class 2606 OID 17004)
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_code, permission_code);


--
-- TOC entry 5081 (class 2606 OID 16990)
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- TOC entry 5083 (class 2606 OID 16988)
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (code);


--
-- TOC entry 5109 (class 2606 OID 17175)
-- Name: service_orders service_orders_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_number_key UNIQUE (number);


--
-- TOC entry 5111 (class 2606 OID 17173)
-- Name: service_orders service_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_pkey PRIMARY KEY (id);


--
-- TOC entry 5141 (class 2606 OID 17390)
-- Name: system_events system_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_events
    ADD CONSTRAINT system_events_pkey PRIMARY KEY (id);


--
-- TOC entry 5149 (class 2606 OID 17449)
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (key);


--
-- TOC entry 5126 (class 2606 OID 17296)
-- Name: technical_attentions technical_attentions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technical_attentions
    ADD CONSTRAINT technical_attentions_pkey PRIMARY KEY (id);


--
-- TOC entry 5118 (class 2606 OID 17216)
-- Name: technician_assignments technician_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_pkey PRIMARY KEY (id);


--
-- TOC entry 5089 (class 2606 OID 17035)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 5114 (class 1259 OID 17234)
-- Name: assignments_assigner_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX assignments_assigner_idx ON public.technician_assignments USING btree (assigned_by);


--
-- TOC entry 5115 (class 1259 OID 17232)
-- Name: assignments_one_current; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX assignments_one_current ON public.technician_assignments USING btree (order_id) WHERE (ended_at IS NULL);


--
-- TOC entry 5116 (class 1259 OID 17233)
-- Name: assignments_technician_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX assignments_technician_idx ON public.technician_assignments USING btree (technician_id, assigned_at);


--
-- TOC entry 5123 (class 1259 OID 17307)
-- Name: attentions_order_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attentions_order_idx ON public.technical_attentions USING btree (order_id, created_at);


--
-- TOC entry 5124 (class 1259 OID 17308)
-- Name: attentions_technician_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attentions_technician_idx ON public.technical_attentions USING btree (technician_id);


--
-- TOC entry 5144 (class 1259 OID 17420)
-- Name: backups_requester_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX backups_requester_idx ON public.backup_runs USING btree (requested_by);


--
-- TOC entry 5092 (class 1259 OID 17075)
-- Name: clients_document_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX clients_document_unique ON public.clients USING btree (lower((document_number)::text));


--
-- TOC entry 5093 (class 1259 OID 24578)
-- Name: clients_email_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX clients_email_unique ON public.clients USING btree (lower(btrim((email)::text))) WHERE (btrim((email)::text) <> ''::text);


--
-- TOC entry 5096 (class 1259 OID 17112)
-- Name: equipment_client_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX equipment_client_idx ON public.equipment USING btree (client_id);


--
-- TOC entry 5099 (class 1259 OID 17111)
-- Name: equipment_serial_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX equipment_serial_unique ON public.equipment USING btree (lower((serial_number)::text)) WHERE ((serial_number)::text <> ''::text);


--
-- TOC entry 5136 (class 1259 OID 17396)
-- Name: events_actor_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX events_actor_idx ON public.system_events USING btree (actor_id);


--
-- TOC entry 5137 (class 1259 OID 17397)
-- Name: events_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX events_date_idx ON public.system_events USING btree (occurred_at);


--
-- TOC entry 5138 (class 1259 OID 17398)
-- Name: events_entity_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX events_entity_idx ON public.system_events USING btree (entity_type, entity_id);


--
-- TOC entry 5139 (class 1259 OID 24606)
-- Name: events_result_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX events_result_date_idx ON public.system_events USING btree (result, occurred_at DESC);


--
-- TOC entry 5079 (class 1259 OID 16981)
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX flyway_schema_history_s_idx ON public.flyway_schema_history USING btree (success);


--
-- TOC entry 5147 (class 1259 OID 17438)
-- Name: monitoring_component_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX monitoring_component_date_idx ON public.monitoring_checks USING btree (component, checked_at);


--
-- TOC entry 5119 (class 1259 OID 17271)
-- Name: order_history_order_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX order_history_order_idx ON public.order_status_history USING btree (order_id, changed_at);


--
-- TOC entry 5120 (class 1259 OID 17272)
-- Name: order_history_user_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX order_history_user_idx ON public.order_status_history USING btree (changed_by);


--
-- TOC entry 5129 (class 1259 OID 17341)
-- Name: prediagnoses_order_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX prediagnoses_order_idx ON public.ai_prediagnoses USING btree (order_id, requested_at);


--
-- TOC entry 5130 (class 1259 OID 17342)
-- Name: prediagnoses_requester_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX prediagnoses_requester_idx ON public.ai_prediagnoses USING btree (requested_by);


--
-- TOC entry 5156 (class 1259 OID 32868)
-- Name: quotation_items_quotation_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX quotation_items_quotation_idx ON public.quotation_item USING btree (quotation_id);


--
-- TOC entry 5152 (class 1259 OID 32841)
-- Name: quotations_one_pending_per_order; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX quotations_one_pending_per_order ON public.quotation USING btree (order_id) WHERE ((status)::text = 'PENDIENTE'::text);


--
-- TOC entry 5153 (class 1259 OID 32842)
-- Name: quotations_order_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX quotations_order_idx ON public.quotation USING btree (order_id, created_at);


--
-- TOC entry 5106 (class 1259 OID 17197)
-- Name: service_orders_client_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX service_orders_client_idx ON public.service_orders USING btree (client_id);


--
-- TOC entry 5107 (class 1259 OID 17196)
-- Name: service_orders_equipment_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX service_orders_equipment_idx ON public.service_orders USING btree (equipment_id);


--
-- TOC entry 5112 (class 1259 OID 17199)
-- Name: service_orders_receiver_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX service_orders_receiver_idx ON public.service_orders USING btree (received_by);


--
-- TOC entry 5113 (class 1259 OID 17198)
-- Name: service_orders_status_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX service_orders_status_date_idx ON public.service_orders USING btree (status_code, created_at);


--
-- TOC entry 5090 (class 1259 OID 17042)
-- Name: users_role_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX users_role_idx ON public.users USING btree (role_code);


--
-- TOC entry 5091 (class 1259 OID 17041)
-- Name: users_username_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX users_username_unique ON public.users USING btree (lower((username)::text));


--
-- TOC entry 5135 (class 1259 OID 17374)
-- Name: validations_technician_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX validations_technician_idx ON public.ai_validations USING btree (technician_id);


--
-- TOC entry 5201 (class 2620 OID 17458)
-- Name: technician_assignments assignment_technician; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER assignment_technician BEFORE INSERT OR UPDATE OF technician_id ON public.technician_assignments FOR EACH ROW EXECUTE FUNCTION public.validate_technician();


--
-- TOC entry 5202 (class 2620 OID 17459)
-- Name: technical_attentions attention_technician; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER attention_technician BEFORE INSERT OR UPDATE OF technician_id ON public.technical_attentions FOR EACH ROW EXECUTE FUNCTION public.validate_technician();


--
-- TOC entry 5196 (class 2620 OID 17465)
-- Name: clients clients_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER clients_updated_at BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 5197 (class 2620 OID 17466)
-- Name: equipment equipment_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER equipment_updated_at BEFORE UPDATE ON public.equipment FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 5198 (class 2620 OID 17462)
-- Name: service_orders order_transition; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER order_transition BEFORE UPDATE OF status_code ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public.validate_status_transition();


--
-- TOC entry 5206 (class 2620 OID 32919)
-- Name: quotation quotation_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER quotation_updated_at BEFORE UPDATE ON public.quotation FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 5199 (class 2620 OID 17456)
-- Name: service_orders service_order_owner; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER service_order_owner BEFORE INSERT OR UPDATE OF equipment_id, client_id ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public.validate_order_owner();


--
-- TOC entry 5200 (class 2620 OID 17467)
-- Name: service_orders service_orders_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER service_orders_updated_at BEFORE UPDATE ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 5205 (class 2620 OID 17469)
-- Name: system_settings system_settings_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER system_settings_updated_at BEFORE UPDATE ON public.system_settings FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 5203 (class 2620 OID 17468)
-- Name: technical_attentions technical_attentions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER technical_attentions_updated_at BEFORE UPDATE ON public.technical_attentions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 5195 (class 2620 OID 17464)
-- Name: users users_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 5204 (class 2620 OID 17460)
-- Name: ai_validations validation_technician; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER validation_technician BEFORE INSERT OR UPDATE OF technician_id ON public.ai_validations FOR EACH ROW EXECUTE FUNCTION public.validate_technician();


--
-- TOC entry 5182 (class 2606 OID 17331)
-- Name: ai_prediagnoses ai_prediagnoses_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_prediagnoses
    ADD CONSTRAINT ai_prediagnoses_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.service_orders(id) ON DELETE RESTRICT;


--
-- TOC entry 5183 (class 2606 OID 17336)
-- Name: ai_prediagnoses ai_prediagnoses_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_prediagnoses
    ADD CONSTRAINT ai_prediagnoses_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.users(id);


--
-- TOC entry 5184 (class 2606 OID 17364)
-- Name: ai_validations ai_validations_prediagnosis_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_validations
    ADD CONSTRAINT ai_validations_prediagnosis_id_fkey FOREIGN KEY (prediagnosis_id) REFERENCES public.ai_prediagnoses(id) ON DELETE RESTRICT;


--
-- TOC entry 5185 (class 2606 OID 17369)
-- Name: ai_validations ai_validations_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_validations
    ADD CONSTRAINT ai_validations_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.users(id);


--
-- TOC entry 5187 (class 2606 OID 17415)
-- Name: backup_runs backup_runs_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.backup_runs
    ADD CONSTRAINT backup_runs_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.users(id);


--
-- TOC entry 5164 (class 2606 OID 17106)
-- Name: equipment equipment_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipment
    ADD CONSTRAINT equipment_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- TOC entry 5193 (class 2606 OID 32897)
-- Name: equipment_deliveries equipment_deliveries_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipment_deliveries
    ADD CONSTRAINT equipment_deliveries_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.service_orders(id) ON DELETE RESTRICT;


--
-- TOC entry 5194 (class 2606 OID 32902)
-- Name: equipment_deliveries equipment_deliveries_responsible_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipment_deliveries
    ADD CONSTRAINT equipment_deliveries_responsible_id_fkey FOREIGN KEY (responsible_id) REFERENCES public.users(id);


--
-- TOC entry 5175 (class 2606 OID 17266)
-- Name: order_status_history order_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);


--
-- TOC entry 5176 (class 2606 OID 17256)
-- Name: order_status_history order_status_history_from_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_from_status_fkey FOREIGN KEY (from_status) REFERENCES public.order_statuses(code);


--
-- TOC entry 5177 (class 2606 OID 17251)
-- Name: order_status_history order_status_history_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.service_orders(id) ON DELETE RESTRICT;


--
-- TOC entry 5178 (class 2606 OID 17261)
-- Name: order_status_history order_status_history_to_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_to_status_fkey FOREIGN KEY (to_status) REFERENCES public.order_statuses(code);


--
-- TOC entry 5165 (class 2606 OID 17132)
-- Name: order_status_transitions order_status_transitions_from_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_transitions
    ADD CONSTRAINT order_status_transitions_from_status_fkey FOREIGN KEY (from_status) REFERENCES public.order_statuses(code);


--
-- TOC entry 5166 (class 2606 OID 17137)
-- Name: order_status_transitions order_status_transitions_to_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status_transitions
    ADD CONSTRAINT order_status_transitions_to_status_fkey FOREIGN KEY (to_status) REFERENCES public.order_statuses(code);


--
-- TOC entry 5189 (class 2606 OID 32831)
-- Name: quotation quotation_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quotation
    ADD CONSTRAINT quotation_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5190 (class 2606 OID 32836)
-- Name: quotation quotation_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quotation
    ADD CONSTRAINT quotation_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.users(id);


--
-- TOC entry 5192 (class 2606 OID 32863)
-- Name: quotation_item quotation_item_quotation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quotation_item
    ADD CONSTRAINT quotation_item_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES public.quotation(id) ON DELETE CASCADE;


--
-- TOC entry 5191 (class 2606 OID 32826)
-- Name: quotation quotation_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quotation
    ADD CONSTRAINT quotation_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.service_orders(id) ON DELETE RESTRICT;


--
-- TOC entry 5161 (class 2606 OID 17010)
-- Name: role_permissions role_permissions_permission_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_code_fkey FOREIGN KEY (permission_code) REFERENCES public.permissions(code);


--
-- TOC entry 5162 (class 2606 OID 17005)
-- Name: role_permissions role_permissions_role_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_code_fkey FOREIGN KEY (role_code) REFERENCES public.roles(code);


--
-- TOC entry 5167 (class 2606 OID 17181)
-- Name: service_orders service_orders_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- TOC entry 5168 (class 2606 OID 17176)
-- Name: service_orders service_orders_equipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES public.equipment(id) ON DELETE RESTRICT;


--
-- TOC entry 5169 (class 2606 OID 24594)
-- Name: service_orders service_orders_finalized_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_finalized_by_fkey FOREIGN KEY (finalized_by) REFERENCES public.users(id);


--
-- TOC entry 5170 (class 2606 OID 17186)
-- Name: service_orders service_orders_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.users(id);


--
-- TOC entry 5171 (class 2606 OID 17191)
-- Name: service_orders service_orders_status_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_status_code_fkey FOREIGN KEY (status_code) REFERENCES public.order_statuses(code);


--
-- TOC entry 5186 (class 2606 OID 17391)
-- Name: system_events system_events_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_events
    ADD CONSTRAINT system_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- TOC entry 5188 (class 2606 OID 17450)
-- Name: system_settings system_settings_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5179 (class 2606 OID 17297)
-- Name: technical_attentions technical_attentions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technical_attentions
    ADD CONSTRAINT technical_attentions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.service_orders(id) ON DELETE RESTRICT;


--
-- TOC entry 5180 (class 2606 OID 17302)
-- Name: technical_attentions technical_attentions_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technical_attentions
    ADD CONSTRAINT technical_attentions_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.users(id);


--
-- TOC entry 5181 (class 2606 OID 24589)
-- Name: technical_attentions technical_attentions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technical_attentions
    ADD CONSTRAINT technical_attentions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5172 (class 2606 OID 17227)
-- Name: technician_assignments technician_assignments_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.users(id);


--
-- TOC entry 5173 (class 2606 OID 17217)
-- Name: technician_assignments technician_assignments_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.service_orders(id) ON DELETE RESTRICT;


--
-- TOC entry 5174 (class 2606 OID 17222)
-- Name: technician_assignments technician_assignments_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.users(id);


--
-- TOC entry 5163 (class 2606 OID 17036)
-- Name: users users_role_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_code_fkey FOREIGN KEY (role_code) REFERENCES public.roles(code);

