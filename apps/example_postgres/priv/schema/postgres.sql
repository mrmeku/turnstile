--
-- PostgreSQL database dump
--


-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

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
-- Name: turnstile_document_decontrol(bigint); Type: FUNCTION; Schema: public; Owner: turnstile_owner
--

CREATE FUNCTION public.turnstile_document_decontrol(document bigint) RETURNS timestamp without time zone
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$SELECT decontrol FROM documents WHERE id = document$$;


ALTER FUNCTION public.turnstile_document_decontrol(document bigint) OWNER TO turnstile_owner;

--
-- Name: turnstile_document_office(bigint); Type: FUNCTION; Schema: public; Owner: turnstile_owner
--

CREATE FUNCTION public.turnstile_document_office(document bigint) RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$SELECT designating_office_id FROM documents WHERE id = document$$;


ALTER FUNCTION public.turnstile_document_office(document bigint) OWNER TO turnstile_owner;

--
-- Name: turnstile_document_program(bigint); Type: FUNCTION; Schema: public; Owner: turnstile_owner
--

CREATE FUNCTION public.turnstile_document_program(document bigint) RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$SELECT program_id FROM documents WHERE id = document$$;


ALTER FUNCTION public.turnstile_document_program(document bigint) OWNER TO turnstile_owner;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_roles; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.account_roles (
    id bigint NOT NULL,
    user_id text NOT NULL,
    role text NOT NULL
);


ALTER TABLE public.account_roles OWNER TO turnstile_owner;

--
-- Name: account_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.account_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.account_roles_id_seq OWNER TO turnstile_owner;

--
-- Name: account_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.account_roles_id_seq OWNED BY public.account_roles.id;


--
-- Name: agencies; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.agencies (
    id bigint NOT NULL,
    name text NOT NULL,
    nationality text NOT NULL
);


ALTER TABLE public.agencies OWNER TO turnstile_owner;

--
-- Name: agencies_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.agencies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.agencies_id_seq OWNER TO turnstile_owner;

--
-- Name: agencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.agencies_id_seq OWNED BY public.agencies.id;


--
-- Name: assignments; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.assignments (
    id bigint NOT NULL,
    user_id text NOT NULL,
    program_id bigint NOT NULL,
    role text NOT NULL
);


ALTER TABLE public.assignments OWNER TO turnstile_owner;

--
-- Name: assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.assignments_id_seq OWNER TO turnstile_owner;

--
-- Name: assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.assignments_id_seq OWNED BY public.assignments.id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.categories (
    name text NOT NULL,
    specified boolean DEFAULT false NOT NULL,
    implied_controls text[] DEFAULT ARRAY[]::text[] NOT NULL
);


ALTER TABLE public.categories OWNER TO turnstile_owner;

--
-- Name: documents; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.documents (
    id bigint NOT NULL,
    title text NOT NULL,
    decontrol timestamp(0) without time zone,
    program_id bigint NOT NULL,
    designating_office_id bigint NOT NULL
);

ALTER TABLE ONLY public.documents FORCE ROW LEVEL SECURITY;


ALTER TABLE public.documents OWNER TO turnstile_owner;

--
-- Name: documents_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.documents_id_seq OWNER TO turnstile_owner;

--
-- Name: documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.documents_id_seq OWNED BY public.documents.id;


--
-- Name: marking_proposals; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.marking_proposals (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    proposer_id text NOT NULL,
    approver_id text,
    status text DEFAULT 'pending'::text NOT NULL,
    categories text[] DEFAULT ARRAY[]::text[] NOT NULL,
    controls text[] DEFAULT ARRAY[]::text[] NOT NULL,
    releasable_to text[] DEFAULT ARRAY[]::text[] NOT NULL,
    list text[] DEFAULT ARRAY[]::text[] NOT NULL
);

ALTER TABLE ONLY public.marking_proposals FORCE ROW LEVEL SECURITY;


ALTER TABLE public.marking_proposals OWNER TO turnstile_owner;

--
-- Name: marking_proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.marking_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.marking_proposals_id_seq OWNER TO turnstile_owner;

--
-- Name: marking_proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.marking_proposals_id_seq OWNED BY public.marking_proposals.id;


