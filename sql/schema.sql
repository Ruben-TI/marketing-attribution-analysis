--
-- PostgreSQL database dump
--


-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

-- Started on 2026-09-24 14:57:47

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 226 (class 1259 OID 16627)
-- Name: fact_touchpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_touchpoints (
    touchpoint_id integer NOT NULL,
    user_id integer,
    touchpoint_time timestamp without time zone,
    channel character varying(25),
    campaign character varying(25),
    conversion text,
    first_conversion_time timestamp without time zone,
    outcome character varying(10)
);


--
-- TOC entry 228 (class 1259 OID 16640)
-- Name: dim_campaign; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dim_campaign AS
 SELECT DISTINCT campaign,
        CASE
            WHEN ((campaign)::text = '-'::text) THEN 'No Campaign'::character varying
            ELSE campaign
        END AS campaign_label
   FROM public.fact_touchpoints;


--
-- TOC entry 227 (class 1259 OID 16636)
-- Name: dim_channel; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dim_channel AS
 SELECT DISTINCT channel
   FROM public.fact_touchpoints;


--
-- TOC entry 229 (class 1259 OID 16644)
-- Name: dim_model; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_model (
    model character varying(25) NOT NULL,
    model_label character varying(30),
    model_type character varying(20),
    sort_order integer
);


--
-- TOC entry 225 (class 1259 OID 16626)
-- Name: fact_touchpoints_touchpoint_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fact_touchpoints_touchpoint_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5058 (class 0 OID 0)
-- Dependencies: 225
-- Name: fact_touchpoints_touchpoint_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fact_touchpoints_touchpoint_id_seq OWNED BY public.fact_touchpoints.touchpoint_id;


--
-- TOC entry 220 (class 1259 OID 16598)
-- Name: journeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journeys (
    touchpoint_id integer NOT NULL,
    user_id integer,
    touchpoint_time timestamp without time zone,
    channel character varying(25),
    campaign character varying(25),
    conversion text,
    first_conversion_time timestamp without time zone
);


--
-- TOC entry 230 (class 1259 OID 16650)
-- Name: journey_lengths; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.journey_lengths AS
 SELECT user_id,
    count(*) AS journey_length
   FROM public.journeys
  GROUP BY user_id;


--
-- TOC entry 219 (class 1259 OID 16597)
-- Name: journeys_touchpoint_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.journeys_touchpoint_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5059 (class 0 OID 0)
-- Dependencies: 219
-- Name: journeys_touchpoint_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.journeys_touchpoint_id_seq OWNED BY public.journeys.touchpoint_id;


--
-- TOC entry 223 (class 1259 OID 16612)
-- Name: model_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_results (
    result_id integer NOT NULL,
    channel character varying(25),
    model character varying(25),
    value numeric
);


--
-- TOC entry 224 (class 1259 OID 16622)
-- Name: model_results_ranked; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.model_results_ranked AS
 SELECT channel,
    model,
    value,
    rank() OVER (PARTITION BY model ORDER BY value DESC) AS rank
   FROM public.model_results;


--
-- TOC entry 222 (class 1259 OID 16611)
-- Name: model_results_result_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.model_results_result_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5060 (class 0 OID 0)
-- Dependencies: 222
-- Name: model_results_result_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.model_results_result_id_seq OWNED BY public.model_results.result_id;


--
-- TOC entry 221 (class 1259 OID 16607)
-- Name: numbered_touchpoints; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.numbered_touchpoints AS
 WITH numbered AS (
         SELECT journeys.user_id,
            journeys.touchpoint_time,
            journeys.channel,
            row_number() OVER (PARTITION BY journeys.user_id ORDER BY journeys.touchpoint_time) AS touchpoint_position
           FROM public.journeys
        )
 SELECT user_id,
    touchpoint_time,
    channel,
    touchpoint_position,
    max(touchpoint_position) OVER (PARTITION BY user_id) AS max_position
   FROM numbered;


--
-- TOC entry 4892 (class 2604 OID 16630)
-- Name: fact_touchpoints touchpoint_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_touchpoints ALTER COLUMN touchpoint_id SET DEFAULT nextval('public.fact_touchpoints_touchpoint_id_seq'::regclass);


--
-- TOC entry 4890 (class 2604 OID 16601)
-- Name: journeys touchpoint_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journeys ALTER COLUMN touchpoint_id SET DEFAULT nextval('public.journeys_touchpoint_id_seq'::regclass);


--
-- TOC entry 4891 (class 2604 OID 16615)
-- Name: model_results result_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_results ALTER COLUMN result_id SET DEFAULT nextval('public.model_results_result_id_seq'::regclass);


--
-- TOC entry 4900 (class 2606 OID 16649)
-- Name: dim_model dim_model_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_model
    ADD CONSTRAINT dim_model_pkey PRIMARY KEY (model);


--
-- TOC entry 4898 (class 2606 OID 16635)
-- Name: fact_touchpoints fact_touchpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_touchpoints
    ADD CONSTRAINT fact_touchpoints_pkey PRIMARY KEY (touchpoint_id);


--
-- TOC entry 4894 (class 2606 OID 16606)
-- Name: journeys journeys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journeys
    ADD CONSTRAINT journeys_pkey PRIMARY KEY (touchpoint_id);


--
-- TOC entry 4896 (class 2606 OID 16620)
-- Name: model_results model_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_results
    ADD CONSTRAINT model_results_pkey PRIMARY KEY (result_id);


-- Completed on 2026-09-24 14:57:48

--
-- PostgreSQL database dump complete
--


