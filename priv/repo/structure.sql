--
-- PostgreSQL database dump
--

-- Dumped from database version 14.0
-- Dumped by pg_dump version 16.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


--
-- Name: oban_jobs_notify(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.oban_jobs_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  channel text;
  notice json;
BEGIN
  IF NEW.state = 'available' THEN
    channel = 'public.oban_insert';
    notice = json_build_object('queue', NEW.queue);

    PERFORM pg_notify(channel, notice::text);
  END IF;

  RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.answers (
    id bigint NOT NULL,
    response character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: answers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: answers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.answers_id_seq OWNED BY public.answers.id;


--
-- Name: authors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.authors (
    id bigint NOT NULL,
    name character varying(255),
    bio text,
    wikipedia_url character varying(255),
    twitter_username character varying(255),
    country character varying(255),
    twin_origin boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    twitter_id_str character varying(255),
    profile_image_url character varying(255),
    description character varying(255),
    followers_count integer,
    verified boolean,
    location character varying(255),
    friends_count integer,
    twin_enabled boolean DEFAULT true NOT NULL
);


--
-- Name: authors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.authors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: authors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.authors_id_seq OWNED BY public.authors.id;


--
-- Name: delegations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delegations (
    id bigint NOT NULL,
    deleguee_id bigint NOT NULL,
    delegate_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: delegations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.delegations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: delegations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.delegations_id_seq OWNED BY public.delegations.id;


--
-- Name: halls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.halls (
    id bigint NOT NULL,
    name character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: halls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.halls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: halls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.halls_id_seq OWNED BY public.halls.id;


--
-- Name: halls_votings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.halls_votings (
    id bigint NOT NULL,
    hall_id bigint,
    voting_id bigint
);


--
-- Name: halls_votings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.halls_votings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: halls_votings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.halls_votings_id_seq OWNED BY public.halls_votings.id;


--
-- Name: likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.likes (
    id bigint NOT NULL,
    opinion_id integer NOT NULL,
    user_id integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: likes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.likes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: likes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.likes_id_seq OWNED BY public.likes.id;


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT priority_range CHECK (((priority >= 0) AND (priority <= 3))),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '11';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: opinions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opinions (
    id bigint NOT NULL,
    content text NOT NULL,
    source_url character varying(255),
    twin boolean DEFAULT false NOT NULL,
    author_id bigint,
    user_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    ancestry character varying(255),
    descendants_count integer DEFAULT 0,
    likes_count integer DEFAULT 0
);


--
-- Name: opinions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.opinions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: opinions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.opinions_id_seq OWNED BY public.opinions.id;


--
-- Name: opinions_votings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opinions_votings (
    id bigint NOT NULL,
    opinion_id bigint NOT NULL,
    voting_id bigint NOT NULL,
    user_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: opinions_votings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.opinions_votings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: opinions_votings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.opinions_votings_id_seq OWNED BY public.opinions_votings.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email public.citext NOT NULL,
    hashed_password character varying(255),
    email_confirmed_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    author_id bigint NOT NULL,
    role character varying(255) DEFAULT 'user'::character varying NOT NULL,
    newsletter boolean DEFAULT false,
    phone_number_confirmed_at timestamp(0) without time zone,
    phone_number character varying(255)
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: users_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token bytea NOT NULL,
    context character varying(255) NOT NULL,
    sent_to character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: users_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_tokens_id_seq OWNED BY public.users_tokens.id;


--
-- Name: votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.votes (
    id bigint NOT NULL,
    author_id bigint NOT NULL,
    voting_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    answer_id integer,
    direct boolean DEFAULT true NOT NULL,
    twin boolean DEFAULT false NOT NULL,
    opinion_id bigint
);


--
-- Name: votes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.votes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.votes_id_seq OWNED BY public.votes.id;


--
-- Name: votings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.votings (
    id bigint NOT NULL,
    title character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    generating_left integer DEFAULT 0 NOT NULL,
    user_id bigint,
    slug character varying(255),
    generating_total integer DEFAULT 0,
    opinion_likes_count integer DEFAULT 0 NOT NULL
);


--
-- Name: votings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.votings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: votings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.votings_id_seq OWNED BY public.votings.id;


--
-- Name: answers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answers ALTER COLUMN id SET DEFAULT nextval('public.answers_id_seq'::regclass);


--
-- Name: authors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authors ALTER COLUMN id SET DEFAULT nextval('public.authors_id_seq'::regclass);


--
-- Name: delegations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delegations ALTER COLUMN id SET DEFAULT nextval('public.delegations_id_seq'::regclass);


--
-- Name: halls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.halls ALTER COLUMN id SET DEFAULT nextval('public.halls_id_seq'::regclass);


--
-- Name: halls_votings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.halls_votings ALTER COLUMN id SET DEFAULT nextval('public.halls_votings_id_seq'::regclass);


--
-- Name: likes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.likes ALTER COLUMN id SET DEFAULT nextval('public.likes_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: opinions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions ALTER COLUMN id SET DEFAULT nextval('public.opinions_id_seq'::regclass);


--
-- Name: opinions_votings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions_votings ALTER COLUMN id SET DEFAULT nextval('public.opinions_votings_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: users_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens ALTER COLUMN id SET DEFAULT nextval('public.users_tokens_id_seq'::regclass);


--
-- Name: votes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes ALTER COLUMN id SET DEFAULT nextval('public.votes_id_seq'::regclass);


--
-- Name: votings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votings ALTER COLUMN id SET DEFAULT nextval('public.votings_id_seq'::regclass);


--
-- Name: answers answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answers
    ADD CONSTRAINT answers_pkey PRIMARY KEY (id);


--
-- Name: authors authors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authors
    ADD CONSTRAINT authors_pkey PRIMARY KEY (id);


--
-- Name: delegations delegations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delegations
    ADD CONSTRAINT delegations_pkey PRIMARY KEY (id);


--
-- Name: halls halls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.halls
    ADD CONSTRAINT halls_pkey PRIMARY KEY (id);


--
-- Name: halls_votings halls_votings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.halls_votings
    ADD CONSTRAINT halls_votings_pkey PRIMARY KEY (id);


--
-- Name: likes likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: opinions opinions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions
    ADD CONSTRAINT opinions_pkey PRIMARY KEY (id);


--
-- Name: opinions_votings opinions_votings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions_votings
    ADD CONSTRAINT opinions_votings_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users_tokens users_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_pkey PRIMARY KEY (id);


--
-- Name: votes votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_pkey PRIMARY KEY (id);


--
-- Name: votings votings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votings
    ADD CONSTRAINT votings_pkey PRIMARY KEY (id);


--
-- Name: authors_twitter_id_str_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX authors_twitter_id_str_index ON public.authors USING btree (twitter_id_str);


--
-- Name: authors_twitter_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX authors_twitter_url_index ON public.authors USING btree (twitter_username);


--
-- Name: authors_wikipedia_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX authors_wikipedia_url_index ON public.authors USING btree (wikipedia_url);


--
-- Name: delegations_delegate_id_deleguee_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX delegations_delegate_id_deleguee_id_index ON public.delegations USING btree (delegate_id, deleguee_id);


--
-- Name: delegations_delegate_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX delegations_delegate_id_index ON public.delegations USING btree (delegate_id);


--
-- Name: delegations_deleguee_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX delegations_deleguee_id_index ON public.delegations USING btree (deleguee_id);


--
-- Name: halls_votings_hall_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX halls_votings_hall_id_index ON public.halls_votings USING btree (hall_id);


--
-- Name: halls_votings_hall_id_voting_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX halls_votings_hall_id_voting_id_index ON public.halls_votings USING btree (hall_id, voting_id);


--
-- Name: halls_votings_voting_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX halls_votings_voting_id_index ON public.halls_votings USING btree (voting_id);


--
-- Name: likes_opinion_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX likes_opinion_id_user_id_index ON public.likes USING btree (opinion_id, user_id);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: opinions_ancestry_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX opinions_ancestry_index ON public.opinions USING btree (ancestry);


--
-- Name: opinions_author_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX opinions_author_id_index ON public.opinions USING btree (author_id);


--
-- Name: opinions_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX opinions_user_id_index ON public.opinions USING btree (user_id);


--
-- Name: opinions_votings_opinion_id_voting_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX opinions_votings_opinion_id_voting_id_index ON public.opinions_votings USING btree (opinion_id, voting_id);


--
-- Name: opinions_votings_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX opinions_votings_user_id_index ON public.opinions_votings USING btree (user_id);


--
-- Name: opinions_votings_voting_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX opinions_votings_voting_id_index ON public.opinions_votings USING btree (voting_id);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email);


--
-- Name: users_tokens_context_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_tokens_context_token_index ON public.users_tokens USING btree (context, token);


--
-- Name: users_tokens_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_tokens_user_id_index ON public.users_tokens USING btree (user_id);


--
-- Name: votes_author_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX votes_author_id_index ON public.votes USING btree (author_id);


--
-- Name: votes_author_id_voting_id_answer_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_author_id_voting_id_answer_id_index ON public.votes USING btree (author_id, voting_id, answer_id);


--
-- Name: votes_author_id_voting_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_author_id_voting_id_index ON public.votes USING btree (author_id, voting_id);


--
-- Name: votes_voting_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX votes_voting_id_index ON public.votes USING btree (voting_id);


--
-- Name: votings_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votings_slug_index ON public.votings USING btree (slug);


--
-- Name: votings_title_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votings_title_index ON public.votings USING btree (title);


--
-- Name: oban_jobs oban_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER oban_notify AFTER INSERT ON public.oban_jobs FOR EACH ROW EXECUTE FUNCTION public.oban_jobs_notify();


--
-- Name: delegations delegations_delegate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delegations
    ADD CONSTRAINT delegations_delegate_id_fkey FOREIGN KEY (delegate_id) REFERENCES public.authors(id) ON DELETE CASCADE;


--
-- Name: delegations delegations_deleguee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delegations
    ADD CONSTRAINT delegations_deleguee_id_fkey FOREIGN KEY (deleguee_id) REFERENCES public.authors(id) ON DELETE CASCADE;


--
-- Name: halls_votings halls_votings_hall_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.halls_votings
    ADD CONSTRAINT halls_votings_hall_id_fkey FOREIGN KEY (hall_id) REFERENCES public.halls(id);


--
-- Name: halls_votings halls_votings_voting_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.halls_votings
    ADD CONSTRAINT halls_votings_voting_id_fkey FOREIGN KEY (voting_id) REFERENCES public.votings(id);


--
-- Name: opinions opinions_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions
    ADD CONSTRAINT opinions_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.authors(id) ON DELETE CASCADE;


--
-- Name: opinions opinions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions
    ADD CONSTRAINT opinions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: opinions_votings opinions_votings_opinion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions_votings
    ADD CONSTRAINT opinions_votings_opinion_id_fkey FOREIGN KEY (opinion_id) REFERENCES public.opinions(id) ON DELETE CASCADE;


--
-- Name: opinions_votings opinions_votings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions_votings
    ADD CONSTRAINT opinions_votings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: opinions_votings opinions_votings_voting_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opinions_votings
    ADD CONSTRAINT opinions_votings_voting_id_fkey FOREIGN KEY (voting_id) REFERENCES public.votings(id) ON DELETE CASCADE;


--
-- Name: users users_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.authors(id) ON DELETE SET NULL;


--
-- Name: users_tokens users_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: votes votes_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.authors(id) ON DELETE CASCADE;


--
-- Name: votes votes_opinion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_opinion_id_fkey FOREIGN KEY (opinion_id) REFERENCES public.opinions(id) ON DELETE SET NULL;


--
-- Name: votes votes_voting_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_voting_id_fkey FOREIGN KEY (voting_id) REFERENCES public.votings(id) ON DELETE CASCADE;


--
-- Name: votings votings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votings
    ADD CONSTRAINT votings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20230812184249);
INSERT INTO public."schema_migrations" (version) VALUES (20230812190117);
INSERT INTO public."schema_migrations" (version) VALUES (20230812194639);
INSERT INTO public."schema_migrations" (version) VALUES (20231109153942);
INSERT INTO public."schema_migrations" (version) VALUES (20231109154057);
INSERT INTO public."schema_migrations" (version) VALUES (20231111115930);
INSERT INTO public."schema_migrations" (version) VALUES (20231111121527);
INSERT INTO public."schema_migrations" (version) VALUES (20231111135249);
INSERT INTO public."schema_migrations" (version) VALUES (20231125143057);
INSERT INTO public."schema_migrations" (version) VALUES (20231125151005);
INSERT INTO public."schema_migrations" (version) VALUES (20231202135142);
INSERT INTO public."schema_migrations" (version) VALUES (20231210085607);
INSERT INTO public."schema_migrations" (version) VALUES (20231227190439);
INSERT INTO public."schema_migrations" (version) VALUES (20231228182909);
INSERT INTO public."schema_migrations" (version) VALUES (20231229170633);
INSERT INTO public."schema_migrations" (version) VALUES (20240106114945);
INSERT INTO public."schema_migrations" (version) VALUES (20240107155631);
INSERT INTO public."schema_migrations" (version) VALUES (20240107165427);
INSERT INTO public."schema_migrations" (version) VALUES (20240107172720);
INSERT INTO public."schema_migrations" (version) VALUES (20240113144343);
INSERT INTO public."schema_migrations" (version) VALUES (20240114171319);
INSERT INTO public."schema_migrations" (version) VALUES (20240120161619);
INSERT INTO public."schema_migrations" (version) VALUES (20240124201803);
INSERT INTO public."schema_migrations" (version) VALUES (20240218122716);
INSERT INTO public."schema_migrations" (version) VALUES (20240218131858);
INSERT INTO public."schema_migrations" (version) VALUES (20240302144153);
INSERT INTO public."schema_migrations" (version) VALUES (20240309220204);
INSERT INTO public."schema_migrations" (version) VALUES (20240316190806);
INSERT INTO public."schema_migrations" (version) VALUES (20240316205405);
INSERT INTO public."schema_migrations" (version) VALUES (20240317183457);
INSERT INTO public."schema_migrations" (version) VALUES (20240326111409);
INSERT INTO public."schema_migrations" (version) VALUES (20240326114137);
INSERT INTO public."schema_migrations" (version) VALUES (20240326160223);
INSERT INTO public."schema_migrations" (version) VALUES (20240406091754);
INSERT INTO public."schema_migrations" (version) VALUES (20240427094309);
INSERT INTO public."schema_migrations" (version) VALUES (20240427205936);
INSERT INTO public."schema_migrations" (version) VALUES (20240629130946);
INSERT INTO public."schema_migrations" (version) VALUES (20240629132005);
INSERT INTO public."schema_migrations" (version) VALUES (20240629134735);
INSERT INTO public."schema_migrations" (version) VALUES (20240629234151);
INSERT INTO public."schema_migrations" (version) VALUES (20240706085923);
INSERT INTO public."schema_migrations" (version) VALUES (20240706095456);
INSERT INTO public."schema_migrations" (version) VALUES (20240815085140);
INSERT INTO public."schema_migrations" (version) VALUES (20240815085324);
INSERT INTO public."schema_migrations" (version) VALUES (20241019141205);
INSERT INTO public."schema_migrations" (version) VALUES (20241019141319);
INSERT INTO public."schema_migrations" (version) VALUES (20241019142019);
INSERT INTO public."schema_migrations" (version) VALUES (20241019215813);
INSERT INTO public."schema_migrations" (version) VALUES (20241101113234);
INSERT INTO public."schema_migrations" (version) VALUES (20241115200137);
INSERT INTO public."schema_migrations" (version) VALUES (20250816141800);