--
-- Name: markings; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.markings (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    categories text[] DEFAULT ARRAY[]::text[] NOT NULL,
    controls text[] DEFAULT ARRAY[]::text[] NOT NULL,
    releasable_to text[] DEFAULT ARRAY[]::text[] NOT NULL,
    list text[] DEFAULT ARRAY[]::text[] NOT NULL
);

ALTER TABLE ONLY public.markings FORCE ROW LEVEL SECURITY;


ALTER TABLE public.markings OWNER TO turnstile_owner;

--
-- Name: markings_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.markings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.markings_id_seq OWNER TO turnstile_owner;

--
-- Name: markings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.markings_id_seq OWNED BY public.markings.id;


--
-- Name: office_roles; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.office_roles (
    id bigint NOT NULL,
    user_id text NOT NULL,
    office_id bigint NOT NULL,
    role text NOT NULL
);


ALTER TABLE public.office_roles OWNER TO turnstile_owner;

--
-- Name: office_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.office_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.office_roles_id_seq OWNER TO turnstile_owner;

--
-- Name: office_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.office_roles_id_seq OWNED BY public.office_roles.id;


--
-- Name: offices; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.offices (
    id bigint NOT NULL,
    name text NOT NULL,
    agency_id bigint NOT NULL
);


ALTER TABLE public.offices OWNER TO turnstile_owner;

--
-- Name: offices_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.offices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.offices_id_seq OWNER TO turnstile_owner;

--
-- Name: offices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.offices_id_seq OWNED BY public.offices.id;


--
-- Name: override_reports; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.override_reports (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    office_id bigint NOT NULL,
    user_id text NOT NULL,
    justification text NOT NULL,
    operation_id text NOT NULL,
    at timestamp(0) without time zone NOT NULL
);


ALTER TABLE public.override_reports OWNER TO turnstile_owner;

--
-- Name: override_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.override_reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.override_reports_id_seq OWNER TO turnstile_owner;

--
-- Name: override_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.override_reports_id_seq OWNED BY public.override_reports.id;


--
-- Name: portions; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.portions (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    body text NOT NULL,
    categories text[] DEFAULT ARRAY[]::text[] NOT NULL,
    controls text[] DEFAULT ARRAY[]::text[] NOT NULL,
    releasable_to text[] DEFAULT ARRAY[]::text[] NOT NULL
);

ALTER TABLE ONLY public.portions FORCE ROW LEVEL SECURITY;


ALTER TABLE public.portions OWNER TO turnstile_owner;

--
-- Name: portions_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.portions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portions_id_seq OWNER TO turnstile_owner;

--
-- Name: portions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.portions_id_seq OWNED BY public.portions.id;


--
-- Name: programs; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.programs (
    id bigint NOT NULL,
    name text NOT NULL,
    closed_at timestamp(0) without time zone,
    office_id bigint NOT NULL
);


ALTER TABLE public.programs OWNER TO turnstile_owner;

--
-- Name: programs_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.programs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.programs_id_seq OWNER TO turnstile_owner;

--
-- Name: programs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.programs_id_seq OWNED BY public.programs.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


ALTER TABLE public.schema_migrations OWNER TO turnstile_owner;

--
-- Name: turnstile_ledger_counter; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.turnstile_ledger_counter (
    name text NOT NULL,
    "position" bigint NOT NULL
);


ALTER TABLE public.turnstile_ledger_counter OWNER TO turnstile_owner;

--
-- Name: turnstile_ledger_events; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.turnstile_ledger_events (
    id bigint NOT NULL,
    "position" bigint NOT NULL,
    kind text NOT NULL,
    subject_ref jsonb,
    object_ref jsonb,
    attribute text,
    old jsonb,
    new jsonb,
    operation_id text NOT NULL,
    at timestamp with time zone NOT NULL,
    by jsonb NOT NULL
);


ALTER TABLE public.turnstile_ledger_events OWNER TO turnstile_owner;

--
-- Name: turnstile_ledger_events_id_seq; Type: SEQUENCE; Schema: public; Owner: turnstile_owner
--

CREATE SEQUENCE public.turnstile_ledger_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.turnstile_ledger_events_id_seq OWNER TO turnstile_owner;

--
-- Name: turnstile_ledger_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: turnstile_owner
--

ALTER SEQUENCE public.turnstile_ledger_events_id_seq OWNED BY public.turnstile_ledger_events.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: turnstile_owner
--

CREATE TABLE public.users (
    id text NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    person_id text NOT NULL,
    employment text NOT NULL,
    nationality text NOT NULL
);


ALTER TABLE public.users OWNER TO turnstile_owner;

--
-- Name: account_roles id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.account_roles ALTER COLUMN id SET DEFAULT nextval('public.account_roles_id_seq'::regclass);


--
-- Name: agencies id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.agencies ALTER COLUMN id SET DEFAULT nextval('public.agencies_id_seq'::regclass);


--
-- Name: assignments id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.assignments ALTER COLUMN id SET DEFAULT nextval('public.assignments_id_seq'::regclass);


--
-- Name: documents id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.documents ALTER COLUMN id SET DEFAULT nextval('public.documents_id_seq'::regclass);


--
-- Name: marking_proposals id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.marking_proposals ALTER COLUMN id SET DEFAULT nextval('public.marking_proposals_id_seq'::regclass);


--
-- Name: markings id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.markings ALTER COLUMN id SET DEFAULT nextval('public.markings_id_seq'::regclass);


--
-- Name: office_roles id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.office_roles ALTER COLUMN id SET DEFAULT nextval('public.office_roles_id_seq'::regclass);


--
-- Name: offices id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.offices ALTER COLUMN id SET DEFAULT nextval('public.offices_id_seq'::regclass);


--
-- Name: override_reports id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.override_reports ALTER COLUMN id SET DEFAULT nextval('public.override_reports_id_seq'::regclass);


--
-- Name: portions id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.portions ALTER COLUMN id SET DEFAULT nextval('public.portions_id_seq'::regclass);


--
-- Name: programs id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.programs ALTER COLUMN id SET DEFAULT nextval('public.programs_id_seq'::regclass);


--
-- Name: turnstile_ledger_events id; Type: DEFAULT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.turnstile_ledger_events ALTER COLUMN id SET DEFAULT nextval('public.turnstile_ledger_events_id_seq'::regclass);


--
-- Name: account_roles account_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.account_roles
    ADD CONSTRAINT account_roles_pkey PRIMARY KEY (id);


--
-- Name: agencies agencies_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.agencies
    ADD CONSTRAINT agencies_pkey PRIMARY KEY (id);


--
-- Name: assignments assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (name);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: marking_proposals marking_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.marking_proposals
    ADD CONSTRAINT marking_proposals_pkey PRIMARY KEY (id);


--
-- Name: markings markings_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.markings
    ADD CONSTRAINT markings_pkey PRIMARY KEY (id);


--
-- Name: office_roles office_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.office_roles
    ADD CONSTRAINT office_roles_pkey PRIMARY KEY (id);


--
-- Name: offices offices_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_pkey PRIMARY KEY (id);


--
-- Name: override_reports override_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.override_reports
    ADD CONSTRAINT override_reports_pkey PRIMARY KEY (id);


--
-- Name: portions portions_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.portions
    ADD CONSTRAINT portions_pkey PRIMARY KEY (id);


--
-- Name: programs programs_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.programs
    ADD CONSTRAINT programs_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: turnstile_ledger_counter turnstile_ledger_counter_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.turnstile_ledger_counter
    ADD CONSTRAINT turnstile_ledger_counter_pkey PRIMARY KEY (name);


--
-- Name: turnstile_ledger_events turnstile_ledger_events_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.turnstile_ledger_events
    ADD CONSTRAINT turnstile_ledger_events_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: account_roles_user_id_role_index; Type: INDEX; Schema: public; Owner: turnstile_owner
--

CREATE UNIQUE INDEX account_roles_user_id_role_index ON public.account_roles USING btree (user_id, role);


--
-- Name: assignments_user_id_program_id_index; Type: INDEX; Schema: public; Owner: turnstile_owner
--

CREATE UNIQUE INDEX assignments_user_id_program_id_index ON public.assignments USING btree (user_id, program_id);


--
-- Name: markings_document_id_index; Type: INDEX; Schema: public; Owner: turnstile_owner
--

CREATE UNIQUE INDEX markings_document_id_index ON public.markings USING btree (document_id);


--
-- Name: office_roles_user_id_office_id_role_index; Type: INDEX; Schema: public; Owner: turnstile_owner
--

CREATE UNIQUE INDEX office_roles_user_id_office_id_role_index ON public.office_roles USING btree (user_id, office_id, role);


--
-- Name: turnstile_ledger_events_operation_id_index; Type: INDEX; Schema: public; Owner: turnstile_owner
--

CREATE INDEX turnstile_ledger_events_operation_id_index ON public.turnstile_ledger_events USING btree (operation_id);


--
-- Name: turnstile_ledger_events_position_index; Type: INDEX; Schema: public; Owner: turnstile_owner
--

CREATE INDEX turnstile_ledger_events_position_index ON public.turnstile_ledger_events USING btree ("position");


--
-- Name: account_roles account_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.account_roles
    ADD CONSTRAINT account_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: assignments assignments_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_program_id_fkey FOREIGN KEY (program_id) REFERENCES public.programs(id);


--
-- Name: assignments assignments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: documents documents_designating_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_designating_office_id_fkey FOREIGN KEY (designating_office_id) REFERENCES public.offices(id);


--
-- Name: documents documents_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_program_id_fkey FOREIGN KEY (program_id) REFERENCES public.programs(id);


--
-- Name: marking_proposals marking_proposals_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.marking_proposals
    ADD CONSTRAINT marking_proposals_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.users(id);


--
-- Name: marking_proposals marking_proposals_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.marking_proposals
    ADD CONSTRAINT marking_proposals_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: marking_proposals marking_proposals_proposer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.marking_proposals
    ADD CONSTRAINT marking_proposals_proposer_id_fkey FOREIGN KEY (proposer_id) REFERENCES public.users(id);


--
-- Name: markings markings_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.markings
    ADD CONSTRAINT markings_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: office_roles office_roles_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.office_roles
    ADD CONSTRAINT office_roles_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: office_roles office_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.office_roles
    ADD CONSTRAINT office_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: offices offices_agency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_agency_id_fkey FOREIGN KEY (agency_id) REFERENCES public.agencies(id);


--
-- Name: override_reports override_reports_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.override_reports
    ADD CONSTRAINT override_reports_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: override_reports override_reports_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.override_reports
    ADD CONSTRAINT override_reports_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: override_reports override_reports_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.override_reports
    ADD CONSTRAINT override_reports_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: portions portions_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.portions
    ADD CONSTRAINT portions_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: programs programs_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: turnstile_owner
--

ALTER TABLE ONLY public.programs
    ADD CONSTRAINT programs_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: documents; Type: ROW SECURITY; Schema: public; Owner: turnstile_owner
--

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

--
-- Name: marking_proposals; Type: ROW SECURITY; Schema: public; Owner: turnstile_owner
--

ALTER TABLE public.marking_proposals ENABLE ROW LEVEL SECURITY;

--
-- Name: markings; Type: ROW SECURITY; Schema: public; Owner: turnstile_owner
--

ALTER TABLE public.markings ENABLE ROW LEVEL SECURITY;

--
-- Name: portions; Type: ROW SECURITY; Schema: public; Owner: turnstile_owner
--

ALTER TABLE public.portions ENABLE ROW LEVEL SECURITY;

--
-- Name: markings turnstile_admit_select; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_admit_select ON public.markings FOR SELECT USING (true);


--
-- Name: documents turnstile_exempt_turnstile_app_insert; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_app_insert ON public.documents FOR INSERT WITH CHECK (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text)));


--
-- Name: markings turnstile_exempt_turnstile_app_insert; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_app_insert ON public.markings FOR INSERT WITH CHECK (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text)));


--
-- Name: portions turnstile_exempt_turnstile_app_insert; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_app_insert ON public.portions FOR INSERT WITH CHECK (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text)));


--
-- Name: documents turnstile_exempt_turnstile_app_select; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_app_select ON public.documents FOR SELECT USING (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text)));


--
-- Name: marking_proposals turnstile_exempt_turnstile_app_select; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_app_select ON public.marking_proposals FOR SELECT USING (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text)));


--
-- Name: portions turnstile_exempt_turnstile_app_select; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_app_select ON public.portions FOR SELECT USING (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text)));


--
-- Name: markings turnstile_exempt_turnstile_app_update; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_app_update ON public.markings FOR UPDATE USING (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text))) WITH CHECK (((CURRENT_USER = 'turnstile_app'::name) AND (COALESCE(current_setting('turnstile.operation'::text, true), ''::text) = ''::text)));


--
-- Name: documents turnstile_exempt_turnstile_owner_select; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_owner_select ON public.documents FOR SELECT USING ((CURRENT_USER = 'turnstile_owner'::name));


--
-- Name: marking_proposals turnstile_exempt_turnstile_owner_select; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_owner_select ON public.marking_proposals FOR SELECT USING ((CURRENT_USER = 'turnstile_owner'::name));


--
-- Name: portions turnstile_exempt_turnstile_owner_select; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_exempt_turnstile_owner_select ON public.portions FOR SELECT USING ((CURRENT_USER = 'turnstile_owner'::name));


--
-- Name: marking_proposals turnstile_gate_approve_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_approve_marking ON public.marking_proposals FOR UPDATE USING (true) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(marking_proposals.document_id)) AND (r.role = ANY (ARRAY['approver'::text]))))) AND (proposer_id <> current_setting('turnstile.subject_id'::text, true))));


--
-- Name: markings turnstile_gate_approve_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_approve_marking ON public.markings FOR UPDATE USING (true) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(markings.document_id)) AND (r.role = ANY (ARRAY['approver'::text]))))) AND (EXISTS ( SELECT 1
   FROM public.marking_proposals p
  WHERE ((p.document_id = markings.document_id) AND (p.status = 'pending'::text) AND (p.proposer_id <> current_setting('turnstile.subject_id'::text, true)))))));


--
-- Name: documents turnstile_gate_change_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_change_marking ON public.documents FOR UPDATE USING (true) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval))));


--
-- Name: markings turnstile_gate_change_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_change_marking ON public.markings FOR UPDATE USING (true) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(markings.document_id)) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval))));


--
-- Name: portions turnstile_gate_change_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_change_marking ON public.portions FOR UPDATE USING (true) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(portions.document_id)) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval))));


--
-- Name: documents turnstile_gate_decontrol; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_decontrol ON public.documents FOR UPDATE USING (true) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval))));


--
-- Name: marking_proposals turnstile_gate_propose_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_propose_marking ON public.marking_proposals FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(marking_proposals.document_id)) AND (r.role = ANY (ARRAY['designator'::text]))))) AND (proposer_id = current_setting('turnstile.subject_id'::text, true))));


--
-- Name: documents turnstile_gate_set_decontrol; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_gate_set_decontrol ON public.documents FOR UPDATE USING (true) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval))));


--
-- Name: documents turnstile_scope_approve_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_approve_marking ON public.documents FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'approve_marking'::text) AND (EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['approver'::text])))))));


--
-- Name: marking_proposals turnstile_scope_approve_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_approve_marking ON public.marking_proposals FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'approve_marking'::text) AND ((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(marking_proposals.document_id)) AND (r.role = ANY (ARRAY['approver'::text]))))) AND (proposer_id <> current_setting('turnstile.subject_id'::text, true)))));


--
-- Name: documents turnstile_scope_change_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_change_marking ON public.documents FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'change_marking'::text) AND ((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval)))));


--
-- Name: portions turnstile_scope_change_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_change_marking ON public.portions FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'change_marking'::text) AND ((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(portions.document_id)) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval)))));


--
-- Name: documents turnstile_scope_decontrol; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_decontrol ON public.documents FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'decontrol'::text) AND ((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval)))));


--
-- Name: documents turnstile_scope_propose_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_propose_marking ON public.documents FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'propose_marking'::text) AND (EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text])))))));


--
-- Name: marking_proposals turnstile_scope_propose_marking; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_propose_marking ON public.marking_proposals FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'propose_marking'::text) AND (EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(marking_proposals.document_id)) AND (r.role = ANY (ARRAY['designator'::text])))))));


--
-- Name: documents turnstile_scope_read; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_read ON public.documents FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'read'::text) AND (((EXISTS ( SELECT 1
   FROM (public.assignments a
     JOIN public.programs p ON ((p.id = a.program_id)))
  WHERE ((a.user_id = current_setting('turnstile.subject_id'::text, true)) AND (a.program_id = documents.program_id) AND (a.role = ANY (ARRAY['lead'::text, 'member'::text])) AND (p.closed_at IS NULL)))) OR (EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text, 'approver'::text])))))) AND (NOT (EXISTS ( SELECT 1
   FROM ((((public.markings m
     JOIN public.offices o ON ((o.id = documents.designating_office_id)))
     JOIN public.agencies g ON ((g.id = o.agency_id)))
     JOIN public.users u ON ((u.id = current_setting('turnstile.subject_id'::text, true))))
     LEFT JOIN public.categories c ON (((c.name = ANY (m.categories)) AND c.specified)))
  WHERE ((m.document_id = documents.id) AND ((documents.decontrol IS NULL) OR (documents.decontrol > (NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone)) AND (((('federal_only'::text = ANY (m.controls)) OR ('federal_only'::text = ANY (c.implied_controls))) AND (u.employment <> 'federal'::text)) OR ((('no_foreign'::text = ANY (m.controls)) OR ('no_foreign'::text = ANY (c.implied_controls))) AND (u.nationality <> g.nationality)) OR ((('releasable_to'::text = ANY (m.controls)) OR ('releasable_to'::text = ANY (c.implied_controls))) AND (NOT (u.nationality = ANY (m.releasable_to)))) OR ((('named_list'::text = ANY (m.controls)) OR ('named_list'::text = ANY (c.implied_controls))) AND (NOT (current_setting('turnstile.subject_id'::text, true) = ANY (m.list))))))))))));


--
-- Name: portions turnstile_scope_read; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_read ON public.portions FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'read'::text) AND (((EXISTS ( SELECT 1
   FROM (public.assignments a
     JOIN public.programs p ON ((p.id = a.program_id)))
  WHERE ((a.user_id = current_setting('turnstile.subject_id'::text, true)) AND (a.program_id = public.turnstile_document_program(portions.document_id)) AND (a.role = ANY (ARRAY['lead'::text, 'member'::text])) AND (p.closed_at IS NULL)))) OR (EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = public.turnstile_document_office(portions.document_id)) AND (r.role = ANY (ARRAY['designator'::text, 'approver'::text])))))) AND (NOT (EXISTS ( SELECT 1
   FROM ((((public.markings dm
     JOIN public.offices o ON ((o.id = public.turnstile_document_office(portions.document_id))))
     JOIN public.agencies g ON ((g.id = o.agency_id)))
     JOIN public.users u ON ((u.id = current_setting('turnstile.subject_id'::text, true))))
     LEFT JOIN public.categories c ON (((c.name = ANY (portions.categories)) AND c.specified)))
  WHERE ((dm.document_id = portions.document_id) AND ((public.turnstile_document_decontrol(portions.document_id) IS NULL) OR (public.turnstile_document_decontrol(portions.document_id) > (NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone)) AND (((('federal_only'::text = ANY (portions.controls)) OR ('federal_only'::text = ANY (c.implied_controls))) AND (u.employment <> 'federal'::text)) OR ((('no_foreign'::text = ANY (portions.controls)) OR ('no_foreign'::text = ANY (c.implied_controls))) AND (u.nationality <> g.nationality)) OR ((('releasable_to'::text = ANY (portions.controls)) OR ('releasable_to'::text = ANY (c.implied_controls))) AND (NOT (u.nationality = ANY (portions.releasable_to)))) OR ((('named_list'::text = ANY (portions.controls)) OR ('named_list'::text = ANY (c.implied_controls))) AND (NOT (current_setting('turnstile.subject_id'::text, true) = ANY (dm.list))))))))))));


--
-- Name: documents turnstile_scope_read_redacted; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_read_redacted ON public.documents FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'read_redacted'::text) AND ((EXISTS ( SELECT 1
   FROM (public.assignments a
     JOIN public.programs p ON ((p.id = a.program_id)))
  WHERE ((a.user_id = current_setting('turnstile.subject_id'::text, true)) AND (a.program_id = documents.program_id) AND (a.role = ANY (ARRAY['lead'::text, 'member'::text])) AND (p.closed_at IS NULL)))) OR (EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text, 'approver'::text]))))))));


--
-- Name: documents turnstile_scope_set_decontrol; Type: POLICY; Schema: public; Owner: turnstile_owner
--

CREATE POLICY turnstile_scope_set_decontrol ON public.documents FOR SELECT USING (((current_setting('turnstile.operation'::text, true) = 'set_decontrol'::text) AND ((EXISTS ( SELECT 1
   FROM public.office_roles r
  WHERE ((r.user_id = current_setting('turnstile.subject_id'::text, true)) AND (r.office_id = documents.designating_office_id) AND (r.role = ANY (ARRAY['designator'::text]))))) AND ((((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) >= '00:00:00'::interval) AND (((NULLIF(current_setting('turnstile.now'::text, true), ''::text))::timestamp without time zone - (NULLIF(current_setting('turnstile.reauthenticated_at'::text, true), ''::text))::timestamp without time zone) <= '00:15:00'::interval)))));


--
-- Name: FUNCTION turnstile_document_decontrol(document bigint); Type: ACL; Schema: public; Owner: turnstile_owner
--

REVOKE ALL ON FUNCTION public.turnstile_document_decontrol(document bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.turnstile_document_decontrol(document bigint) TO turnstile_app;


--
-- Name: FUNCTION turnstile_document_office(document bigint); Type: ACL; Schema: public; Owner: turnstile_owner
--

REVOKE ALL ON FUNCTION public.turnstile_document_office(document bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.turnstile_document_office(document bigint) TO turnstile_app;


--
-- Name: FUNCTION turnstile_document_program(document bigint); Type: ACL; Schema: public; Owner: turnstile_owner
--

REVOKE ALL ON FUNCTION public.turnstile_document_program(document bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.turnstile_document_program(document bigint) TO turnstile_app;


--
-- Name: TABLE account_roles; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.account_roles TO turnstile_app;


--
-- Name: SEQUENCE account_roles_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.account_roles_id_seq TO turnstile_app;


--
-- Name: TABLE agencies; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.agencies TO turnstile_app;


--
-- Name: SEQUENCE agencies_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.agencies_id_seq TO turnstile_app;


--
-- Name: TABLE assignments; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.assignments TO turnstile_app;


--
-- Name: SEQUENCE assignments_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.assignments_id_seq TO turnstile_app;


--
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.categories TO turnstile_app;


--
-- Name: TABLE documents; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.documents TO turnstile_app;


--
-- Name: SEQUENCE documents_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.documents_id_seq TO turnstile_app;


--
-- Name: TABLE marking_proposals; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.marking_proposals TO turnstile_app;


--
-- Name: SEQUENCE marking_proposals_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.marking_proposals_id_seq TO turnstile_app;


--
-- Name: TABLE markings; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.markings TO turnstile_app;


--
-- Name: SEQUENCE markings_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.markings_id_seq TO turnstile_app;


--
-- Name: TABLE office_roles; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.office_roles TO turnstile_app;


--
-- Name: SEQUENCE office_roles_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.office_roles_id_seq TO turnstile_app;


--
-- Name: TABLE offices; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.offices TO turnstile_app;


--
-- Name: SEQUENCE offices_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.offices_id_seq TO turnstile_app;


--
-- Name: TABLE override_reports; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.override_reports TO turnstile_app;


--
-- Name: SEQUENCE override_reports_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.override_reports_id_seq TO turnstile_app;


--
-- Name: TABLE portions; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.portions TO turnstile_app;


--
-- Name: SEQUENCE portions_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.portions_id_seq TO turnstile_app;


--
-- Name: TABLE programs; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.programs TO turnstile_app;


--
-- Name: SEQUENCE programs_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.programs_id_seq TO turnstile_app;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT ON TABLE public.schema_migrations TO turnstile_app;


--
-- Name: TABLE turnstile_ledger_counter; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.turnstile_ledger_counter TO turnstile_app;


--
-- Name: TABLE turnstile_ledger_events; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT ON TABLE public.turnstile_ledger_events TO turnstile_app;


--
-- Name: SEQUENCE turnstile_ledger_events_id_seq; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.turnstile_ledger_events_id_seq TO turnstile_app;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: turnstile_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.users TO turnstile_app;


--
-- PostgreSQL database dump complete
--


