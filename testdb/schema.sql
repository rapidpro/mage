--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.1
-- Dumped by pg_dump version 9.6.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET search_path = public, pg_catalog;

--
-- Name: contact_check_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION contact_check_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.is_test != NEW.is_test THEN
    RAISE EXCEPTION 'Contact.is_test cannot be changed';
  END IF;

  IF NEW.is_test AND (NEW.is_blocked OR NEW.is_stopped) THEN
    RAISE EXCEPTION 'Test contacts cannot opt out or be blocked';
  END IF;

  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: contacts_contact; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_contact (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(128),
    is_blocked boolean NOT NULL,
    is_test boolean NOT NULL,
    is_stopped boolean NOT NULL,
    language character varying(3),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: contact_toggle_system_group(contacts_contact, character, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION contact_toggle_system_group(_contact contacts_contact, _group_type character, _add boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _group_id INT;
BEGIN
  PERFORM contact_toggle_system_group(_contact.id, _contact.org_id, _group_type, _add);
END;
$$;


--
-- Name: contact_toggle_system_group(integer, integer, character, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION contact_toggle_system_group(_contact_id integer, _org_id integer, _group_type character, _add boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _group_id INT;
BEGIN
  -- lookup the group id
  SELECT id INTO STRICT _group_id FROM contacts_contactgroup
  WHERE org_id = _org_id AND group_type = _group_type;

  -- don't do anything if group doesn't exist for some inexplicable reason
  IF _group_id IS NULL THEN
    RETURN;
  END IF;

  IF _add THEN
    BEGIN
      INSERT INTO contacts_contactgroup_contacts (contactgroup_id, contact_id) VALUES (_group_id, _contact_id);
    EXCEPTION WHEN unique_violation THEN
      -- do nothing
    END;
  ELSE
    DELETE FROM contacts_contactgroup_contacts WHERE contactgroup_id = _group_id AND contact_id = _contact_id;
  END IF;
END;
$$;


--
-- Name: msgs_broadcast; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_broadcast (
    id integer NOT NULL,
    recipient_count integer,
    status character varying(1) NOT NULL,
    base_language character varying(4) NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    purged boolean NOT NULL,
    channel_id integer,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    parent_id integer,
    schedule_id integer,
    send_all boolean NOT NULL,
    media hstore,
    text hstore NOT NULL
);


--
-- Name: temba_broadcast_determine_system_label(msgs_broadcast); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_broadcast_determine_system_label(_broadcast msgs_broadcast) RETURNS character
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF _broadcast.is_active AND _broadcast.schedule_id IS NOT NULL THEN
    RETURN 'E';
  END IF;

  RETURN NULL; -- might not match any label
END;
$$;


--
-- Name: temba_broadcast_on_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_broadcast_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _is_test BOOLEAN;
  _new_label_type CHAR(1);
  _old_label_type CHAR(1);
BEGIN
  -- new broadcast inserted
  IF TG_OP = 'INSERT' THEN
    -- don't update anything for a test broadcast
    IF NEW.recipient_count = 1 THEN
      SELECT c.is_test INTO _is_test FROM contacts_contact c
      INNER JOIN msgs_msg m ON m.contact_id = c.id AND m.broadcast_id = NEW.id;
      IF _is_test = TRUE THEN
        RETURN NULL;
      END IF;
    END IF;

    _new_label_type := temba_broadcast_determine_system_label(NEW);
    IF _new_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
    END IF;

  -- existing broadcast updated
  ELSIF TG_OP = 'UPDATE' THEN
    _old_label_type := temba_broadcast_determine_system_label(OLD);
    _new_label_type := temba_broadcast_determine_system_label(NEW);

    IF _old_label_type IS DISTINCT FROM _new_label_type THEN
      -- if this could be a test broadcast, check it and exit if so
      IF NEW.recipient_count = 1 THEN
        SELECT c.is_test INTO _is_test FROM contacts_contact c
        INNER JOIN msgs_msg m ON m.contact_id = c.id AND m.broadcast_id = NEW.id;
        IF _is_test = TRUE THEN
          RETURN NULL;
        END IF;
      END IF;

      IF _old_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, -1);
      END IF;
      IF _new_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
      END IF;
    END IF;

  -- existing broadcast deleted
  ELSIF TG_OP = 'DELETE' THEN
    -- don't update anything for a test broadcast
    IF OLD.recipient_count = 1 THEN
      SELECT c.is_test INTO _is_test FROM contacts_contact c
      INNER JOIN msgs_msg m ON m.contact_id = c.id AND m.broadcast_id = OLD.id;
      IF _is_test = TRUE THEN
        RETURN NULL;
      END IF;
    END IF;

    _old_label_type := temba_broadcast_determine_system_label(OLD);

    IF _old_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, 1);
    END IF;

  -- all broadcast deleted
  ELSIF TG_OP = 'TRUNCATE' THEN
    PERFORM temba_reset_system_labels('{"E"}');

  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: channels_channelevent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE channels_channelevent (
    id integer NOT NULL,
    event_type character varying(16) NOT NULL,
    "time" timestamp with time zone NOT NULL,
    duration integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    is_active boolean NOT NULL,
    channel_id integer NOT NULL,
    contact_id integer NOT NULL,
    contact_urn_id integer,
    org_id integer NOT NULL
);


--
-- Name: temba_channelevent_is_call(channels_channelevent); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_channelevent_is_call(_event channels_channelevent) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN _event.event_type IN ('mo_call', 'mo_miss', 'mt_call', 'mt_miss');
END;
$$;


--
-- Name: temba_channelevent_on_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_channelevent_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- new event inserted
  IF TG_OP = 'INSERT' THEN
    -- don't update anything for a non-call event or test call
    IF NOT temba_channelevent_is_call(NEW) OR temba_contact_is_test(NEW.contact_id) THEN
      RETURN NULL;
    END IF;

    IF NEW.is_active THEN
      PERFORM temba_insert_system_label(NEW.org_id, 'C', 1);
    END IF;

  -- existing call updated
  ELSIF TG_OP = 'UPDATE' THEN
    -- don't update anything for a non-call event or test call
    IF NOT temba_channelevent_is_call(NEW) OR temba_contact_is_test(NEW.contact_id) THEN
      RETURN NULL;
    END IF;

    -- is being de-activated
    IF OLD.is_active AND NOT NEW.is_active THEN
      PERFORM temba_insert_system_label(NEW.org_id, 'C', -1);
    -- is being re-activated
    ELSIF NOT OLD.is_active AND NEW.is_active THEN
      PERFORM temba_insert_system_label(NEW.org_id, 'C', 1);
    END IF;

  -- existing call deleted
  ELSIF TG_OP = 'DELETE' THEN
    -- don't update anything for a test call
    IF NOT temba_channelevent_is_call(OLD) OR temba_contact_is_test(OLD.contact_id) THEN
      RETURN NULL;
    END IF;

    IF OLD.is_active THEN
      PERFORM temba_insert_system_label(OLD.org_id, 'C', -1);
    END IF;

  -- all calls deleted
  ELSIF TG_OP = 'TRUNCATE' THEN
    PERFORM temba_reset_system_labels('{"C"}');

  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: temba_contact_is_test(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_contact_is_test(_contact_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  _is_test BOOLEAN;
BEGIN
  SELECT is_test INTO STRICT _is_test FROM contacts_contact WHERE id = _contact_id;
  RETURN _is_test;
END;
$$;


--
-- Name: temba_flow_for_run(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_flow_for_run(_run_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  _flow_id INTEGER;
BEGIN
  SELECT flow_id INTO STRICT _flow_id FROM flows_flowrun WHERE id = _run_id;
  RETURN _flow_id;
END;
$$;


--
-- Name: temba_flows_contact_is_test(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_flows_contact_is_test(_contact_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  _is_test BOOLEAN;
BEGIN
  SELECT is_test INTO STRICT _is_test FROM contacts_contact WHERE id = _contact_id;
  RETURN _is_test;
END;
$$;


--
-- Name: temba_insert_channelcount(integer, character varying, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_channelcount(_channel_id integer, _count_type character varying, _count_day date, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    INSERT INTO channels_channelcount("channel_id", "count_type", "day", "count", "is_squashed")
      VALUES(_channel_id, _count_type, _count_day, _count, FALSE);
  END;
$$;


--
-- Name: temba_insert_flownodecount(integer, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_flownodecount(_flow_id integer, _node_uuid uuid, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    INSERT INTO flows_flownodecount("flow_id", "node_uuid", "count", "is_squashed")
      VALUES(_flow_id, _node_uuid, _count, FALSE);
  END;
$$;


--
-- Name: temba_insert_flowpathcount(integer, uuid, uuid, timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_flowpathcount(_flow_id integer, _from_uuid uuid, _to_uuid uuid, _period timestamp with time zone, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
  BEGIN
    INSERT INTO flows_flowpathcount("flow_id", "from_uuid", "to_uuid", "period", "count", "is_squashed")
      VALUES(_flow_id, _from_uuid, _to_uuid, date_trunc('hour', _period), _count, FALSE);
  END;
$$;


--
-- Name: temba_insert_flowruncount(integer, character, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_flowruncount(_flow_id integer, _exit_type character, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO flows_flowruncount("flow_id", "exit_type", "count", "is_squashed")
  VALUES(_flow_id, _exit_type, _count, FALSE);
END;
$$;


--
-- Name: temba_insert_label_count(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_label_count(_label_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO msgs_labelcount("label_id", "count", "is_squashed") VALUES(_label_id, _count, FALSE);
END;
$$;


--
-- Name: temba_insert_message_label_counts(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_message_label_counts(_msg_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO msgs_labelcount("label_id", "count", "is_squashed")
  SELECT label_id, _count, FALSE FROM msgs_msg_labels WHERE msgs_msg_labels.msg_id = _msg_id;
END;
$$;


--
-- Name: temba_insert_system_label(integer, character, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_system_label(_org_id integer, _label_type character, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO msgs_systemlabelcount("org_id", "label_type", "count", "is_squashed") VALUES(_org_id, _label_type, _count, FALSE);
END;
$$;


--
-- Name: temba_insert_topupcredits(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_insert_topupcredits(_topup_id integer, _count integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO orgs_topupcredits("topup_id", "used", "is_squashed") VALUES(_topup_id, _count, FALSE);
END;
$$;


--
-- Name: msgs_msg; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_msg (
    id integer NOT NULL,
    text text NOT NULL,
    priority integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone,
    sent_on timestamp with time zone,
    queued_on timestamp with time zone,
    direction character varying(1) NOT NULL,
    status character varying(1) NOT NULL,
    visibility character varying(1) NOT NULL,
    has_template_error boolean NOT NULL,
    msg_type character varying(1),
    msg_count integer NOT NULL,
    error_count integer NOT NULL,
    next_attempt timestamp with time zone NOT NULL,
    external_id character varying(255),
    broadcast_id integer,
    channel_id integer,
    contact_id integer NOT NULL,
    contact_urn_id integer,
    org_id integer NOT NULL,
    response_to_id integer,
    topup_id integer,
    session_id integer,
    attachments character varying(255)[],
    uuid uuid
);


--
-- Name: temba_msg_determine_system_label(msgs_msg); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_msg_determine_system_label(_msg msgs_msg) RETURNS character
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF _msg.direction = 'I' THEN
    IF _msg.visibility = 'V' THEN
      IF _msg.msg_type = 'I' THEN
        RETURN 'I';
      ELSIF _msg.msg_type = 'F' THEN
        RETURN 'W';
      END IF;
    ELSIF _msg.visibility = 'A' THEN
      RETURN 'A';
    END IF;
  ELSE
    IF _msg.VISIBILITY = 'V' THEN
      IF _msg.status = 'P' OR _msg.status = 'Q' THEN
        RETURN 'O';
      ELSIF _msg.status = 'W' OR _msg.status = 'S' OR _msg.status = 'D' THEN
        RETURN 'S';
      ELSIF _msg.status = 'F' THEN
        RETURN 'X';
      END IF;
    END IF;
  END IF;

  RETURN NULL; -- might not match any label
END;
$$;


--
-- Name: temba_msg_labels_on_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_msg_labels_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_visible BOOLEAN;
BEGIN
  -- label applied to message
  IF TG_OP = 'INSERT' THEN
    -- is this message visible
    SELECT msgs_msg.visibility = 'V' INTO STRICT is_visible FROM msgs_msg WHERE msgs_msg.id = NEW.msg_id;

    IF is_visible THEN
      PERFORM temba_insert_label_count(NEW.label_id, 1);
    END IF;

  -- label removed from message
  ELSIF TG_OP = 'DELETE' THEN
    -- is this message visible
    SELECT msgs_msg.visibility = 'V' INTO STRICT is_visible FROM msgs_msg WHERE msgs_msg.id = OLD.msg_id;

    IF is_visible THEN
      PERFORM temba_insert_label_count(OLD.label_id, -1);
    END IF;

  -- no more labels for any messages
  ELSIF TG_OP = 'TRUNCATE' THEN
    TRUNCATE msgs_labelcount;

  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: temba_msg_on_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_msg_on_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _is_test BOOLEAN;
  _new_label_type CHAR(1);
  _old_label_type CHAR(1);
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    -- prevent illegal message states
    IF NEW.direction = 'I' AND NEW.status NOT IN ('P', 'H') THEN
      RAISE EXCEPTION 'Incoming messages can only be PENDING or HANDLED';
    END IF;
    IF NEW.direction = 'O' AND NEW.visibility = 'A' THEN
      RAISE EXCEPTION 'Outgoing messages cannot be archived';
    END IF;
  END IF;

  -- new message inserted
  IF TG_OP = 'INSERT' THEN
    -- don't update anything for a test message
    IF temba_contact_is_test(NEW.contact_id) THEN
      RETURN NULL;
    END IF;

    _new_label_type := temba_msg_determine_system_label(NEW);
    IF _new_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
    END IF;

  -- existing message updated
  ELSIF TG_OP = 'UPDATE' THEN
    _old_label_type := temba_msg_determine_system_label(OLD);
    _new_label_type := temba_msg_determine_system_label(NEW);

    IF _old_label_type IS DISTINCT FROM _new_label_type THEN
      -- don't update anything for a test message
      IF temba_contact_is_test(NEW.contact_id) THEN
        RETURN NULL;
      END IF;

      IF _old_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, -1);
      END IF;
      IF _new_label_type IS NOT NULL THEN
        PERFORM temba_insert_system_label(NEW.org_id, _new_label_type, 1);
      END IF;
    END IF;

    -- is being archived or deleted (i.e. no longer included for user labels)
    IF OLD.visibility = 'V' AND NEW.visibility != 'V' THEN
      PERFORM temba_insert_message_label_counts(NEW.id, -1);
    END IF;

    -- is being restored (i.e. now included for user labels)
    IF OLD.visibility != 'V' AND NEW.visibility = 'V' THEN
      PERFORM temba_insert_message_label_counts(NEW.id, 1);
    END IF;

  -- existing message deleted
  ELSIF TG_OP = 'DELETE' THEN
    -- don't update anything for a test message
    IF temba_contact_is_test(OLD.contact_id) THEN
      RETURN NULL;
    END IF;

    _old_label_type := temba_msg_determine_system_label(OLD);

    IF _old_label_type IS NOT NULL THEN
      PERFORM temba_insert_system_label(OLD.org_id, _old_label_type, -1);
    END IF;

  -- all messages deleted
  ELSIF TG_OP = 'TRUNCATE' THEN
    PERFORM temba_reset_system_labels('{"I", "W", "A", "O", "S", "X"}');

  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: temba_reset_system_labels(character[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_reset_system_labels(_label_types character[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM msgs_systemlabelcount WHERE label_type = ANY(_label_types);
END;
$$;


--
-- Name: flows_flowstep; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowstep (
    id integer NOT NULL,
    step_type character varying(1) NOT NULL,
    step_uuid character varying(36) NOT NULL,
    rule_uuid character varying(36),
    rule_category character varying(36),
    rule_value text,
    rule_decimal_value numeric(36,8),
    next_uuid character varying(36),
    arrived_on timestamp with time zone NOT NULL,
    left_on timestamp with time zone,
    contact_id integer NOT NULL,
    run_id integer NOT NULL
);


--
-- Name: temba_step_from_uuid(flows_flowstep); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_step_from_uuid(_row flows_flowstep) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF _row.rule_uuid IS NOT NULL THEN
    RETURN UUID(_row.rule_uuid);
  END IF;

  RETURN UUID(_row.step_uuid);
END;
$$;


--
-- Name: temba_update_channelcount(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_update_channelcount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_test boolean;
BEGIN
  -- Message being updated
  IF TG_OP = 'INSERT' THEN
    -- Return if there is no channel on this message
    IF NEW.channel_id IS NULL THEN
      RETURN NULL;
    END IF;

    -- Find out if this is a test contact
    SELECT contacts_contact.is_test INTO STRICT is_test FROM contacts_contact WHERE id=NEW.contact_id;

    -- Return if it is
    IF is_test THEN
      RETURN NULL;
    END IF;

    -- If this is an incoming message, without message type, then increment that count
    IF NEW.direction = 'I' THEN
      -- This is a voice message, increment that count
      IF NEW.msg_type = 'V' THEN
        PERFORM temba_insert_channelcount(NEW.channel_id, 'IV', NEW.created_on::date, 1);
      -- Otherwise, this is a normal message
      ELSE
        PERFORM temba_insert_channelcount(NEW.channel_id, 'IM', NEW.created_on::date, 1);
      END IF;

    -- This is an outgoing message
    ELSIF NEW.direction = 'O' THEN
      -- This is a voice message, increment that count
      IF NEW.msg_type = 'V' THEN
        PERFORM temba_insert_channelcount(NEW.channel_id, 'OV', NEW.created_on::date, 1);
      -- Otherwise, this is a normal message
      ELSE
        PERFORM temba_insert_channelcount(NEW.channel_id, 'OM', NEW.created_on::date, 1);
      END IF;

    END IF;

  -- Assert that updates aren't happening that we don't approve of
  ELSIF TG_OP = 'UPDATE' THEN
    -- If the direction is changing, blow up
    IF NEW.direction <> OLD.direction THEN
      RAISE EXCEPTION 'Cannot change direction on messages';
    END IF;

    -- Cannot move from IVR to Text, or IVR to Text
    IF (OLD.msg_type <> 'V' AND NEW.msg_type = 'V') OR (OLD.msg_type = 'V' AND NEW.msg_type <> 'V') THEN
      RAISE EXCEPTION 'Cannot change a message from voice to something else or vice versa';
    END IF;

    -- Cannot change created_on
    IF NEW.created_on <> OLD.created_on THEN
      RAISE EXCEPTION 'Cannot change created_on on messages';
    END IF;

  -- Table being cleared, reset all counts
  ELSIF TG_OP = 'TRUNCATE' THEN
    DELETE FROM channels_channel WHERE count_type IN ('IV', 'IM', 'OV', 'OM');
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: temba_update_channellog_count(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_update_channellog_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- ChannelLog being added
  IF TG_OP = 'INSERT' THEN
    -- Error, increment our error count
    IF NEW.is_error THEN
      PERFORM temba_insert_channelcount(NEW.channel_id, 'LE', NULL::date, 1);
    -- Success, increment that count instead
    ELSE
      PERFORM temba_insert_channelcount(NEW.channel_id, 'LS', NULL::date, 1);
    END IF;

  -- Updating is_error is forbidden
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Cannot update is_error or channel_id on ChannelLog events';

  -- Deleting, decrement our count
  ELSIF TG_OP = 'DELETE' THEN
    -- Error, decrement our error count
    IF OLD.is_error THEN
      PERFORM temba_insert_channelcount(OLD.channel_id, 'LE', NULL::date, -1);
    -- Success, decrement that count instead
    ELSE
      PERFORM temba_insert_channelcount(OLD.channel_id, 'LS', NULL::date, -1);
    END IF;

  -- Table being cleared, reset all counts
  ELSIF TG_OP = 'TRUNCATE' THEN
    DELETE FROM channels_channel WHERE count_type IN ('LE', 'LS');
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: temba_update_flowpathcount(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_update_flowpathcount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE flow_id int;
BEGIN

  IF TG_OP = 'TRUNCATE' THEN
    -- FlowStep table being cleared, reset all counts
    DELETE FROM flows_flownodecount;
    DELETE FROM flows_flowpathcount;

  -- FlowStep being deleted
  ELSIF TG_OP = 'DELETE' THEN

    -- ignore if test contact
    IF temba_contact_is_test(OLD.contact_id) THEN
      RETURN NULL;
    END IF;

    flow_id = temba_flow_for_run(OLD.run_id);

    IF OLD.left_on IS NULL THEN
      PERFORM temba_insert_flownodecount(flow_id, UUID(OLD.step_uuid), -1);
    ELSE
      PERFORM temba_insert_flowpathcount(flow_id, temba_step_from_uuid(OLD), UUID(OLD.next_uuid), OLD.left_on, -1);
    END IF;

  -- FlowStep being added or left_on field updated
  ELSIF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN

    -- ignore if test contact
    IF temba_contact_is_test(NEW.contact_id) THEN
      RETURN NULL;
    END IF;

    flow_id = temba_flow_for_run(NEW.run_id);

    IF NEW.left_on IS NULL THEN
      PERFORM temba_insert_flownodecount(flow_id, UUID(NEW.step_uuid), 1);
    ELSE
      PERFORM temba_insert_flowpathcount(flow_id, temba_step_from_uuid(NEW), UUID(NEW.next_uuid), NEW.left_on, 1);
    END IF;

    IF TG_OP = 'UPDATE' THEN
      IF OLD.left_on IS NULL THEN
        PERFORM temba_insert_flownodecount(flow_id, UUID(OLD.step_uuid), -1);
      ELSE
        PERFORM temba_insert_flowpathcount(flow_id, temba_step_from_uuid(OLD), UUID(OLD.next_uuid), OLD.left_on, -1);
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: temba_update_flowruncount(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_update_flowruncount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Table being cleared, reset all counts
  IF TG_OP = 'TRUNCATE' THEN
    TRUNCATE flows_flowruncounts;
    RETURN NULL;
  END IF;

  -- FlowRun being added
  IF TG_OP = 'INSERT' THEN
     -- Is this a test contact, ignore
     IF temba_contact_is_test(NEW.contact_id) THEN
       RETURN NULL;
     END IF;

    -- Increment appropriate type
    PERFORM temba_insert_flowruncount(NEW.flow_id, NEW.exit_type, 1);

  -- FlowRun being removed
  ELSIF TG_OP = 'DELETE' THEN
     -- Is this a test contact, ignore
     IF temba_contact_is_test(OLD.contact_id) THEN
       RETURN NULL;
     END IF;

    PERFORM temba_insert_flowruncount(OLD.flow_id, OLD.exit_type, -1);

  -- Updating exit type
  ELSIF TG_OP = 'UPDATE' THEN
     -- Is this a test contact, ignore
     IF temba_contact_is_test(NEW.contact_id) THEN
       RETURN NULL;
     END IF;

    PERFORM temba_insert_flowruncount(OLD.flow_id, OLD.exit_type, -1);
    PERFORM temba_insert_flowruncount(NEW.flow_id, NEW.exit_type, 1);
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: temba_update_topupcredits(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_update_topupcredits() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Msg is being created
  IF TG_OP = 'INSERT' THEN
    -- If we have a topup, increment our # of used credits
    IF NEW.topup_id IS NOT NULL THEN
      PERFORM temba_insert_topupcredits(NEW.topup_id, 1);
    END IF;

  -- Msg is being updated
  ELSIF TG_OP = 'UPDATE' THEN
    -- If the topup has changed
    IF NEW.topup_id IS DISTINCT FROM OLD.topup_id THEN
      -- If our old topup wasn't null then decrement our used credits on it
      IF OLD.topup_id IS NOT NULL THEN
        PERFORM temba_insert_topupcredits(OLD.topup_id, -1);
      END IF;

      -- if our new topup isn't null, then increment our used credits on it
      IF NEW.topup_id IS NOT NULL THEN
        PERFORM temba_insert_topupcredits(NEW.topup_id, 1);
      END IF;
    END IF;

  -- Msg is being deleted
  ELSIF TG_OP = 'DELETE' THEN
    -- Remove a used credit if this Msg had one assigned
    IF OLD.topup_id IS NOT NULL THEN
      PERFORM temba_insert_topupcredits(OLD.topup_id, -1);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: temba_update_topupcredits_for_debit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION temba_update_topupcredits_for_debit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Debit is being created
  IF TG_OP = 'INSERT' THEN
    -- If we are an allocation and have a topup, increment our # of used credits
    IF NEW.topup_id IS NOT NULL AND NEW.debit_type = 'A' THEN
      PERFORM temba_insert_topupcredits(NEW.topup_id, NEW.amount);
    END IF;

  -- Debit is being updated
  ELSIF TG_OP = 'UPDATE' THEN
    -- If the topup has changed
    IF NEW.topup_id IS DISTINCT FROM OLD.topup_id AND NEW.debit_type = 'A' THEN
      -- If our old topup wasn't null then decrement our used credits on it
      IF OLD.topup_id IS NOT NULL THEN
        PERFORM temba_insert_topupcredits(OLD.topup_id, OLD.amount);
      END IF;

      -- if our new topup isn't null, then increment our used credits on it
      IF NEW.topup_id IS NOT NULL THEN
        PERFORM temba_insert_topupcredits(NEW.topup_id, NEW.amount);
      END IF;
    END IF;

  -- Debit is being deleted
  ELSIF TG_OP = 'DELETE' THEN
    -- Remove a used credit if this Debit had one assigned
    IF OLD.topup_id IS NOT NULL AND OLD.debit_type = 'A' THEN
      PERFORM temba_insert_topupcredits(OLD.topup_id, OLD.amount);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: update_contact_system_groups(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_contact_system_groups() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- new contact added
  IF TG_OP = 'INSERT' AND NEW.is_active AND NOT NEW.is_test THEN
    IF NEW.is_blocked THEN
      PERFORM contact_toggle_system_group(NEW, 'B', true);
    END IF;

    IF NEW.is_stopped THEN
      PERFORM contact_toggle_system_group(NEW, 'S', true);
    END IF;

    IF NOT NEW.is_stopped AND NOT NEW.is_blocked THEN
      PERFORM contact_toggle_system_group(NEW, 'A', true);
    END IF;
  END IF;

  -- existing contact updated
  IF TG_OP = 'UPDATE' AND NOT NEW.is_test THEN
    -- do nothing for inactive contacts
    IF NOT OLD.is_active AND NOT NEW.is_active THEN
      RETURN NULL;
    END IF;

    -- is being blocked
    IF NOT OLD.is_blocked AND NEW.is_blocked THEN
      PERFORM contact_toggle_system_group(NEW, 'B', true);
      PERFORM contact_toggle_system_group(NEW, 'A', false);
    END IF;

    -- is being unblocked
    IF OLD.is_blocked AND NOT NEW.is_blocked THEN
      PERFORM contact_toggle_system_group(NEW, 'B', false);
      IF NOT NEW.is_stopped THEN
        PERFORM contact_toggle_system_group(NEW, 'A', true);
      END IF;
    END IF;

    -- they stopped themselves
    IF NOT OLD.is_stopped AND NEW.is_stopped THEN
      PERFORM contact_toggle_system_group(NEW, 'S', true);
      PERFORM contact_toggle_system_group(NEW, 'A', false);
    END IF;

    -- they opted back in
    IF OLD.is_stopped AND NOT NEW.is_stopped THEN
    PERFORM contact_toggle_system_group(NEW, 'S', false);
      IF NOT NEW.is_blocked THEN
        PERFORM contact_toggle_system_group(NEW, 'A', true);
      END IF;
    END IF;

    -- is being released
    IF OLD.is_active AND NOT NEW.is_active THEN
      PERFORM contact_toggle_system_group(NEW, 'A', false);
      PERFORM contact_toggle_system_group(NEW, 'B', false);
      PERFORM contact_toggle_system_group(NEW, 'S', false);
    END IF;

    -- is being unreleased
    IF NOT OLD.is_active AND NEW.is_active THEN
      IF NEW.is_blocked THEN
        PERFORM contact_toggle_system_group(NEW, 'B', true);
      END IF;

      IF NEW.is_stopped THEN
        PERFORM contact_toggle_system_group(NEW, 'S', true);
      END IF;

      IF NOT NEW.is_stopped AND NOT NEW.is_blocked THEN
        PERFORM contact_toggle_system_group(NEW, 'A', true);
      END IF;
    END IF;

  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: update_group_count(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_group_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_test BOOLEAN;
BEGIN
  -- contact being added to group
  IF TG_OP = 'INSERT' THEN
    -- is this a test contact
    SELECT contacts_contact.is_test INTO STRICT is_test FROM contacts_contact WHERE id = NEW.contact_id;

    IF NOT is_test THEN
      INSERT INTO contacts_contactgroupcount("group_id", "count", "is_squashed")
      VALUES(NEW.contactgroup_id, 1, FALSE);
    END IF;

  -- contact being removed from a group
  ELSIF TG_OP = 'DELETE' THEN
    -- is this a test contact
    SELECT contacts_contact.is_test INTO STRICT is_test FROM contacts_contact WHERE id = OLD.contact_id;

    IF NOT is_test THEN
      INSERT INTO contacts_contactgroupcount("group_id", "count", "is_squashed")
      VALUES(OLD.contactgroup_id, -1, FALSE);
    END IF;

  -- table being cleared, clear our counts
  ELSIF TG_OP = 'TRUNCATE' THEN
    TRUNCATE contacts_contactgroupcount;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: airtime_airtimetransfer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE airtime_airtimetransfer (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    status character varying(1) NOT NULL,
    recipient character varying(64) NOT NULL,
    amount double precision NOT NULL,
    denomination character varying(32),
    data text,
    response text,
    message character varying(255),
    channel_id integer,
    contact_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: airtime_airtimetransfer_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE airtime_airtimetransfer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: airtime_airtimetransfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE airtime_airtimetransfer_id_seq OWNED BY airtime_airtimetransfer.id;


--
-- Name: api_apitoken; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE api_apitoken (
    is_active boolean NOT NULL,
    key character varying(40) NOT NULL,
    created timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    role_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: api_resthook; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE api_resthook (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    slug character varying(50) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: api_resthook_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE api_resthook_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_resthook_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE api_resthook_id_seq OWNED BY api_resthook.id;


--
-- Name: api_resthooksubscriber; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE api_resthooksubscriber (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    target_url character varying(200) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    resthook_id integer NOT NULL
);


--
-- Name: api_resthooksubscriber_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE api_resthooksubscriber_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_resthooksubscriber_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE api_resthooksubscriber_id_seq OWNED BY api_resthooksubscriber.id;


--
-- Name: api_webhookevent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE api_webhookevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    status character varying(1) NOT NULL,
    event character varying(16) NOT NULL,
    data text NOT NULL,
    try_count integer NOT NULL,
    next_attempt timestamp with time zone,
    action character varying(8) NOT NULL,
    channel_id integer,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    resthook_id integer,
    run_id integer
);


--
-- Name: api_webhookevent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE api_webhookevent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_webhookevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE api_webhookevent_id_seq OWNED BY api_webhookevent.id;


--
-- Name: api_webhookresult; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE api_webhookresult (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    url text,
    data text,
    request text,
    status_code integer NOT NULL,
    message character varying(255) NOT NULL,
    body text,
    created_by_id integer NOT NULL,
    event_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    request_time integer
);


--
-- Name: api_webhookresult_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE api_webhookresult_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_webhookresult_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE api_webhookresult_id_seq OWNED BY api_webhookresult.id;


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE auth_group (
    id integer NOT NULL,
    name character varying(80) NOT NULL
);


--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_group_id_seq OWNED BY auth_group.id;


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE auth_group_permissions (
    id integer NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_group_permissions_id_seq OWNED BY auth_group_permissions.id;


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_permission_id_seq OWNED BY auth_permission.id;


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(254) NOT NULL,
    first_name character varying(30) NOT NULL,
    last_name character varying(30) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE auth_user_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_user_groups_id_seq OWNED BY auth_user_groups.id;


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_user_id_seq OWNED BY auth_user.id;


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE auth_user_user_permissions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_user_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_user_user_permissions_id_seq OWNED BY auth_user_user_permissions.id;


--
-- Name: authtoken_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE authtoken_token (
    key character varying(40) NOT NULL,
    created timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: campaigns_campaign; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE campaigns_campaign (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    is_archived boolean NOT NULL,
    created_by_id integer NOT NULL,
    group_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE campaigns_campaign_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE campaigns_campaign_id_seq OWNED BY campaigns_campaign.id;


--
-- Name: campaigns_campaignevent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE campaigns_campaignevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    "offset" integer NOT NULL,
    unit character varying(1) NOT NULL,
    event_type character varying(1) NOT NULL,
    delivery_hour integer NOT NULL,
    campaign_id integer NOT NULL,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    relative_to_id integer NOT NULL,
    message hstore
);


--
-- Name: campaigns_campaignevent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE campaigns_campaignevent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_campaignevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE campaigns_campaignevent_id_seq OWNED BY campaigns_campaignevent.id;


--
-- Name: campaigns_eventfire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE campaigns_eventfire (
    id integer NOT NULL,
    scheduled timestamp with time zone NOT NULL,
    fired timestamp with time zone,
    contact_id integer NOT NULL,
    event_id integer NOT NULL
);


--
-- Name: campaigns_eventfire_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE campaigns_eventfire_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_eventfire_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE campaigns_eventfire_id_seq OWNED BY campaigns_eventfire.id;


--
-- Name: channels_alert; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE channels_alert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    alert_type character varying(1) NOT NULL,
    ended_on timestamp with time zone,
    channel_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    sync_event_id integer
);


--
-- Name: channels_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_alert_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_alert_id_seq OWNED BY channels_alert.id;


--
-- Name: channels_channel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE channels_channel (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    channel_type character varying(3) NOT NULL,
    name character varying(64),
    address character varying(255),
    country character varying(2),
    gcm_id character varying(255),
    claim_code character varying(16),
    secret character varying(64),
    last_seen timestamp with time zone NOT NULL,
    device character varying(255),
    os character varying(255),
    alert_email character varying(254),
    config text,
    scheme character varying(8) NOT NULL,
    role character varying(4) NOT NULL,
    bod text,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer,
    parent_id integer,
    tps integer
);


--
-- Name: channels_channel_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_channel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_channel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_channel_id_seq OWNED BY channels_channel.id;


--
-- Name: channels_channelcount_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_channelcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_channelcount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE channels_channelcount (
    id bigint DEFAULT nextval('channels_channelcount_id_seq'::regclass) NOT NULL,
    count_type character varying(2) NOT NULL,
    day date,
    count integer NOT NULL,
    channel_id integer NOT NULL,
    is_squashed boolean NOT NULL
);


--
-- Name: channels_channelevent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_channelevent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_channelevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_channelevent_id_seq OWNED BY channels_channelevent.id;


--
-- Name: channels_channellog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE channels_channellog (
    id integer NOT NULL,
    description character varying(255) NOT NULL,
    is_error boolean NOT NULL,
    url text,
    method character varying(16),
    request text,
    response text,
    response_status integer,
    created_on timestamp with time zone NOT NULL,
    request_time integer,
    channel_id integer NOT NULL,
    msg_id integer,
    session_id integer
);


--
-- Name: channels_channellog_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_channellog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_channellog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_channellog_id_seq OWNED BY channels_channellog.id;


--
-- Name: channels_channelsession; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE channels_channelsession (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    external_id character varying(255) NOT NULL,
    status character varying(1) NOT NULL,
    direction character varying(1) NOT NULL,
    started_on timestamp with time zone,
    ended_on timestamp with time zone,
    session_type character varying(1) NOT NULL,
    duration integer,
    channel_id integer NOT NULL,
    contact_id integer NOT NULL,
    contact_urn_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: channels_channelsession_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_channelsession_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_channelsession_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_channelsession_id_seq OWNED BY channels_channelsession.id;


--
-- Name: channels_syncevent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE channels_syncevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    power_source character varying(64) NOT NULL,
    power_status character varying(64) NOT NULL,
    power_level integer NOT NULL,
    network_type character varying(128) NOT NULL,
    lifetime integer,
    pending_message_count integer NOT NULL,
    retry_message_count integer NOT NULL,
    incoming_command_count integer NOT NULL,
    outgoing_command_count integer NOT NULL,
    channel_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: channels_syncevent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_syncevent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_syncevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_syncevent_id_seq OWNED BY channels_syncevent.id;


--
-- Name: contacts_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contact_id_seq OWNED BY contacts_contact.id;


--
-- Name: contacts_contactfield; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_contactfield (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    label character varying(36) NOT NULL,
    key character varying(36) NOT NULL,
    value_type character varying(1) NOT NULL,
    show_in_table boolean NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: contacts_contactfield_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactfield_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactfield_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactfield_id_seq OWNED BY contacts_contactfield.id;


--
-- Name: contacts_contactgroup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_contactgroup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    group_type character varying(1) NOT NULL,
    query text,
    created_by_id integer NOT NULL,
    import_task_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: contacts_contactgroup_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_contactgroup_contacts (
    id integer NOT NULL,
    contactgroup_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: contacts_contactgroup_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactgroup_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactgroup_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactgroup_contacts_id_seq OWNED BY contacts_contactgroup_contacts.id;


--
-- Name: contacts_contactgroup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactgroup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactgroup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactgroup_id_seq OWNED BY contacts_contactgroup.id;


--
-- Name: contacts_contactgroup_query_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_contactgroup_query_fields (
    id integer NOT NULL,
    contactgroup_id integer NOT NULL,
    contactfield_id integer NOT NULL
);


--
-- Name: contacts_contactgroup_query_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactgroup_query_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactgroup_query_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactgroup_query_fields_id_seq OWNED BY contacts_contactgroup_query_fields.id;


--
-- Name: contacts_contactgroupcount_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactgroupcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactgroupcount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_contactgroupcount (
    id bigint DEFAULT nextval('contacts_contactgroupcount_id_seq'::regclass) NOT NULL,
    count integer NOT NULL,
    group_id integer NOT NULL,
    is_squashed boolean NOT NULL
);


--
-- Name: contacts_contacturn; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_contacturn (
    id integer NOT NULL,
    identity character varying(255) NOT NULL,
    path character varying(255) NOT NULL,
    scheme character varying(128) NOT NULL,
    priority integer NOT NULL,
    channel_id integer,
    contact_id integer,
    org_id integer NOT NULL,
    auth text,
    display character varying(255)
);


--
-- Name: contacts_contacturn_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contacturn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contacturn_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contacturn_id_seq OWNED BY contacts_contacturn.id;


--
-- Name: contacts_exportcontactstask; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE contacts_exportcontactstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    created_by_id integer NOT NULL,
    group_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    status character varying(1) NOT NULL,
    search text
);


--
-- Name: contacts_exportcontactstask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_exportcontactstask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_exportcontactstask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_exportcontactstask_id_seq OWNED BY contacts_exportcontactstask.id;


--
-- Name: csv_imports_importtask; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE csv_imports_importtask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    csv_file character varying(100) NOT NULL,
    model_class character varying(255) NOT NULL,
    import_params text,
    import_log text NOT NULL,
    import_results text,
    task_id character varying(64),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    task_status character varying(32) NOT NULL
);


--
-- Name: csv_imports_importtask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE csv_imports_importtask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: csv_imports_importtask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE csv_imports_importtask_id_seq OWNED BY csv_imports_importtask.id;


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_content_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE django_content_type_id_seq OWNED BY django_content_type.id;


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE django_migrations (
    id integer NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE django_migrations_id_seq OWNED BY django_migrations.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


--
-- Name: django_site; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE django_site (
    id integer NOT NULL,
    domain character varying(100) NOT NULL,
    name character varying(50) NOT NULL
);


--
-- Name: django_site_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE django_site_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_site_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE django_site_id_seq OWNED BY django_site.id;


--
-- Name: flows_actionlog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_actionlog (
    id integer NOT NULL,
    text text NOT NULL,
    level character varying(1) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    run_id integer NOT NULL
);


--
-- Name: flows_actionlog_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_actionlog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_actionlog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_actionlog_id_seq OWNED BY flows_actionlog.id;


--
-- Name: flows_actionset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_actionset (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    destination character varying(36),
    destination_type character varying(1),
    actions text NOT NULL,
    x integer NOT NULL,
    y integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    flow_id integer NOT NULL
);


--
-- Name: flows_actionset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_actionset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_actionset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_actionset_id_seq OWNED BY flows_actionset.id;


--
-- Name: flows_exportflowresultstask; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_exportflowresultstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    config text,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    status character varying(1) NOT NULL
);


--
-- Name: flows_exportflowresultstask_flows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_exportflowresultstask_flows (
    id integer NOT NULL,
    exportflowresultstask_id integer NOT NULL,
    flow_id integer NOT NULL
);


--
-- Name: flows_exportflowresultstask_flows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_exportflowresultstask_flows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_exportflowresultstask_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_exportflowresultstask_flows_id_seq OWNED BY flows_exportflowresultstask_flows.id;


--
-- Name: flows_exportflowresultstask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_exportflowresultstask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_exportflowresultstask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_exportflowresultstask_id_seq OWNED BY flows_exportflowresultstask.id;


--
-- Name: flows_flow; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flow (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    entry_uuid character varying(36),
    entry_type character varying(1),
    is_archived boolean NOT NULL,
    flow_type character varying(1) NOT NULL,
    metadata text,
    expires_after_minutes integer NOT NULL,
    ignore_triggers boolean NOT NULL,
    saved_on timestamp with time zone NOT NULL,
    base_language character varying(4),
    version_number integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    saved_by_id integer NOT NULL
);


--
-- Name: flows_flow_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flow_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flow_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flow_id_seq OWNED BY flows_flow.id;


--
-- Name: flows_flow_labels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flow_labels (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    flowlabel_id integer NOT NULL
);


--
-- Name: flows_flow_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flow_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flow_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flow_labels_id_seq OWNED BY flows_flow_labels.id;


--
-- Name: flows_flowlabel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowlabel (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    org_id integer NOT NULL,
    parent_id integer
);


--
-- Name: flows_flowlabel_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowlabel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowlabel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowlabel_id_seq OWNED BY flows_flowlabel.id;


--
-- Name: flows_flownodecount_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flownodecount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flownodecount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flownodecount (
    id bigint DEFAULT nextval('flows_flownodecount_id_seq'::regclass) NOT NULL,
    is_squashed boolean NOT NULL,
    node_uuid uuid NOT NULL,
    count integer NOT NULL,
    flow_id integer NOT NULL
);


--
-- Name: flows_flowpathcount_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowpathcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowpathcount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowpathcount (
    id bigint DEFAULT nextval('flows_flowpathcount_id_seq'::regclass) NOT NULL,
    from_uuid uuid NOT NULL,
    to_uuid uuid,
    period timestamp with time zone NOT NULL,
    count integer NOT NULL,
    flow_id integer NOT NULL,
    is_squashed boolean NOT NULL
);


--
-- Name: flows_flowpathrecentmessage_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowpathrecentmessage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowpathrecentmessage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowpathrecentmessage (
    id bigint DEFAULT nextval('flows_flowpathrecentmessage_id_seq'::regclass) NOT NULL,
    from_uuid uuid NOT NULL,
    to_uuid uuid NOT NULL,
    text text NOT NULL,
    created_on timestamp with time zone NOT NULL,
    run_id integer NOT NULL
);


--
-- Name: flows_flowrevision; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowrevision (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    definition text NOT NULL,
    spec_version integer NOT NULL,
    revision integer,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: flows_flowrevision_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowrevision_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowrevision_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowrevision_id_seq OWNED BY flows_flowrevision.id;


--
-- Name: flows_flowrun; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowrun (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    fields text,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    exited_on timestamp with time zone,
    exit_type character varying(1),
    expires_on timestamp with time zone,
    timeout_on timestamp with time zone,
    responded boolean NOT NULL,
    contact_id integer NOT NULL,
    flow_id integer NOT NULL,
    org_id integer NOT NULL,
    parent_id integer,
    session_id integer,
    start_id integer,
    submitted_by_id integer,
    uuid uuid NOT NULL
);


--
-- Name: flows_flowrun_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowrun_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowrun_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowrun_id_seq OWNED BY flows_flowrun.id;


--
-- Name: flows_flowruncount_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowruncount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowruncount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowruncount (
    id bigint DEFAULT nextval('flows_flowruncount_id_seq'::regclass) NOT NULL,
    exit_type character varying(1),
    count integer NOT NULL,
    flow_id integer NOT NULL,
    is_squashed boolean NOT NULL
);


--
-- Name: flows_flowstart; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowstart (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    restart_participants boolean NOT NULL,
    contact_count integer NOT NULL,
    status character varying(1) NOT NULL,
    extra text,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    include_active boolean NOT NULL,
    uuid uuid NOT NULL
);


--
-- Name: flows_flowstart_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowstart_contacts (
    id integer NOT NULL,
    flowstart_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: flows_flowstart_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstart_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstart_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstart_contacts_id_seq OWNED BY flows_flowstart_contacts.id;


--
-- Name: flows_flowstart_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowstart_groups (
    id integer NOT NULL,
    flowstart_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: flows_flowstart_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstart_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstart_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstart_groups_id_seq OWNED BY flows_flowstart_groups.id;


--
-- Name: flows_flowstart_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstart_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstart_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstart_id_seq OWNED BY flows_flowstart.id;


--
-- Name: flows_flowstep_broadcasts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowstep_broadcasts (
    id integer NOT NULL,
    flowstep_id integer NOT NULL,
    broadcast_id integer NOT NULL
);


--
-- Name: flows_flowstep_broadcasts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstep_broadcasts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstep_broadcasts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstep_broadcasts_id_seq OWNED BY flows_flowstep_broadcasts.id;


--
-- Name: flows_flowstep_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstep_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstep_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstep_id_seq OWNED BY flows_flowstep.id;


--
-- Name: flows_flowstep_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_flowstep_messages (
    id integer NOT NULL,
    flowstep_id integer NOT NULL,
    msg_id integer NOT NULL
);


--
-- Name: flows_flowstep_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstep_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstep_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstep_messages_id_seq OWNED BY flows_flowstep_messages.id;


--
-- Name: flows_ruleset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE flows_ruleset (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    label character varying(64),
    operand character varying(128),
    webhook_url character varying(255),
    webhook_action character varying(8),
    rules text NOT NULL,
    finished_key character varying(1),
    value_type character varying(1) NOT NULL,
    ruleset_type character varying(16),
    response_type character varying(1) NOT NULL,
    config text,
    x integer NOT NULL,
    y integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    flow_id integer NOT NULL
);


--
-- Name: flows_ruleset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_ruleset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_ruleset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_ruleset_id_seq OWNED BY flows_ruleset.id;


--
-- Name: guardian_groupobjectpermission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE guardian_groupobjectpermission (
    id integer NOT NULL,
    object_pk character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: guardian_groupobjectpermission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE guardian_groupobjectpermission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: guardian_groupobjectpermission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE guardian_groupobjectpermission_id_seq OWNED BY guardian_groupobjectpermission.id;


--
-- Name: guardian_userobjectpermission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE guardian_userobjectpermission (
    id integer NOT NULL,
    object_pk character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    permission_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: guardian_userobjectpermission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE guardian_userobjectpermission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: guardian_userobjectpermission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE guardian_userobjectpermission_id_seq OWNED BY guardian_userobjectpermission.id;


--
-- Name: locations_adminboundary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE locations_adminboundary (
    id integer NOT NULL,
    osm_id character varying(15) NOT NULL,
    name character varying(128) NOT NULL,
    level integer NOT NULL,
    geometry geometry(MultiPolygon,4326),
    simplified_geometry geometry(MultiPolygon,4326),
    lft integer NOT NULL,
    rght integer NOT NULL,
    tree_id integer NOT NULL,
    parent_id integer,
    CONSTRAINT locations_adminboundary_lft_check CHECK ((lft >= 0)),
    CONSTRAINT locations_adminboundary_rght_check CHECK ((rght >= 0)),
    CONSTRAINT locations_adminboundary_tree_id_check CHECK ((tree_id >= 0))
);


--
-- Name: locations_adminboundary_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE locations_adminboundary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations_adminboundary_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE locations_adminboundary_id_seq OWNED BY locations_adminboundary.id;


--
-- Name: locations_boundaryalias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE locations_boundaryalias (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    boundary_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: locations_boundaryalias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE locations_boundaryalias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations_boundaryalias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE locations_boundaryalias_id_seq OWNED BY locations_boundaryalias.id;


--
-- Name: msgs_broadcast_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_broadcast_contacts (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: msgs_broadcast_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_contacts_id_seq OWNED BY msgs_broadcast_contacts.id;


--
-- Name: msgs_broadcast_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_broadcast_groups (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: msgs_broadcast_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_groups_id_seq OWNED BY msgs_broadcast_groups.id;


--
-- Name: msgs_broadcast_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_id_seq OWNED BY msgs_broadcast.id;


--
-- Name: msgs_broadcast_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_broadcast_recipients (
    id integer NOT NULL,
    purged_status character varying(1),
    broadcast_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: msgs_broadcast_recipients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_recipients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_recipients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_recipients_id_seq OWNED BY msgs_broadcast_recipients.id;


--
-- Name: msgs_broadcast_urns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_broadcast_urns (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contacturn_id integer NOT NULL
);


--
-- Name: msgs_broadcast_urns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_urns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_urns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_urns_id_seq OWNED BY msgs_broadcast_urns.id;


--
-- Name: msgs_exportmessagestask; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_exportmessagestask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    start_date date,
    end_date date,
    uuid character varying(36) NOT NULL,
    created_by_id integer NOT NULL,
    label_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    status character varying(1) NOT NULL,
    system_label character varying(1)
);


--
-- Name: msgs_exportmessagestask_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_exportmessagestask_groups (
    id integer NOT NULL,
    exportmessagestask_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: msgs_exportmessagestask_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_exportmessagestask_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_exportmessagestask_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_exportmessagestask_groups_id_seq OWNED BY msgs_exportmessagestask_groups.id;


--
-- Name: msgs_exportmessagestask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_exportmessagestask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_exportmessagestask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_exportmessagestask_id_seq OWNED BY msgs_exportmessagestask.id;


--
-- Name: msgs_label; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_label (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    uuid character varying(36) NOT NULL,
    name character varying(64) NOT NULL,
    label_type character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    folder_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: msgs_label_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_label_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_label_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_label_id_seq OWNED BY msgs_label.id;


--
-- Name: msgs_labelcount_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_labelcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_labelcount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_labelcount (
    id bigint DEFAULT nextval('msgs_labelcount_id_seq'::regclass) NOT NULL,
    is_squashed boolean NOT NULL,
    count integer NOT NULL,
    label_id integer NOT NULL
);


--
-- Name: msgs_msg_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_msg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_msg_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_msg_id_seq OWNED BY msgs_msg.id;


--
-- Name: msgs_msg_labels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_msg_labels (
    id integer NOT NULL,
    msg_id integer NOT NULL,
    label_id integer NOT NULL
);


--
-- Name: msgs_msg_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_msg_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_msg_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_msg_labels_id_seq OWNED BY msgs_msg_labels.id;


--
-- Name: msgs_systemlabelcount_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_systemlabelcount_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_systemlabelcount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE msgs_systemlabelcount (
    id bigint DEFAULT nextval('msgs_systemlabelcount_id_seq'::regclass) NOT NULL,
    label_type character varying(1) NOT NULL,
    count integer NOT NULL,
    org_id integer NOT NULL,
    is_squashed boolean NOT NULL
);


--
-- Name: msgs_systemlabel_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_systemlabel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_systemlabel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_systemlabel_id_seq OWNED BY msgs_systemlabelcount.id;


--
-- Name: orgs_creditalert; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_creditalert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    alert_type character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: orgs_creditalert_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_creditalert_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_creditalert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_creditalert_id_seq OWNED BY orgs_creditalert.id;


--
-- Name: orgs_debit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_debit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_debit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_debit (
    id bigint DEFAULT nextval('orgs_debit_id_seq'::regclass) NOT NULL,
    amount integer NOT NULL,
    debit_type character varying(1) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    beneficiary_id integer,
    created_by_id integer,
    topup_id integer NOT NULL,
    is_squashed boolean NOT NULL
);


--
-- Name: orgs_invitation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_invitation (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    email character varying(254) NOT NULL,
    secret character varying(64) NOT NULL,
    user_group character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: orgs_invitation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_invitation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_invitation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_invitation_id_seq OWNED BY orgs_invitation.id;


--
-- Name: orgs_language; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_language (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    iso_code character varying(4) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: orgs_language_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_language_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_language_id_seq OWNED BY orgs_language.id;


--
-- Name: orgs_org; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_org (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    plan character varying(16) NOT NULL,
    plan_start timestamp with time zone NOT NULL,
    stripe_customer character varying(32),
    language character varying(64),
    timezone character varying(63) NOT NULL,
    date_format character varying(1) NOT NULL,
    webhook text,
    webhook_events integer NOT NULL,
    msg_last_viewed timestamp with time zone NOT NULL,
    flows_last_viewed timestamp with time zone NOT NULL,
    config text,
    slug character varying(255),
    is_anon boolean NOT NULL,
    is_purgeable boolean NOT NULL,
    brand character varying(128) NOT NULL,
    surveyor_password character varying(128),
    country_id integer,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    parent_id integer,
    primary_language_id integer
);


--
-- Name: orgs_org_administrators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_org_administrators (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: orgs_org_administrators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_administrators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_administrators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_administrators_id_seq OWNED BY orgs_org_administrators.id;


--
-- Name: orgs_org_editors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_org_editors (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: orgs_org_editors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_editors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_editors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_editors_id_seq OWNED BY orgs_org_editors.id;


--
-- Name: orgs_org_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_id_seq OWNED BY orgs_org.id;


--
-- Name: orgs_org_surveyors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_org_surveyors (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: orgs_org_surveyors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_surveyors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_surveyors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_surveyors_id_seq OWNED BY orgs_org_surveyors.id;


--
-- Name: orgs_org_viewers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_org_viewers (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: orgs_org_viewers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_viewers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_viewers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_viewers_id_seq OWNED BY orgs_org_viewers.id;


--
-- Name: orgs_topup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_topup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    price integer,
    credits integer NOT NULL,
    expires_on timestamp with time zone NOT NULL,
    stripe_charge character varying(32),
    comment character varying(255),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: orgs_topup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_topup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_topup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_topup_id_seq OWNED BY orgs_topup.id;


--
-- Name: orgs_topupcredits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_topupcredits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_topupcredits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_topupcredits (
    id bigint DEFAULT nextval('orgs_topupcredits_id_seq'::regclass) NOT NULL,
    used integer NOT NULL,
    topup_id integer NOT NULL,
    is_squashed boolean NOT NULL
);


--
-- Name: orgs_usersettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE orgs_usersettings (
    id integer NOT NULL,
    language character varying(8) NOT NULL,
    tel character varying(16),
    user_id integer NOT NULL
);


--
-- Name: orgs_usersettings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_usersettings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_usersettings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_usersettings_id_seq OWNED BY orgs_usersettings.id;


--
-- Name: public_lead; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public_lead (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    email character varying(254) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: public_lead_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public_lead_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: public_lead_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public_lead_id_seq OWNED BY public_lead.id;


--
-- Name: public_video; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public_video (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(255) NOT NULL,
    summary text NOT NULL,
    description text NOT NULL,
    vimeo_id character varying(255) NOT NULL,
    "order" integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: public_video_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public_video_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: public_video_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public_video_id_seq OWNED BY public_video.id;


--
-- Name: reports_report; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE reports_report (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    title character varying(64) NOT NULL,
    description text NOT NULL,
    config text,
    is_published boolean NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE reports_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reports_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE reports_report_id_seq OWNED BY reports_report.id;


--
-- Name: schedules_schedule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE schedules_schedule (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    status character varying(1) NOT NULL,
    repeat_hour_of_day integer,
    repeat_minute_of_hour integer,
    repeat_day_of_month integer,
    repeat_period character varying(1),
    repeat_days integer,
    last_fire timestamp with time zone,
    next_fire timestamp with time zone,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: schedules_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE schedules_schedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedules_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE schedules_schedule_id_seq OWNED BY schedules_schedule.id;


--
-- Name: triggers_trigger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE triggers_trigger (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    keyword character varying(16),
    last_triggered timestamp with time zone,
    trigger_count integer NOT NULL,
    is_archived boolean NOT NULL,
    trigger_type character varying(1) NOT NULL,
    channel_id integer,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    schedule_id integer,
    referrer_id character varying(255),
    match_type character varying(1)
);


--
-- Name: triggers_trigger_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE triggers_trigger_contacts (
    id integer NOT NULL,
    trigger_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: triggers_trigger_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE triggers_trigger_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: triggers_trigger_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE triggers_trigger_contacts_id_seq OWNED BY triggers_trigger_contacts.id;


--
-- Name: triggers_trigger_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE triggers_trigger_groups (
    id integer NOT NULL,
    trigger_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: triggers_trigger_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE triggers_trigger_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: triggers_trigger_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE triggers_trigger_groups_id_seq OWNED BY triggers_trigger_groups.id;


--
-- Name: triggers_trigger_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE triggers_trigger_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: triggers_trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE triggers_trigger_id_seq OWNED BY triggers_trigger.id;


--
-- Name: users_failedlogin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE users_failedlogin (
    id integer NOT NULL,
    failed_on timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: users_failedlogin_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_failedlogin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_failedlogin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_failedlogin_id_seq OWNED BY users_failedlogin.id;


--
-- Name: users_passwordhistory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE users_passwordhistory (
    id integer NOT NULL,
    password character varying(255) NOT NULL,
    set_on timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: users_passwordhistory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_passwordhistory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_passwordhistory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_passwordhistory_id_seq OWNED BY users_passwordhistory.id;


--
-- Name: users_recoverytoken; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE users_recoverytoken (
    id integer NOT NULL,
    token character varying(32) NOT NULL,
    created_on timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: users_recoverytoken_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_recoverytoken_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_recoverytoken_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_recoverytoken_id_seq OWNED BY users_recoverytoken.id;


--
-- Name: values_value; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE values_value (
    id integer NOT NULL,
    rule_uuid character varying(255),
    category character varying(128),
    string_value text NOT NULL,
    decimal_value numeric(36,8),
    datetime_value timestamp with time zone,
    media_value text,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    contact_id integer NOT NULL,
    contact_field_id integer,
    location_value_id integer,
    org_id integer NOT NULL,
    ruleset_id integer,
    run_id integer
);


--
-- Name: values_value_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE values_value_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: values_value_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE values_value_id_seq OWNED BY values_value.id;


--
-- Name: airtime_airtimetransfer id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY airtime_airtimetransfer ALTER COLUMN id SET DEFAULT nextval('airtime_airtimetransfer_id_seq'::regclass);


--
-- Name: api_resthook id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthook ALTER COLUMN id SET DEFAULT nextval('api_resthook_id_seq'::regclass);


--
-- Name: api_resthooksubscriber id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthooksubscriber ALTER COLUMN id SET DEFAULT nextval('api_resthooksubscriber_id_seq'::regclass);


--
-- Name: api_webhookevent id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent ALTER COLUMN id SET DEFAULT nextval('api_webhookevent_id_seq'::regclass);


--
-- Name: api_webhookresult id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult ALTER COLUMN id SET DEFAULT nextval('api_webhookresult_id_seq'::regclass);


--
-- Name: auth_group id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group ALTER COLUMN id SET DEFAULT nextval('auth_group_id_seq'::regclass);


--
-- Name: auth_group_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('auth_group_permissions_id_seq'::regclass);


--
-- Name: auth_permission id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission ALTER COLUMN id SET DEFAULT nextval('auth_permission_id_seq'::regclass);


--
-- Name: auth_user id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user ALTER COLUMN id SET DEFAULT nextval('auth_user_id_seq'::regclass);


--
-- Name: auth_user_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups ALTER COLUMN id SET DEFAULT nextval('auth_user_groups_id_seq'::regclass);


--
-- Name: auth_user_user_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('auth_user_user_permissions_id_seq'::regclass);


--
-- Name: campaigns_campaign id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign ALTER COLUMN id SET DEFAULT nextval('campaigns_campaign_id_seq'::regclass);


--
-- Name: campaigns_campaignevent id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent ALTER COLUMN id SET DEFAULT nextval('campaigns_campaignevent_id_seq'::regclass);


--
-- Name: campaigns_eventfire id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire ALTER COLUMN id SET DEFAULT nextval('campaigns_eventfire_id_seq'::regclass);


--
-- Name: channels_alert id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert ALTER COLUMN id SET DEFAULT nextval('channels_alert_id_seq'::regclass);


--
-- Name: channels_channel id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel ALTER COLUMN id SET DEFAULT nextval('channels_channel_id_seq'::regclass);


--
-- Name: channels_channelevent id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelevent ALTER COLUMN id SET DEFAULT nextval('channels_channelevent_id_seq'::regclass);


--
-- Name: channels_channellog id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog ALTER COLUMN id SET DEFAULT nextval('channels_channellog_id_seq'::regclass);


--
-- Name: channels_channelsession id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession ALTER COLUMN id SET DEFAULT nextval('channels_channelsession_id_seq'::regclass);


--
-- Name: channels_syncevent id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent ALTER COLUMN id SET DEFAULT nextval('channels_syncevent_id_seq'::regclass);


--
-- Name: contacts_contact id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact ALTER COLUMN id SET DEFAULT nextval('contacts_contact_id_seq'::regclass);


--
-- Name: contacts_contactfield id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield ALTER COLUMN id SET DEFAULT nextval('contacts_contactfield_id_seq'::regclass);


--
-- Name: contacts_contactgroup id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_id_seq'::regclass);


--
-- Name: contacts_contactgroup_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_contacts_id_seq'::regclass);


--
-- Name: contacts_contactgroup_query_fields id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_query_fields_id_seq'::regclass);


--
-- Name: contacts_contacturn id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn ALTER COLUMN id SET DEFAULT nextval('contacts_contacturn_id_seq'::regclass);


--
-- Name: contacts_exportcontactstask id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask ALTER COLUMN id SET DEFAULT nextval('contacts_exportcontactstask_id_seq'::regclass);


--
-- Name: csv_imports_importtask id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask ALTER COLUMN id SET DEFAULT nextval('csv_imports_importtask_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_content_type ALTER COLUMN id SET DEFAULT nextval('django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_migrations ALTER COLUMN id SET DEFAULT nextval('django_migrations_id_seq'::regclass);


--
-- Name: django_site id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_site ALTER COLUMN id SET DEFAULT nextval('django_site_id_seq'::regclass);


--
-- Name: flows_actionlog id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionlog ALTER COLUMN id SET DEFAULT nextval('flows_actionlog_id_seq'::regclass);


--
-- Name: flows_actionset id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset ALTER COLUMN id SET DEFAULT nextval('flows_actionset_id_seq'::regclass);


--
-- Name: flows_exportflowresultstask id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask ALTER COLUMN id SET DEFAULT nextval('flows_exportflowresultstask_id_seq'::regclass);


--
-- Name: flows_exportflowresultstask_flows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows ALTER COLUMN id SET DEFAULT nextval('flows_exportflowresultstask_flows_id_seq'::regclass);


--
-- Name: flows_flow id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow ALTER COLUMN id SET DEFAULT nextval('flows_flow_id_seq'::regclass);


--
-- Name: flows_flow_labels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels ALTER COLUMN id SET DEFAULT nextval('flows_flow_labels_id_seq'::regclass);


--
-- Name: flows_flowlabel id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel ALTER COLUMN id SET DEFAULT nextval('flows_flowlabel_id_seq'::regclass);


--
-- Name: flows_flowrevision id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrevision ALTER COLUMN id SET DEFAULT nextval('flows_flowrevision_id_seq'::regclass);


--
-- Name: flows_flowrun id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun ALTER COLUMN id SET DEFAULT nextval('flows_flowrun_id_seq'::regclass);


--
-- Name: flows_flowstart id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_id_seq'::regclass);


--
-- Name: flows_flowstart_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_contacts_id_seq'::regclass);


--
-- Name: flows_flowstart_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_groups_id_seq'::regclass);


--
-- Name: flows_flowstep id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep ALTER COLUMN id SET DEFAULT nextval('flows_flowstep_id_seq'::regclass);


--
-- Name: flows_flowstep_broadcasts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_broadcasts ALTER COLUMN id SET DEFAULT nextval('flows_flowstep_broadcasts_id_seq'::regclass);


--
-- Name: flows_flowstep_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages ALTER COLUMN id SET DEFAULT nextval('flows_flowstep_messages_id_seq'::regclass);


--
-- Name: flows_ruleset id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset ALTER COLUMN id SET DEFAULT nextval('flows_ruleset_id_seq'::regclass);


--
-- Name: guardian_groupobjectpermission id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission ALTER COLUMN id SET DEFAULT nextval('guardian_groupobjectpermission_id_seq'::regclass);


--
-- Name: guardian_userobjectpermission id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission ALTER COLUMN id SET DEFAULT nextval('guardian_userobjectpermission_id_seq'::regclass);


--
-- Name: locations_adminboundary id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary ALTER COLUMN id SET DEFAULT nextval('locations_adminboundary_id_seq'::regclass);


--
-- Name: locations_boundaryalias id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias ALTER COLUMN id SET DEFAULT nextval('locations_boundaryalias_id_seq'::regclass);


--
-- Name: msgs_broadcast id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_id_seq'::regclass);


--
-- Name: msgs_broadcast_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_contacts_id_seq'::regclass);


--
-- Name: msgs_broadcast_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_groups_id_seq'::regclass);


--
-- Name: msgs_broadcast_recipients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_recipients ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_recipients_id_seq'::regclass);


--
-- Name: msgs_broadcast_urns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_urns_id_seq'::regclass);


--
-- Name: msgs_exportmessagestask id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask ALTER COLUMN id SET DEFAULT nextval('msgs_exportmessagestask_id_seq'::regclass);


--
-- Name: msgs_exportmessagestask_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups ALTER COLUMN id SET DEFAULT nextval('msgs_exportmessagestask_groups_id_seq'::regclass);


--
-- Name: msgs_label id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label ALTER COLUMN id SET DEFAULT nextval('msgs_label_id_seq'::regclass);


--
-- Name: msgs_msg id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg ALTER COLUMN id SET DEFAULT nextval('msgs_msg_id_seq'::regclass);


--
-- Name: msgs_msg_labels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels ALTER COLUMN id SET DEFAULT nextval('msgs_msg_labels_id_seq'::regclass);


--
-- Name: orgs_creditalert id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert ALTER COLUMN id SET DEFAULT nextval('orgs_creditalert_id_seq'::regclass);


--
-- Name: orgs_invitation id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation ALTER COLUMN id SET DEFAULT nextval('orgs_invitation_id_seq'::regclass);


--
-- Name: orgs_language id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language ALTER COLUMN id SET DEFAULT nextval('orgs_language_id_seq'::regclass);


--
-- Name: orgs_org id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org ALTER COLUMN id SET DEFAULT nextval('orgs_org_id_seq'::regclass);


--
-- Name: orgs_org_administrators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators ALTER COLUMN id SET DEFAULT nextval('orgs_org_administrators_id_seq'::regclass);


--
-- Name: orgs_org_editors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors ALTER COLUMN id SET DEFAULT nextval('orgs_org_editors_id_seq'::regclass);


--
-- Name: orgs_org_surveyors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_surveyors ALTER COLUMN id SET DEFAULT nextval('orgs_org_surveyors_id_seq'::regclass);


--
-- Name: orgs_org_viewers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers ALTER COLUMN id SET DEFAULT nextval('orgs_org_viewers_id_seq'::regclass);


--
-- Name: orgs_topup id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup ALTER COLUMN id SET DEFAULT nextval('orgs_topup_id_seq'::regclass);


--
-- Name: orgs_usersettings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_usersettings ALTER COLUMN id SET DEFAULT nextval('orgs_usersettings_id_seq'::regclass);


--
-- Name: public_lead id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead ALTER COLUMN id SET DEFAULT nextval('public_lead_id_seq'::regclass);


--
-- Name: public_video id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video ALTER COLUMN id SET DEFAULT nextval('public_video_id_seq'::regclass);


--
-- Name: reports_report id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report ALTER COLUMN id SET DEFAULT nextval('reports_report_id_seq'::regclass);


--
-- Name: schedules_schedule id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule ALTER COLUMN id SET DEFAULT nextval('schedules_schedule_id_seq'::regclass);


--
-- Name: triggers_trigger id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_id_seq'::regclass);


--
-- Name: triggers_trigger_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_contacts_id_seq'::regclass);


--
-- Name: triggers_trigger_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_groups_id_seq'::regclass);


--
-- Name: users_failedlogin id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_failedlogin ALTER COLUMN id SET DEFAULT nextval('users_failedlogin_id_seq'::regclass);


--
-- Name: users_passwordhistory id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_passwordhistory ALTER COLUMN id SET DEFAULT nextval('users_passwordhistory_id_seq'::regclass);


--
-- Name: users_recoverytoken id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_recoverytoken ALTER COLUMN id SET DEFAULT nextval('users_recoverytoken_id_seq'::regclass);


--
-- Name: values_value id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value ALTER COLUMN id SET DEFAULT nextval('values_value_id_seq'::regclass);


--
-- Name: airtime_airtimetransfer airtime_airtimetransfer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetransfer_pkey PRIMARY KEY (id);


--
-- Name: api_apitoken api_apitoken_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_pkey PRIMARY KEY (key);


--
-- Name: api_resthook api_resthook_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthook
    ADD CONSTRAINT api_resthook_pkey PRIMARY KEY (id);


--
-- Name: api_resthooksubscriber api_resthooksubscriber_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_pkey PRIMARY KEY (id);


--
-- Name: api_webhookevent api_webhookevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_pkey PRIMARY KEY (id);


--
-- Name: api_webhookresult api_webhookresult_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresult_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_user_id_94350c0c_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_94350c0c_uniq UNIQUE (user_id, group_id);


--
-- Name: auth_user auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_14a6b632_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_14a6b632_uniq UNIQUE (user_id, permission_id);


--
-- Name: auth_user auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: authtoken_token authtoken_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_pkey PRIMARY KEY (key);


--
-- Name: authtoken_token authtoken_token_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_key UNIQUE (user_id);


--
-- Name: campaigns_campaign campaigns_campaign_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaign campaigns_campaign_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_uuid_key UNIQUE (uuid);


--
-- Name: campaigns_campaignevent campaigns_campaignevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaignevent campaigns_campaignevent_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_uuid_key UNIQUE (uuid);


--
-- Name: campaigns_eventfire campaigns_eventfire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT campaigns_eventfire_pkey PRIMARY KEY (id);


--
-- Name: channels_alert channels_alert_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_pkey PRIMARY KEY (id);


--
-- Name: channels_channel channels_channel_claim_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_claim_code_key UNIQUE (claim_code);


--
-- Name: channels_channel channels_channel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_pkey PRIMARY KEY (id);


--
-- Name: channels_channel channels_channel_secret_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_secret_key UNIQUE (secret);


--
-- Name: channels_channel channels_channel_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_uuid_key UNIQUE (uuid);


--
-- Name: channels_channelcount channels_channelcount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelcount
    ADD CONSTRAINT channels_channelcount_pkey PRIMARY KEY (id);


--
-- Name: channels_channelevent channels_channelevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelevent
    ADD CONSTRAINT channels_channelevent_pkey PRIMARY KEY (id);


--
-- Name: channels_channellog channels_channellog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT channels_channellog_pkey PRIMARY KEY (id);


--
-- Name: channels_channelsession channels_channelsession_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession
    ADD CONSTRAINT channels_channelsession_pkey PRIMARY KEY (id);


--
-- Name: channels_syncevent channels_syncevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syncevent_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact contacts_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact contacts_contact_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contactfield contacts_contactfield_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_contacts contacts_contactgroup_contacts_contactgroup_id_0f909f73_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_contacts_contactgroup_id_0f909f73_uniq UNIQUE (contactgroup_id, contact_id);


--
-- Name: contacts_contactgroup_contacts contacts_contactgroup_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_contacts_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup contacts_contactgroup_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_query_fields contacts_contactgroup_query_field_contactgroup_id_642b9244_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_query_field_contactgroup_id_642b9244_uniq UNIQUE (contactgroup_id, contactfield_id);


--
-- Name: contacts_contactgroup_query_fields contacts_contactgroup_query_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_query_fields_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup contacts_contactgroup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contactgroupcount contacts_contactgroupcount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroupcount
    ADD CONSTRAINT contacts_contactgroupcount_pkey PRIMARY KEY (id);


--
-- Name: contacts_contacturn contacts_contacturn_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_pkey PRIMARY KEY (id);


--
-- Name: contacts_contacturn contacts_contacturn_urn_a86b9105_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_urn_a86b9105_uniq UNIQUE (identity, org_id);


--
-- Name: contacts_exportcontactstask contacts_exportcontactstask_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_pkey PRIMARY KEY (id);


--
-- Name: contacts_exportcontactstask contacts_exportcontactstask_uuid_aad904fe_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_uuid_aad904fe_uniq UNIQUE (uuid);


--
-- Name: csv_imports_importtask csv_imports_importtask_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_pkey PRIMARY KEY (id);


--
-- Name: django_content_type django_content_type_app_label_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_content_type
    ADD CONSTRAINT django_content_type_app_label_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: django_site django_site_domain_a2e37b91_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_site
    ADD CONSTRAINT django_site_domain_a2e37b91_uniq UNIQUE (domain);


--
-- Name: django_site django_site_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_site
    ADD CONSTRAINT django_site_pkey PRIMARY KEY (id);


--
-- Name: flows_actionlog flows_actionlog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionlog
    ADD CONSTRAINT flows_actionlog_pkey PRIMARY KEY (id);


--
-- Name: flows_actionset flows_actionset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_pkey PRIMARY KEY (id);


--
-- Name: flows_actionset flows_actionset_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_uuid_key UNIQUE (uuid);


--
-- Name: flows_exportflowresultstask_flows flows_exportflowresultst_exportflowresultstask_id_4e70a5c5_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultst_exportflowresultstask_id_4e70a5c5_uniq UNIQUE (exportflowresultstask_id, flow_id);


--
-- Name: flows_exportflowresultstask_flows flows_exportflowresultstask_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultstask_flows_pkey PRIMARY KEY (id);


--
-- Name: flows_exportflowresultstask flows_exportflowresultstask_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_pkey PRIMARY KEY (id);


--
-- Name: flows_exportflowresultstask flows_exportflowresultstask_uuid_ed7e2021_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_uuid_ed7e2021_uniq UNIQUE (uuid);


--
-- Name: flows_flow flows_flow_entry_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_entry_uuid_key UNIQUE (entry_uuid);


--
-- Name: flows_flow_labels flows_flow_labels_flow_id_99ec8abf_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flow_id_99ec8abf_uniq UNIQUE (flow_id, flowlabel_id);


--
-- Name: flows_flow_labels flows_flow_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_pkey PRIMARY KEY (id);


--
-- Name: flows_flow flows_flow_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_pkey PRIMARY KEY (id);


--
-- Name: flows_flow flows_flow_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_uuid_key UNIQUE (uuid);


--
-- Name: flows_flowlabel flows_flowlabel_name_00066d3a_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_name_00066d3a_uniq UNIQUE (name, parent_id, org_id);


--
-- Name: flows_flowlabel flows_flowlabel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_pkey PRIMARY KEY (id);


--
-- Name: flows_flowlabel flows_flowlabel_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_uuid_key UNIQUE (uuid);


--
-- Name: flows_flownodecount flows_flownodecount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flownodecount
    ADD CONSTRAINT flows_flownodecount_pkey PRIMARY KEY (id);


--
-- Name: flows_flowpathcount flows_flowpathcount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowpathcount
    ADD CONSTRAINT flows_flowpathcount_pkey PRIMARY KEY (id);


--
-- Name: flows_flowpathrecentmessage flows_flowpathrecentmessage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowpathrecentmessage
    ADD CONSTRAINT flows_flowpathrecentmessage_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrevision flows_flowrevision_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrun flows_flowrun_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrun flows_flowrun_uuid_524ab95b_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_uuid_524ab95b_uniq UNIQUE (uuid);


--
-- Name: flows_flowruncount flows_flowruncount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowruncount
    ADD CONSTRAINT flows_flowruncount_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_contacts flows_flowstart_contacts_flowstart_id_88b65412_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_flowstart_id_88b65412_uniq UNIQUE (flowstart_id, contact_id);


--
-- Name: flows_flowstart_contacts flows_flowstart_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_groups flows_flowstart_groups_flowstart_id_fc0b5f4f_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_flowstart_id_fc0b5f4f_uniq UNIQUE (flowstart_id, contactgroup_id);


--
-- Name: flows_flowstart_groups flows_flowstart_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart flows_flowstart_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart flows_flowstart_uuid_1f90b034_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_uuid_1f90b034_uniq UNIQUE (uuid);


--
-- Name: flows_flowstep_broadcasts flows_flowstep_broadcasts_flowstep_id_c9cb8603_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_broadcasts
    ADD CONSTRAINT flows_flowstep_broadcasts_flowstep_id_c9cb8603_uniq UNIQUE (flowstep_id, broadcast_id);


--
-- Name: flows_flowstep_broadcasts flows_flowstep_broadcasts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_broadcasts
    ADD CONSTRAINT flows_flowstep_broadcasts_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstep_messages flows_flowstep_messages_flowstep_id_3ce4a034_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_flowstep_id_3ce4a034_uniq UNIQUE (flowstep_id, msg_id);


--
-- Name: flows_flowstep_messages flows_flowstep_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstep flows_flowstep_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT flows_flowstep_pkey PRIMARY KEY (id);


--
-- Name: flows_ruleset flows_ruleset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_pkey PRIMARY KEY (id);


--
-- Name: flows_ruleset flows_ruleset_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_uuid_key UNIQUE (uuid);


--
-- Name: guardian_groupobjectpermission guardian_groupobjectpermission_group_id_3f189f7c_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobjectpermission_group_id_3f189f7c_uniq UNIQUE (group_id, permission_id, object_pk);


--
-- Name: guardian_groupobjectpermission guardian_groupobjectpermission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobjectpermission_pkey PRIMARY KEY (id);


--
-- Name: guardian_userobjectpermission guardian_userobjectpermission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjectpermission_pkey PRIMARY KEY (id);


--
-- Name: guardian_userobjectpermission guardian_userobjectpermission_user_id_b0b3d2fc_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjectpermission_user_id_b0b3d2fc_uniq UNIQUE (user_id, permission_id, object_pk);


--
-- Name: locations_adminboundary locations_adminboundary_osm_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_osm_id_key UNIQUE (osm_id);


--
-- Name: locations_adminboundary locations_adminboundary_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_pkey PRIMARY KEY (id);


--
-- Name: locations_boundaryalias locations_boundaryalias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_contacts msgs_broadcast_contacts_broadcast_id_85ec2380_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_broadcast_id_85ec2380_uniq UNIQUE (broadcast_id, contact_id);


--
-- Name: msgs_broadcast_contacts msgs_broadcast_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_groups msgs_broadcast_groups_broadcast_id_bc725cf0_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_broadcast_id_bc725cf0_uniq UNIQUE (broadcast_id, contactgroup_id);


--
-- Name: msgs_broadcast_groups msgs_broadcast_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast msgs_broadcast_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_recipients msgs_broadcast_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_recipients
    ADD CONSTRAINT msgs_broadcast_recipients_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast msgs_broadcast_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_schedule_id_key UNIQUE (schedule_id);


--
-- Name: msgs_broadcast_urns msgs_broadcast_urns_broadcast_id_5fe7764f_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_broadcast_id_5fe7764f_uniq UNIQUE (broadcast_id, contacturn_id);


--
-- Name: msgs_broadcast_urns msgs_broadcast_urns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask_groups msgs_exportmessagestask_gro_exportmessagestask_id_d2d2009a_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagestask_gro_exportmessagestask_id_d2d2009a_uniq UNIQUE (exportmessagestask_id, contactgroup_id);


--
-- Name: msgs_exportmessagestask_groups msgs_exportmessagestask_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagestask_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_uuid_a9d02f48_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_uuid_a9d02f48_uniq UNIQUE (uuid);


--
-- Name: msgs_label msgs_label_org_id_e4186cef_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_org_id_e4186cef_uniq UNIQUE (org_id, name);


--
-- Name: msgs_label msgs_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_pkey PRIMARY KEY (id);


--
-- Name: msgs_label msgs_label_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_uuid_key UNIQUE (uuid);


--
-- Name: msgs_labelcount msgs_labelcount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_labelcount
    ADD CONSTRAINT msgs_labelcount_pkey PRIMARY KEY (id);


--
-- Name: msgs_msg_labels msgs_msg_labels_msg_id_98060205_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_msg_id_98060205_uniq UNIQUE (msg_id, label_id);


--
-- Name: msgs_msg_labels msgs_msg_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_pkey PRIMARY KEY (id);


--
-- Name: msgs_msg msgs_msg_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_pkey PRIMARY KEY (id);


--
-- Name: msgs_systemlabelcount msgs_systemlabel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_systemlabelcount
    ADD CONSTRAINT msgs_systemlabel_pkey PRIMARY KEY (id);


--
-- Name: orgs_creditalert orgs_creditalert_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_pkey PRIMARY KEY (id);


--
-- Name: orgs_debit orgs_debit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_debit
    ADD CONSTRAINT orgs_debit_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation orgs_invitation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation orgs_invitation_secret_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_secret_key UNIQUE (secret);


--
-- Name: orgs_language orgs_language_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_administrators orgs_org_administrators_org_id_c6cb5bee_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_org_id_c6cb5bee_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_administrators orgs_org_administrators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_editors orgs_org_editors_org_id_635dc129_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_org_id_635dc129_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_editors orgs_org_editors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_pkey PRIMARY KEY (id);


--
-- Name: orgs_org orgs_org_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_pkey PRIMARY KEY (id);


--
-- Name: orgs_org orgs_org_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_slug_key UNIQUE (slug);


--
-- Name: orgs_org_surveyors orgs_org_surveyors_org_id_f78ff12f_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_org_id_f78ff12f_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_surveyors orgs_org_surveyors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_viewers orgs_org_viewers_org_id_451e0d91_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_org_id_451e0d91_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_viewers orgs_org_viewers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_pkey PRIMARY KEY (id);


--
-- Name: orgs_topup orgs_topup_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_pkey PRIMARY KEY (id);


--
-- Name: orgs_topupcredits orgs_topupcredits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topupcredits
    ADD CONSTRAINT orgs_topupcredits_pkey PRIMARY KEY (id);


--
-- Name: orgs_usersettings orgs_usersettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_pkey PRIMARY KEY (id);


--
-- Name: public_lead public_lead_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT public_lead_pkey PRIMARY KEY (id);


--
-- Name: public_video public_video_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT public_video_pkey PRIMARY KEY (id);


--
-- Name: reports_report reports_report_org_id_d8b6ac42_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_org_id_d8b6ac42_uniq UNIQUE (org_id, title);


--
-- Name: reports_report reports_report_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_pkey PRIMARY KEY (id);


--
-- Name: schedules_schedule schedules_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT schedules_schedule_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_contacts triggers_trigger_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_contacts triggers_trigger_contacts_trigger_id_a5309237_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_trigger_id_a5309237_uniq UNIQUE (trigger_id, contact_id);


--
-- Name: triggers_trigger_groups triggers_trigger_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_groups triggers_trigger_groups_trigger_id_cf0ee28d_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_trigger_id_cf0ee28d_uniq UNIQUE (trigger_id, contactgroup_id);


--
-- Name: triggers_trigger triggers_trigger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger triggers_trigger_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_schedule_id_key UNIQUE (schedule_id);


--
-- Name: users_failedlogin users_failedlogin_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_failedlogin
    ADD CONSTRAINT users_failedlogin_pkey PRIMARY KEY (id);


--
-- Name: users_passwordhistory users_passwordhistory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_passwordhistory
    ADD CONSTRAINT users_passwordhistory_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken users_recoverytoken_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken users_recoverytoken_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_token_key UNIQUE (token);


--
-- Name: values_value values_value_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_pkey PRIMARY KEY (id);


--
-- Name: airtime_airtimetransfer_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX airtime_airtimetransfer_6d82f13d ON airtime_airtimetransfer USING btree (contact_id);


--
-- Name: airtime_airtimetransfer_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX airtime_airtimetransfer_72eb6c85 ON airtime_airtimetransfer USING btree (channel_id);


--
-- Name: airtime_airtimetransfer_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX airtime_airtimetransfer_9cf869aa ON airtime_airtimetransfer USING btree (org_id);


--
-- Name: airtime_airtimetransfer_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX airtime_airtimetransfer_b3da0983 ON airtime_airtimetransfer USING btree (modified_by_id);


--
-- Name: airtime_airtimetransfer_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX airtime_airtimetransfer_e93cb7eb ON airtime_airtimetransfer USING btree (created_by_id);


--
-- Name: api_apitoken_84566833; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_apitoken_84566833 ON api_apitoken USING btree (role_id);


--
-- Name: api_apitoken_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_apitoken_9cf869aa ON api_apitoken USING btree (org_id);


--
-- Name: api_apitoken_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_apitoken_e8701ad4 ON api_apitoken USING btree (user_id);


--
-- Name: api_apitoken_key_e6fcf24a_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_apitoken_key_e6fcf24a_like ON api_apitoken USING btree (key varchar_pattern_ops);


--
-- Name: api_resthook_2dbcba41; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthook_2dbcba41 ON api_resthook USING btree (slug);


--
-- Name: api_resthook_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthook_9cf869aa ON api_resthook USING btree (org_id);


--
-- Name: api_resthook_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthook_b3da0983 ON api_resthook USING btree (modified_by_id);


--
-- Name: api_resthook_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthook_e93cb7eb ON api_resthook USING btree (created_by_id);


--
-- Name: api_resthook_slug_19d1d7bf_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthook_slug_19d1d7bf_like ON api_resthook USING btree (slug varchar_pattern_ops);


--
-- Name: api_resthooksubscriber_1bce5203; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthooksubscriber_1bce5203 ON api_resthooksubscriber USING btree (resthook_id);


--
-- Name: api_resthooksubscriber_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthooksubscriber_b3da0983 ON api_resthooksubscriber USING btree (modified_by_id);


--
-- Name: api_resthooksubscriber_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resthooksubscriber_e93cb7eb ON api_resthooksubscriber USING btree (created_by_id);


--
-- Name: api_webhookevent_0acf093b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookevent_0acf093b ON api_webhookevent USING btree (run_id);


--
-- Name: api_webhookevent_1bce5203; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookevent_1bce5203 ON api_webhookevent USING btree (resthook_id);


--
-- Name: api_webhookevent_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookevent_72eb6c85 ON api_webhookevent USING btree (channel_id);


--
-- Name: api_webhookevent_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookevent_9cf869aa ON api_webhookevent USING btree (org_id);


--
-- Name: api_webhookevent_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookevent_b3da0983 ON api_webhookevent USING btree (modified_by_id);


--
-- Name: api_webhookevent_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookevent_e93cb7eb ON api_webhookevent USING btree (created_by_id);


--
-- Name: api_webhookresult_4437cfac; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookresult_4437cfac ON api_webhookresult USING btree (event_id);


--
-- Name: api_webhookresult_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookresult_b3da0983 ON api_webhookresult USING btree (modified_by_id);


--
-- Name: api_webhookresult_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_webhookresult_e93cb7eb ON api_webhookresult USING btree (created_by_id);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_name_a6ea08ec_like ON auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_0e939a4f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_0e939a4f ON auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_8373b171; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_8373b171 ON auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_417f1b1c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_permission_417f1b1c ON auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_0e939a4f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_groups_0e939a4f ON auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_groups_e8701ad4 ON auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_8373b171; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_user_permissions_8373b171 ON auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_user_permissions_e8701ad4 ON auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_6821ab7c_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_username_6821ab7c_like ON auth_user USING btree (username varchar_pattern_ops);


--
-- Name: authtoken_token_key_10f0b77e_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX authtoken_token_key_10f0b77e_like ON authtoken_token USING btree (key varchar_pattern_ops);


--
-- Name: campaigns_campaign_0e939a4f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaign_0e939a4f ON campaigns_campaign USING btree (group_id);


--
-- Name: campaigns_campaign_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaign_9cf869aa ON campaigns_campaign USING btree (org_id);


--
-- Name: campaigns_campaign_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaign_b3da0983 ON campaigns_campaign USING btree (modified_by_id);


--
-- Name: campaigns_campaign_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaign_e93cb7eb ON campaigns_campaign USING btree (created_by_id);


--
-- Name: campaigns_campaign_uuid_ff86cf7f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaign_uuid_ff86cf7f_like ON campaigns_campaign USING btree (uuid varchar_pattern_ops);


--
-- Name: campaigns_campaignevent_61d66954; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaignevent_61d66954 ON campaigns_campaignevent USING btree (relative_to_id);


--
-- Name: campaigns_campaignevent_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaignevent_7f26ac5b ON campaigns_campaignevent USING btree (flow_id);


--
-- Name: campaigns_campaignevent_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaignevent_b3da0983 ON campaigns_campaignevent USING btree (modified_by_id);


--
-- Name: campaigns_campaignevent_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaignevent_e93cb7eb ON campaigns_campaignevent USING btree (created_by_id);


--
-- Name: campaigns_campaignevent_f14acec3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaignevent_f14acec3 ON campaigns_campaignevent USING btree (campaign_id);


--
-- Name: campaigns_campaignevent_uuid_6f074205_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_campaignevent_uuid_6f074205_like ON campaigns_campaignevent USING btree (uuid varchar_pattern_ops);


--
-- Name: campaigns_eventfire_4437cfac; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_eventfire_4437cfac ON campaigns_eventfire USING btree (event_id);


--
-- Name: campaigns_eventfire_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX campaigns_eventfire_6d82f13d ON campaigns_eventfire USING btree (contact_id);


--
-- Name: channels_alert_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_alert_72eb6c85 ON channels_alert USING btree (channel_id);


--
-- Name: channels_alert_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_alert_b3da0983 ON channels_alert USING btree (modified_by_id);


--
-- Name: channels_alert_c8730bec; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_alert_c8730bec ON channels_alert USING btree (sync_event_id);


--
-- Name: channels_alert_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_alert_e93cb7eb ON channels_alert USING btree (created_by_id);


--
-- Name: channels_channel_6be37982; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channel_6be37982 ON channels_channel USING btree (parent_id);


--
-- Name: channels_channel_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channel_9cf869aa ON channels_channel USING btree (org_id);


--
-- Name: channels_channel_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channel_b3da0983 ON channels_channel USING btree (modified_by_id);


--
-- Name: channels_channel_claim_code_13b82678_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channel_claim_code_13b82678_like ON channels_channel USING btree (claim_code varchar_pattern_ops);


--
-- Name: channels_channel_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channel_e93cb7eb ON channels_channel USING btree (created_by_id);


--
-- Name: channels_channel_secret_7f9a562d_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channel_secret_7f9a562d_like ON channels_channel USING btree (secret varchar_pattern_ops);


--
-- Name: channels_channel_uuid_6008b898_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channel_uuid_6008b898_like ON channels_channel USING btree (uuid varchar_pattern_ops);


--
-- Name: channels_channelcount_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelcount_72eb6c85 ON channels_channelcount USING btree (channel_id);


--
-- Name: channels_channelcount_channel_id_361bd585_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelcount_channel_id_361bd585_idx ON channels_channelcount USING btree (channel_id, count_type, day);


--
-- Name: channels_channelcount_unsquashed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelcount_unsquashed ON channels_channelcount USING btree (channel_id, count_type, day) WHERE (NOT is_squashed);


--
-- Name: channels_channelevent_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelevent_6d82f13d ON channels_channelevent USING btree (contact_id);


--
-- Name: channels_channelevent_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelevent_72eb6c85 ON channels_channelevent USING btree (channel_id);


--
-- Name: channels_channelevent_842dde28; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelevent_842dde28 ON channels_channelevent USING btree (contact_urn_id);


--
-- Name: channels_channelevent_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelevent_9cf869aa ON channels_channelevent USING btree (org_id);


--
-- Name: channels_channelevent_api_view; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelevent_api_view ON channels_channelevent USING btree (org_id, created_on DESC, id DESC) WHERE (is_active = true);


--
-- Name: channels_channelevent_calls_view; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelevent_calls_view ON channels_channelevent USING btree (org_id, "time" DESC) WHERE ((is_active = true) AND ((event_type)::text = ANY ((ARRAY['mt_call'::character varying, 'mt_miss'::character varying, 'mo_call'::character varying, 'mo_miss'::character varying])::text[])));


--
-- Name: channels_channellog_0cc31d7b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channellog_0cc31d7b ON channels_channellog USING btree (msg_id);


--
-- Name: channels_channellog_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channellog_72eb6c85 ON channels_channellog USING btree (channel_id);


--
-- Name: channels_channellog_7fc8ef54; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channellog_7fc8ef54 ON channels_channellog USING btree (session_id);


--
-- Name: channels_channellog_channel_created_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channellog_channel_created_on ON channels_channellog USING btree (channel_id, created_on DESC);


--
-- Name: channels_channelsession_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelsession_6d82f13d ON channels_channelsession USING btree (contact_id);


--
-- Name: channels_channelsession_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelsession_72eb6c85 ON channels_channelsession USING btree (channel_id);


--
-- Name: channels_channelsession_842dde28; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelsession_842dde28 ON channels_channelsession USING btree (contact_urn_id);


--
-- Name: channels_channelsession_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelsession_9cf869aa ON channels_channelsession USING btree (org_id);


--
-- Name: channels_channelsession_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelsession_b3da0983 ON channels_channelsession USING btree (modified_by_id);


--
-- Name: channels_channelsession_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_channelsession_e93cb7eb ON channels_channelsession USING btree (created_by_id);


--
-- Name: channels_syncevent_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_syncevent_72eb6c85 ON channels_syncevent USING btree (channel_id);


--
-- Name: channels_syncevent_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_syncevent_b3da0983 ON channels_syncevent USING btree (modified_by_id);


--
-- Name: channels_syncevent_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_syncevent_e93cb7eb ON channels_syncevent USING btree (created_by_id);


--
-- Name: contacts_contact_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contact_9cf869aa ON contacts_contact USING btree (org_id);


--
-- Name: contacts_contact_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contact_b3da0983 ON contacts_contact USING btree (modified_by_id);


--
-- Name: contacts_contact_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contact_e93cb7eb ON contacts_contact USING btree (created_by_id);


--
-- Name: contacts_contact_org_modified_id_where_nontest_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contact_org_modified_id_where_nontest_active ON contacts_contact USING btree (org_id, modified_on DESC, id DESC) WHERE ((is_test = false) AND (is_active = true));


--
-- Name: contacts_contact_org_modified_id_where_nontest_inactive; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contact_org_modified_id_where_nontest_inactive ON contacts_contact USING btree (org_id, modified_on DESC, id DESC) WHERE ((is_test = false) AND (is_active = false));


--
-- Name: contacts_contact_uuid_66fe2f01_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contact_uuid_66fe2f01_like ON contacts_contact USING btree (uuid varchar_pattern_ops);


--
-- Name: contacts_contactfield_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactfield_9cf869aa ON contacts_contactfield USING btree (org_id);


--
-- Name: contacts_contactfield_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactfield_b3da0983 ON contacts_contactfield USING btree (modified_by_id);


--
-- Name: contacts_contactfield_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactfield_e93cb7eb ON contacts_contactfield USING btree (created_by_id);


--
-- Name: contacts_contactgroup_905540a6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_905540a6 ON contacts_contactgroup USING btree (import_task_id);


--
-- Name: contacts_contactgroup_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_9cf869aa ON contacts_contactgroup USING btree (org_id);


--
-- Name: contacts_contactgroup_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_b3da0983 ON contacts_contactgroup USING btree (modified_by_id);


--
-- Name: contacts_contactgroup_contacts_0b1b2ae4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_contacts_0b1b2ae4 ON contacts_contactgroup_contacts USING btree (contactgroup_id);


--
-- Name: contacts_contactgroup_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_contacts_6d82f13d ON contacts_contactgroup_contacts USING btree (contact_id);


--
-- Name: contacts_contactgroup_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_e93cb7eb ON contacts_contactgroup USING btree (created_by_id);


--
-- Name: contacts_contactgroup_query_fields_0b1b2ae4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_query_fields_0b1b2ae4 ON contacts_contactgroup_query_fields USING btree (contactgroup_id);


--
-- Name: contacts_contactgroup_query_fields_0d0cd403; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_query_fields_0d0cd403 ON contacts_contactgroup_query_fields USING btree (contactfield_id);


--
-- Name: contacts_contactgroup_uuid_377d4c62_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroup_uuid_377d4c62_like ON contacts_contactgroup USING btree (uuid varchar_pattern_ops);


--
-- Name: contacts_contactgroupcount_0e939a4f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroupcount_0e939a4f ON contacts_contactgroupcount USING btree (group_id);


--
-- Name: contacts_contactgroupcount_unsquashed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contactgroupcount_unsquashed ON contacts_contactgroupcount USING btree (group_id) WHERE (NOT is_squashed);


--
-- Name: contacts_contacturn_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contacturn_6d82f13d ON contacts_contacturn USING btree (contact_id);


--
-- Name: contacts_contacturn_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contacturn_72eb6c85 ON contacts_contacturn USING btree (channel_id);


--
-- Name: contacts_contacturn_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_contacturn_9cf869aa ON contacts_contacturn USING btree (org_id);


--
-- Name: contacts_exportcontactstask_0e939a4f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_exportcontactstask_0e939a4f ON contacts_exportcontactstask USING btree (group_id);


--
-- Name: contacts_exportcontactstask_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_exportcontactstask_9cf869aa ON contacts_exportcontactstask USING btree (org_id);


--
-- Name: contacts_exportcontactstask_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_exportcontactstask_b3da0983 ON contacts_exportcontactstask USING btree (modified_by_id);


--
-- Name: contacts_exportcontactstask_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_exportcontactstask_e93cb7eb ON contacts_exportcontactstask USING btree (created_by_id);


--
-- Name: contacts_exportcontactstask_uuid_aad904fe_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_exportcontactstask_uuid_aad904fe_like ON contacts_exportcontactstask USING btree (uuid varchar_pattern_ops);


--
-- Name: csv_imports_importtask_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX csv_imports_importtask_b3da0983 ON csv_imports_importtask USING btree (modified_by_id);


--
-- Name: csv_imports_importtask_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX csv_imports_importtask_e93cb7eb ON csv_imports_importtask USING btree (created_by_id);


--
-- Name: django_session_de54fa62; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_de54fa62 ON django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: django_site_domain_a2e37b91_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_site_domain_a2e37b91_like ON django_site USING btree (domain varchar_pattern_ops);


--
-- Name: flows_actionlog_0acf093b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_actionlog_0acf093b ON flows_actionlog USING btree (run_id);


--
-- Name: flows_actionset_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_actionset_7f26ac5b ON flows_actionset USING btree (flow_id);


--
-- Name: flows_actionset_uuid_a7003ccb_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_actionset_uuid_a7003ccb_like ON flows_actionset USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_exportflowresultstask_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_exportflowresultstask_9cf869aa ON flows_exportflowresultstask USING btree (org_id);


--
-- Name: flows_exportflowresultstask_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_exportflowresultstask_b3da0983 ON flows_exportflowresultstask USING btree (modified_by_id);


--
-- Name: flows_exportflowresultstask_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_exportflowresultstask_e93cb7eb ON flows_exportflowresultstask USING btree (created_by_id);


--
-- Name: flows_exportflowresultstask_flows_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_exportflowresultstask_flows_7f26ac5b ON flows_exportflowresultstask_flows USING btree (flow_id);


--
-- Name: flows_exportflowresultstask_flows_b21ac655; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_exportflowresultstask_flows_b21ac655 ON flows_exportflowresultstask_flows USING btree (exportflowresultstask_id);


--
-- Name: flows_exportflowresultstask_uuid_ed7e2021_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_exportflowresultstask_uuid_ed7e2021_like ON flows_exportflowresultstask USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_flow_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_9cf869aa ON flows_flow USING btree (org_id);


--
-- Name: flows_flow_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_b3da0983 ON flows_flow USING btree (modified_by_id);


--
-- Name: flows_flow_bc7c970b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_bc7c970b ON flows_flow USING btree (saved_by_id);


--
-- Name: flows_flow_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_e93cb7eb ON flows_flow USING btree (created_by_id);


--
-- Name: flows_flow_entry_uuid_e14448bc_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_entry_uuid_e14448bc_like ON flows_flow USING btree (entry_uuid varchar_pattern_ops);


--
-- Name: flows_flow_labels_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_labels_7f26ac5b ON flows_flow_labels USING btree (flow_id);


--
-- Name: flows_flow_labels_da1e9929; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_labels_da1e9929 ON flows_flow_labels USING btree (flowlabel_id);


--
-- Name: flows_flow_uuid_a2114745_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flow_uuid_a2114745_like ON flows_flow USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_flowlabel_6be37982; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowlabel_6be37982 ON flows_flowlabel USING btree (parent_id);


--
-- Name: flows_flowlabel_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowlabel_9cf869aa ON flows_flowlabel USING btree (org_id);


--
-- Name: flows_flowlabel_uuid_133646e5_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowlabel_uuid_133646e5_like ON flows_flowlabel USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_flownodecount_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flownodecount_7f26ac5b ON flows_flownodecount USING btree (flow_id);


--
-- Name: flows_flownodecount_b0074f9e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flownodecount_b0074f9e ON flows_flownodecount USING btree (node_uuid);


--
-- Name: flows_flowpathcount_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowpathcount_7f26ac5b ON flows_flowpathcount USING btree (flow_id);


--
-- Name: flows_flowpathcount_flow_id_c2f02792_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowpathcount_flow_id_c2f02792_idx ON flows_flowpathcount USING btree (flow_id, from_uuid, to_uuid, period);


--
-- Name: flows_flowpathcount_unsquashed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowpathcount_unsquashed ON flows_flowpathcount USING btree (flow_id, from_uuid, to_uuid, period) WHERE (NOT is_squashed);


--
-- Name: flows_flowpathrecentmessage_run_id_63c0cb82; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowpathrecentmessage_run_id_63c0cb82 ON flows_flowpathrecentmessage USING btree (run_id);


--
-- Name: flows_flowrevision_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrevision_7f26ac5b ON flows_flowrevision USING btree (flow_id);


--
-- Name: flows_flowrevision_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrevision_b3da0983 ON flows_flowrevision USING btree (modified_by_id);


--
-- Name: flows_flowrevision_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrevision_e93cb7eb ON flows_flowrevision USING btree (created_by_id);


--
-- Name: flows_flowrun_31174c9a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_31174c9a ON flows_flowrun USING btree (submitted_by_id);


--
-- Name: flows_flowrun_324ac644; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_324ac644 ON flows_flowrun USING btree (start_id);


--
-- Name: flows_flowrun_6be37982; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_6be37982 ON flows_flowrun USING btree (parent_id);


--
-- Name: flows_flowrun_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_6d82f13d ON flows_flowrun USING btree (contact_id);


--
-- Name: flows_flowrun_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_7f26ac5b ON flows_flowrun USING btree (flow_id);


--
-- Name: flows_flowrun_7fc8ef54; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_7fc8ef54 ON flows_flowrun USING btree (session_id);


--
-- Name: flows_flowrun_expires_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_expires_on ON flows_flowrun USING btree (expires_on) WHERE (is_active = true);


--
-- Name: flows_flowrun_flow_modified_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_flow_modified_id ON flows_flowrun USING btree (flow_id, modified_on DESC, id DESC);


--
-- Name: flows_flowrun_flow_modified_id_where_responded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_flow_modified_id_where_responded ON flows_flowrun USING btree (flow_id, modified_on DESC, id DESC) WHERE (responded = true);


--
-- Name: flows_flowrun_null_expired_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_null_expired_on ON flows_flowrun USING btree (exited_on) WHERE (exited_on IS NULL);


--
-- Name: flows_flowrun_org_modified_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_org_modified_id ON flows_flowrun USING btree (org_id, modified_on DESC, id DESC);


--
-- Name: flows_flowrun_org_modified_id_where_responded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_org_modified_id_where_responded ON flows_flowrun USING btree (org_id, modified_on DESC, id DESC) WHERE (responded = true);


--
-- Name: flows_flowrun_parent_created_on_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_parent_created_on_not_null ON flows_flowrun USING btree (parent_id, created_on DESC) WHERE (parent_id IS NOT NULL);


--
-- Name: flows_flowrun_timeout_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowrun_timeout_active ON flows_flowrun USING btree (timeout_on) WHERE ((is_active = true) AND (timeout_on IS NOT NULL));


--
-- Name: flows_flowruncount_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowruncount_7f26ac5b ON flows_flowruncount USING btree (flow_id);


--
-- Name: flows_flowruncount_flow_id_eef1051f_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowruncount_flow_id_eef1051f_idx ON flows_flowruncount USING btree (flow_id, exit_type);


--
-- Name: flows_flowruncount_unsquashed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowruncount_unsquashed ON flows_flowruncount USING btree (flow_id, exit_type) WHERE (NOT is_squashed);


--
-- Name: flows_flowstart_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstart_7f26ac5b ON flows_flowstart USING btree (flow_id);


--
-- Name: flows_flowstart_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstart_b3da0983 ON flows_flowstart USING btree (modified_by_id);


--
-- Name: flows_flowstart_contacts_3f45c555; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstart_contacts_3f45c555 ON flows_flowstart_contacts USING btree (flowstart_id);


--
-- Name: flows_flowstart_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstart_contacts_6d82f13d ON flows_flowstart_contacts USING btree (contact_id);


--
-- Name: flows_flowstart_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstart_e93cb7eb ON flows_flowstart USING btree (created_by_id);


--
-- Name: flows_flowstart_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstart_groups_0b1b2ae4 ON flows_flowstart_groups USING btree (contactgroup_id);


--
-- Name: flows_flowstart_groups_3f45c555; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstart_groups_3f45c555 ON flows_flowstart_groups USING btree (flowstart_id);


--
-- Name: flows_flowstep_017416d4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_017416d4 ON flows_flowstep USING btree (step_uuid);


--
-- Name: flows_flowstep_0acf093b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_0acf093b ON flows_flowstep USING btree (run_id);


--
-- Name: flows_flowstep_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_6d82f13d ON flows_flowstep USING btree (contact_id);


--
-- Name: flows_flowstep_a8b6e9f0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_a8b6e9f0 ON flows_flowstep USING btree (left_on);


--
-- Name: flows_flowstep_broadcasts_b0cb7d59; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_broadcasts_b0cb7d59 ON flows_flowstep_broadcasts USING btree (broadcast_id);


--
-- Name: flows_flowstep_broadcasts_c01a422b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_broadcasts_c01a422b ON flows_flowstep_broadcasts USING btree (flowstep_id);


--
-- Name: flows_flowstep_messages_0cc31d7b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_messages_0cc31d7b ON flows_flowstep_messages USING btree (msg_id);


--
-- Name: flows_flowstep_messages_c01a422b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_messages_c01a422b ON flows_flowstep_messages USING btree (flowstep_id);


--
-- Name: flows_flowstep_step_uuid_5b365bbf_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_flowstep_step_uuid_5b365bbf_like ON flows_flowstep USING btree (step_uuid varchar_pattern_ops);


--
-- Name: flows_ruleset_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_ruleset_7f26ac5b ON flows_ruleset USING btree (flow_id);


--
-- Name: flows_ruleset_uuid_c303fd70_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_ruleset_uuid_c303fd70_like ON flows_ruleset USING btree (uuid varchar_pattern_ops);


--
-- Name: guardian_groupobjectpermission_0e939a4f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX guardian_groupobjectpermission_0e939a4f ON guardian_groupobjectpermission USING btree (group_id);


--
-- Name: guardian_groupobjectpermission_417f1b1c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX guardian_groupobjectpermission_417f1b1c ON guardian_groupobjectpermission USING btree (content_type_id);


--
-- Name: guardian_groupobjectpermission_8373b171; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX guardian_groupobjectpermission_8373b171 ON guardian_groupobjectpermission USING btree (permission_id);


--
-- Name: guardian_userobjectpermission_417f1b1c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX guardian_userobjectpermission_417f1b1c ON guardian_userobjectpermission USING btree (content_type_id);


--
-- Name: guardian_userobjectpermission_8373b171; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX guardian_userobjectpermission_8373b171 ON guardian_userobjectpermission USING btree (permission_id);


--
-- Name: guardian_userobjectpermission_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX guardian_userobjectpermission_e8701ad4 ON guardian_userobjectpermission USING btree (user_id);


--
-- Name: locations_adminboundary_3cfbd988; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_3cfbd988 ON locations_adminboundary USING btree (rght);


--
-- Name: locations_adminboundary_656442a0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_656442a0 ON locations_adminboundary USING btree (tree_id);


--
-- Name: locations_adminboundary_6be37982; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_6be37982 ON locations_adminboundary USING btree (parent_id);


--
-- Name: locations_adminboundary_caf7cc51; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_caf7cc51 ON locations_adminboundary USING btree (lft);


--
-- Name: locations_adminboundary_geometry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_geometry_id ON locations_adminboundary USING gist (geometry);


--
-- Name: locations_adminboundary_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_name ON locations_adminboundary USING btree (upper((name)::text));


--
-- Name: locations_adminboundary_osm_id_ada345c4_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_osm_id_ada345c4_like ON locations_adminboundary USING btree (osm_id varchar_pattern_ops);


--
-- Name: locations_adminboundary_simplified_geometry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_adminboundary_simplified_geometry_id ON locations_adminboundary USING gist (simplified_geometry);


--
-- Name: locations_boundaryalias_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_boundaryalias_9cf869aa ON locations_boundaryalias USING btree (org_id);


--
-- Name: locations_boundaryalias_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_boundaryalias_b3da0983 ON locations_boundaryalias USING btree (modified_by_id);


--
-- Name: locations_boundaryalias_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_boundaryalias_e93cb7eb ON locations_boundaryalias USING btree (created_by_id);


--
-- Name: locations_boundaryalias_eb01ad15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_boundaryalias_eb01ad15 ON locations_boundaryalias USING btree (boundary_id);


--
-- Name: locations_boundaryalias_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_boundaryalias_name ON locations_boundaryalias USING btree (upper((name)::text));


--
-- Name: msgs_broadcast_6be37982; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_6be37982 ON msgs_broadcast USING btree (parent_id);


--
-- Name: msgs_broadcast_6d10fce5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_6d10fce5 ON msgs_broadcast USING btree (created_on);


--
-- Name: msgs_broadcast_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_72eb6c85 ON msgs_broadcast USING btree (channel_id);


--
-- Name: msgs_broadcast_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_9cf869aa ON msgs_broadcast USING btree (org_id);


--
-- Name: msgs_broadcast_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_b3da0983 ON msgs_broadcast USING btree (modified_by_id);


--
-- Name: msgs_broadcast_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_contacts_6d82f13d ON msgs_broadcast_contacts USING btree (contact_id);


--
-- Name: msgs_broadcast_contacts_b0cb7d59; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_contacts_b0cb7d59 ON msgs_broadcast_contacts USING btree (broadcast_id);


--
-- Name: msgs_broadcast_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_e93cb7eb ON msgs_broadcast USING btree (created_by_id);


--
-- Name: msgs_broadcast_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_groups_0b1b2ae4 ON msgs_broadcast_groups USING btree (contactgroup_id);


--
-- Name: msgs_broadcast_groups_b0cb7d59; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_groups_b0cb7d59 ON msgs_broadcast_groups USING btree (broadcast_id);


--
-- Name: msgs_broadcast_recipients_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_recipients_6d82f13d ON msgs_broadcast_recipients USING btree (contact_id);


--
-- Name: msgs_broadcast_recipients_b0cb7d59; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_recipients_b0cb7d59 ON msgs_broadcast_recipients USING btree (broadcast_id);


--
-- Name: msgs_broadcast_urns_5a8e6a7d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_urns_5a8e6a7d ON msgs_broadcast_urns USING btree (contacturn_id);


--
-- Name: msgs_broadcast_urns_b0cb7d59; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcast_urns_b0cb7d59 ON msgs_broadcast_urns USING btree (broadcast_id);


--
-- Name: msgs_broadcasts_org_created_id_where_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_broadcasts_org_created_id_where_active ON msgs_broadcast USING btree (org_id, created_on DESC, id DESC) WHERE (is_active = true);


--
-- Name: msgs_exportmessagestask_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_exportmessagestask_9cf869aa ON msgs_exportmessagestask USING btree (org_id);


--
-- Name: msgs_exportmessagestask_abec2aca; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_exportmessagestask_abec2aca ON msgs_exportmessagestask USING btree (label_id);


--
-- Name: msgs_exportmessagestask_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_exportmessagestask_b3da0983 ON msgs_exportmessagestask USING btree (modified_by_id);


--
-- Name: msgs_exportmessagestask_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_exportmessagestask_e93cb7eb ON msgs_exportmessagestask USING btree (created_by_id);


--
-- Name: msgs_exportmessagestask_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_exportmessagestask_groups_0b1b2ae4 ON msgs_exportmessagestask_groups USING btree (contactgroup_id);


--
-- Name: msgs_exportmessagestask_groups_9ad8bdea; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_exportmessagestask_groups_9ad8bdea ON msgs_exportmessagestask_groups USING btree (exportmessagestask_id);


--
-- Name: msgs_exportmessagestask_uuid_a9d02f48_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_exportmessagestask_uuid_a9d02f48_like ON msgs_exportmessagestask USING btree (uuid varchar_pattern_ops);


--
-- Name: msgs_label_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_label_9cf869aa ON msgs_label USING btree (org_id);


--
-- Name: msgs_label_a8a44dbb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_label_a8a44dbb ON msgs_label USING btree (folder_id);


--
-- Name: msgs_label_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_label_b3da0983 ON msgs_label USING btree (modified_by_id);


--
-- Name: msgs_label_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_label_e93cb7eb ON msgs_label USING btree (created_by_id);


--
-- Name: msgs_label_uuid_d9a956c8_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_label_uuid_d9a956c8_like ON msgs_label USING btree (uuid varchar_pattern_ops);


--
-- Name: msgs_labelcount_abec2aca; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_labelcount_abec2aca ON msgs_labelcount USING btree (label_id);


--
-- Name: msgs_msg_6d10fce5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_6d10fce5 ON msgs_msg USING btree (created_on);


--
-- Name: msgs_msg_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_6d82f13d ON msgs_msg USING btree (contact_id);


--
-- Name: msgs_msg_72eb6c85; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_72eb6c85 ON msgs_msg USING btree (channel_id);


--
-- Name: msgs_msg_7fc8ef54; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_7fc8ef54 ON msgs_msg USING btree (session_id);


--
-- Name: msgs_msg_842dde28; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_842dde28 ON msgs_msg USING btree (contact_urn_id);


--
-- Name: msgs_msg_9acb4454; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_9acb4454 ON msgs_msg USING btree (status);


--
-- Name: msgs_msg_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_9cf869aa ON msgs_msg USING btree (org_id);


--
-- Name: msgs_msg_a5d9fd84; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_a5d9fd84 ON msgs_msg USING btree (topup_id);


--
-- Name: msgs_msg_b0cb7d59; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_b0cb7d59 ON msgs_msg USING btree (broadcast_id);


--
-- Name: msgs_msg_external_id_where_nonnull; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_external_id_where_nonnull ON msgs_msg USING btree (external_id) WHERE (external_id IS NOT NULL);


--
-- Name: msgs_msg_f79b1d64; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_f79b1d64 ON msgs_msg USING btree (visibility);


--
-- Name: msgs_msg_labels_0cc31d7b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_labels_0cc31d7b ON msgs_msg_labels USING btree (msg_id);


--
-- Name: msgs_msg_labels_abec2aca; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_labels_abec2aca ON msgs_msg_labels USING btree (label_id);


--
-- Name: msgs_msg_org_created_id_where_outbound_visible_failed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_org_created_id_where_outbound_visible_failed ON msgs_msg USING btree (org_id, created_on DESC, id DESC) WHERE (((direction)::text = 'O'::text) AND ((visibility)::text = 'V'::text) AND ((status)::text = 'F'::text));


--
-- Name: msgs_msg_org_created_id_where_outbound_visible_outbox; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_org_created_id_where_outbound_visible_outbox ON msgs_msg USING btree (org_id, created_on DESC, id DESC) WHERE (((direction)::text = 'O'::text) AND ((visibility)::text = 'V'::text) AND ((status)::text = ANY ((ARRAY['P'::character varying, 'Q'::character varying])::text[])));


--
-- Name: msgs_msg_org_created_id_where_outbound_visible_sent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_org_created_id_where_outbound_visible_sent ON msgs_msg USING btree (org_id, created_on DESC, id DESC) WHERE (((direction)::text = 'O'::text) AND ((visibility)::text = 'V'::text) AND ((status)::text = ANY ((ARRAY['W'::character varying, 'S'::character varying, 'D'::character varying])::text[])));


--
-- Name: msgs_msg_org_modified_id_where_inbound; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_org_modified_id_where_inbound ON msgs_msg USING btree (org_id, modified_on DESC, id DESC) WHERE ((direction)::text = 'I'::text);


--
-- Name: msgs_msg_responded_to_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_responded_to_not_null ON msgs_msg USING btree (response_to_id) WHERE (response_to_id IS NOT NULL);


--
-- Name: msgs_msg_status_869a44ea_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_status_869a44ea_like ON msgs_msg USING btree (status varchar_pattern_ops);


--
-- Name: msgs_msg_visibility_f61b5308_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_visibility_f61b5308_like ON msgs_msg USING btree (visibility varchar_pattern_ops);


--
-- Name: msgs_msg_visibility_type_created_id_where_inbound; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_msg_visibility_type_created_id_where_inbound ON msgs_msg USING btree (org_id, visibility, msg_type, created_on DESC, id DESC) WHERE ((direction)::text = 'I'::text);


--
-- Name: msgs_systemlabel_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_systemlabel_9cf869aa ON msgs_systemlabelcount USING btree (org_id);


--
-- Name: msgs_systemlabel_org_id_65875516_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_systemlabel_org_id_65875516_idx ON msgs_systemlabelcount USING btree (org_id, label_type);


--
-- Name: msgs_systemlabel_unsquashed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX msgs_systemlabel_unsquashed ON msgs_systemlabelcount USING btree (org_id, label_type) WHERE (NOT is_squashed);


--
-- Name: org_test_contacts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX org_test_contacts ON contacts_contact USING btree (org_id) WHERE (is_test = true);


--
-- Name: orgs_creditalert_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_creditalert_9cf869aa ON orgs_creditalert USING btree (org_id);


--
-- Name: orgs_creditalert_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_creditalert_b3da0983 ON orgs_creditalert USING btree (modified_by_id);


--
-- Name: orgs_creditalert_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_creditalert_e93cb7eb ON orgs_creditalert USING btree (created_by_id);


--
-- Name: orgs_debit_9e459dc4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_debit_9e459dc4 ON orgs_debit USING btree (beneficiary_id);


--
-- Name: orgs_debit_a5d9fd84; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_debit_a5d9fd84 ON orgs_debit USING btree (topup_id);


--
-- Name: orgs_debit_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_debit_e93cb7eb ON orgs_debit USING btree (created_by_id);


--
-- Name: orgs_debit_unsquashed_purged; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_debit_unsquashed_purged ON orgs_debit USING btree (topup_id) WHERE ((NOT is_squashed) AND ((debit_type)::text = 'P'::text));


--
-- Name: orgs_invitation_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_invitation_9cf869aa ON orgs_invitation USING btree (org_id);


--
-- Name: orgs_invitation_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_invitation_b3da0983 ON orgs_invitation USING btree (modified_by_id);


--
-- Name: orgs_invitation_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_invitation_e93cb7eb ON orgs_invitation USING btree (created_by_id);


--
-- Name: orgs_invitation_secret_fa4b1204_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_invitation_secret_fa4b1204_like ON orgs_invitation USING btree (secret varchar_pattern_ops);


--
-- Name: orgs_language_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_language_9cf869aa ON orgs_language USING btree (org_id);


--
-- Name: orgs_language_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_language_b3da0983 ON orgs_language USING btree (modified_by_id);


--
-- Name: orgs_language_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_language_e93cb7eb ON orgs_language USING btree (created_by_id);


--
-- Name: orgs_org_199f5f21; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_199f5f21 ON orgs_org USING btree (primary_language_id);


--
-- Name: orgs_org_6be37982; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_6be37982 ON orgs_org USING btree (parent_id);


--
-- Name: orgs_org_93bfec8a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_93bfec8a ON orgs_org USING btree (country_id);


--
-- Name: orgs_org_administrators_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_administrators_9cf869aa ON orgs_org_administrators USING btree (org_id);


--
-- Name: orgs_org_administrators_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_administrators_e8701ad4 ON orgs_org_administrators USING btree (user_id);


--
-- Name: orgs_org_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_b3da0983 ON orgs_org USING btree (modified_by_id);


--
-- Name: orgs_org_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_e93cb7eb ON orgs_org USING btree (created_by_id);


--
-- Name: orgs_org_editors_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_editors_9cf869aa ON orgs_org_editors USING btree (org_id);


--
-- Name: orgs_org_editors_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_editors_e8701ad4 ON orgs_org_editors USING btree (user_id);


--
-- Name: orgs_org_slug_203caf0d_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_slug_203caf0d_like ON orgs_org USING btree (slug varchar_pattern_ops);


--
-- Name: orgs_org_surveyors_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_surveyors_9cf869aa ON orgs_org_surveyors USING btree (org_id);


--
-- Name: orgs_org_surveyors_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_surveyors_e8701ad4 ON orgs_org_surveyors USING btree (user_id);


--
-- Name: orgs_org_viewers_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_viewers_9cf869aa ON orgs_org_viewers USING btree (org_id);


--
-- Name: orgs_org_viewers_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_org_viewers_e8701ad4 ON orgs_org_viewers USING btree (user_id);


--
-- Name: orgs_topup_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_topup_9cf869aa ON orgs_topup USING btree (org_id);


--
-- Name: orgs_topup_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_topup_b3da0983 ON orgs_topup USING btree (modified_by_id);


--
-- Name: orgs_topup_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_topup_e93cb7eb ON orgs_topup USING btree (created_by_id);


--
-- Name: orgs_topupcredits_a5d9fd84; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_topupcredits_a5d9fd84 ON orgs_topupcredits USING btree (topup_id);


--
-- Name: orgs_topupcredits_unsquashed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_topupcredits_unsquashed ON orgs_topupcredits USING btree (topup_id) WHERE (NOT is_squashed);


--
-- Name: orgs_usersettings_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orgs_usersettings_e8701ad4 ON orgs_usersettings USING btree (user_id);


--
-- Name: public_lead_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX public_lead_b3da0983 ON public_lead USING btree (modified_by_id);


--
-- Name: public_lead_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX public_lead_e93cb7eb ON public_lead USING btree (created_by_id);


--
-- Name: public_video_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX public_video_b3da0983 ON public_video USING btree (modified_by_id);


--
-- Name: public_video_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX public_video_e93cb7eb ON public_video USING btree (created_by_id);


--
-- Name: reports_report_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_report_9cf869aa ON reports_report USING btree (org_id);


--
-- Name: reports_report_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_report_b3da0983 ON reports_report USING btree (modified_by_id);


--
-- Name: reports_report_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_report_e93cb7eb ON reports_report USING btree (created_by_id);


--
-- Name: schedules_schedule_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schedules_schedule_b3da0983 ON schedules_schedule USING btree (modified_by_id);


--
-- Name: schedules_schedule_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schedules_schedule_e93cb7eb ON schedules_schedule USING btree (created_by_id);


--
-- Name: triggers_trigger_7f26ac5b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_7f26ac5b ON triggers_trigger USING btree (flow_id);


--
-- Name: triggers_trigger_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_9cf869aa ON triggers_trigger USING btree (org_id);


--
-- Name: triggers_trigger_b3da0983; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_b3da0983 ON triggers_trigger USING btree (modified_by_id);


--
-- Name: triggers_trigger_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_contacts_6d82f13d ON triggers_trigger_contacts USING btree (contact_id);


--
-- Name: triggers_trigger_contacts_b10b1f9f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_contacts_b10b1f9f ON triggers_trigger_contacts USING btree (trigger_id);


--
-- Name: triggers_trigger_e93cb7eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_e93cb7eb ON triggers_trigger USING btree (created_by_id);


--
-- Name: triggers_trigger_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_groups_0b1b2ae4 ON triggers_trigger_groups USING btree (contactgroup_id);


--
-- Name: triggers_trigger_groups_b10b1f9f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_trigger_groups_b10b1f9f ON triggers_trigger_groups USING btree (trigger_id);


--
-- Name: users_failedlogin_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_failedlogin_e8701ad4 ON users_failedlogin USING btree (user_id);


--
-- Name: users_passwordhistory_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_passwordhistory_e8701ad4 ON users_passwordhistory USING btree (user_id);


--
-- Name: users_recoverytoken_e8701ad4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_recoverytoken_e8701ad4 ON users_recoverytoken USING btree (user_id);


--
-- Name: users_recoverytoken_token_c8594dc8_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_recoverytoken_token_c8594dc8_like ON users_recoverytoken USING btree (token varchar_pattern_ops);


--
-- Name: values_value_0acf093b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_0acf093b ON values_value USING btree (run_id);


--
-- Name: values_value_4d0a6d0f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_4d0a6d0f ON values_value USING btree (ruleset_id);


--
-- Name: values_value_6d82f13d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_6d82f13d ON values_value USING btree (contact_id);


--
-- Name: values_value_91709fb3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_91709fb3 ON values_value USING btree (location_value_id);


--
-- Name: values_value_9cf869aa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_9cf869aa ON values_value USING btree (org_id);


--
-- Name: values_value_9ff6aeda; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_9ff6aeda ON values_value USING btree (contact_field_id);


--
-- Name: values_value_a3329707; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_a3329707 ON values_value USING btree (rule_uuid);


--
-- Name: values_value_contact_field_location_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_contact_field_location_not_null ON values_value USING btree (contact_field_id, location_value_id) WHERE ((contact_field_id IS NOT NULL) AND (location_value_id IS NOT NULL));


--
-- Name: values_value_field_datetime_value_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_field_datetime_value_not_null ON values_value USING btree (contact_field_id, datetime_value) WHERE ((contact_field_id IS NOT NULL) AND (datetime_value IS NOT NULL));


--
-- Name: values_value_field_decimal_value_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_field_decimal_value_not_null ON values_value USING btree (contact_field_id, decimal_value) WHERE ((contact_field_id IS NOT NULL) AND (decimal_value IS NOT NULL));


--
-- Name: values_value_field_string_value_concat_new; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_field_string_value_concat_new ON values_value USING btree ((((contact_field_id || '|'::text) || upper("substring"(string_value, 1, 32)))));


--
-- Name: values_value_rule_uuid_5b1a260a_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX values_value_rule_uuid_5b1a260a_like ON values_value USING btree (rule_uuid varchar_pattern_ops);


--
-- Name: contacts_contact contact_check_update_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contact_check_update_trg BEFORE UPDATE OF is_test, is_blocked, is_stopped ON contacts_contact FOR EACH ROW EXECUTE PROCEDURE contact_check_update();


--
-- Name: msgs_broadcast temba_broadcast_on_change_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_broadcast_on_change_trg AFTER INSERT OR DELETE OR UPDATE ON msgs_broadcast FOR EACH ROW EXECUTE PROCEDURE temba_broadcast_on_change();


--
-- Name: msgs_broadcast temba_broadcast_on_truncate_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_broadcast_on_truncate_trg AFTER TRUNCATE ON msgs_broadcast FOR EACH STATEMENT EXECUTE PROCEDURE temba_broadcast_on_change();


--
-- Name: channels_channelevent temba_channelevent_on_change_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_channelevent_on_change_trg AFTER INSERT OR DELETE OR UPDATE ON channels_channelevent FOR EACH ROW EXECUTE PROCEDURE temba_channelevent_on_change();


--
-- Name: channels_channelevent temba_channelevent_on_truncate_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_channelevent_on_truncate_trg AFTER TRUNCATE ON channels_channelevent FOR EACH STATEMENT EXECUTE PROCEDURE temba_channelevent_on_change();


--
-- Name: channels_channellog temba_channellog_truncate_channelcount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_channellog_truncate_channelcount AFTER TRUNCATE ON channels_channellog FOR EACH STATEMENT EXECUTE PROCEDURE temba_update_channellog_count();


--
-- Name: channels_channellog temba_channellog_update_channelcount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_channellog_update_channelcount AFTER INSERT OR DELETE OR UPDATE OF is_error, channel_id ON channels_channellog FOR EACH ROW EXECUTE PROCEDURE temba_update_channellog_count();


--
-- Name: flows_flowrun temba_flowrun_truncate_flowruncount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_flowrun_truncate_flowruncount AFTER TRUNCATE ON flows_flowrun FOR EACH STATEMENT EXECUTE PROCEDURE temba_update_flowruncount();


--
-- Name: flows_flowrun temba_flowrun_update_flowruncount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_flowrun_update_flowruncount AFTER INSERT OR DELETE OR UPDATE OF exit_type ON flows_flowrun FOR EACH ROW EXECUTE PROCEDURE temba_update_flowruncount();


--
-- Name: flows_flowstep temba_flowstep_truncate_flowpathcount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_flowstep_truncate_flowpathcount AFTER TRUNCATE ON flows_flowstep FOR EACH STATEMENT EXECUTE PROCEDURE temba_update_flowpathcount();


--
-- Name: flows_flowstep temba_flowstep_update_flowpathcount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_flowstep_update_flowpathcount AFTER INSERT OR DELETE OR UPDATE OF left_on ON flows_flowstep FOR EACH ROW EXECUTE PROCEDURE temba_update_flowpathcount();


--
-- Name: msgs_msg temba_msg_clear_channelcount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_msg_clear_channelcount AFTER TRUNCATE ON msgs_msg FOR EACH STATEMENT EXECUTE PROCEDURE temba_update_channelcount();


--
-- Name: msgs_msg_labels temba_msg_labels_on_change_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_msg_labels_on_change_trg AFTER INSERT OR DELETE ON msgs_msg_labels FOR EACH ROW EXECUTE PROCEDURE temba_msg_labels_on_change();


--
-- Name: msgs_msg_labels temba_msg_labels_on_truncate_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_msg_labels_on_truncate_trg AFTER TRUNCATE ON msgs_msg_labels FOR EACH STATEMENT EXECUTE PROCEDURE temba_msg_labels_on_change();


--
-- Name: msgs_msg temba_msg_on_change_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_msg_on_change_trg AFTER INSERT OR DELETE OR UPDATE ON msgs_msg FOR EACH ROW EXECUTE PROCEDURE temba_msg_on_change();


--
-- Name: msgs_msg temba_msg_on_truncate_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_msg_on_truncate_trg AFTER TRUNCATE ON msgs_msg FOR EACH STATEMENT EXECUTE PROCEDURE temba_msg_on_change();


--
-- Name: msgs_msg temba_msg_update_channelcount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_msg_update_channelcount AFTER INSERT OR UPDATE OF direction, msg_type, created_on ON msgs_msg FOR EACH ROW EXECUTE PROCEDURE temba_update_channelcount();


--
-- Name: orgs_debit temba_when_debit_update_then_update_topupcredits_for_debit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_when_debit_update_then_update_topupcredits_for_debit AFTER INSERT OR DELETE OR UPDATE OF topup_id ON orgs_debit FOR EACH ROW EXECUTE PROCEDURE temba_update_topupcredits_for_debit();


--
-- Name: msgs_msg temba_when_msgs_update_then_update_topupcredits; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER temba_when_msgs_update_then_update_topupcredits AFTER INSERT OR DELETE OR UPDATE OF topup_id ON msgs_msg FOR EACH ROW EXECUTE PROCEDURE temba_update_topupcredits();


--
-- Name: contacts_contactgroup_contacts when_contact_groups_changed_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contact_groups_changed_then_update_count_trg AFTER INSERT OR DELETE ON contacts_contactgroup_contacts FOR EACH ROW EXECUTE PROCEDURE update_group_count();


--
-- Name: contacts_contactgroup_contacts when_contact_groups_truncate_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contact_groups_truncate_then_update_count_trg AFTER TRUNCATE ON contacts_contactgroup_contacts FOR EACH STATEMENT EXECUTE PROCEDURE update_group_count();


--
-- Name: contacts_contact when_contacts_changed_then_update_groups_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contacts_changed_then_update_groups_trg AFTER INSERT OR UPDATE ON contacts_contact FOR EACH ROW EXECUTE PROCEDURE update_contact_system_groups();


--
-- Name: flows_exportflowresultstask_flows D351adf3ef72c1d7d251e03ef7e65a9e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT "D351adf3ef72c1d7d251e03ef7e65a9e" FOREIGN KEY (exportflowresultstask_id) REFERENCES flows_exportflowresultstask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: airtime_airtimetransfer airtime_airtimetrans_channel_id_26d84428_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetrans_channel_id_26d84428_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: airtime_airtimetransfer airtime_airtimetrans_contact_id_e90a2275_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetrans_contact_id_e90a2275_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: airtime_airtimetransfer airtime_airtimetransfer_created_by_id_efb7f775_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetransfer_created_by_id_efb7f775_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: airtime_airtimetransfer airtime_airtimetransfer_modified_by_id_4682a18c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetransfer_modified_by_id_4682a18c_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: airtime_airtimetransfer airtime_airtimetransfer_org_id_3eef5867_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY airtime_airtimetransfer
    ADD CONSTRAINT airtime_airtimetransfer_org_id_3eef5867_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken api_apitoken_org_id_b1411661_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_org_id_b1411661_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken api_apitoken_role_id_391adbf5_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_role_id_391adbf5_fk_auth_group_id FOREIGN KEY (role_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken api_apitoken_user_id_9cffaf33_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_user_id_9cffaf33_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthook api_resthook_created_by_id_26c82721_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthook
    ADD CONSTRAINT api_resthook_created_by_id_26c82721_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthook api_resthook_modified_by_id_d5b8e394_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthook
    ADD CONSTRAINT api_resthook_modified_by_id_d5b8e394_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthook api_resthook_org_id_3ac815fe_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthook
    ADD CONSTRAINT api_resthook_org_id_3ac815fe_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthooksubscriber api_resthooksubscriber_created_by_id_ff38300d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_created_by_id_ff38300d_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthooksubscriber api_resthooksubscriber_modified_by_id_0e996ea4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_modified_by_id_0e996ea4_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_resthooksubscriber api_resthooksubscriber_resthook_id_59cd8bc3_fk_api_resthook_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_resthooksubscriber
    ADD CONSTRAINT api_resthooksubscriber_resthook_id_59cd8bc3_fk_api_resthook_id FOREIGN KEY (resthook_id) REFERENCES api_resthook(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_channel_id_a6c81b11_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_channel_id_a6c81b11_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_created_by_id_2b93b775_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_created_by_id_2b93b775_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_modified_by_id_5f5f505b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_modified_by_id_5f5f505b_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_org_id_2c305947_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_org_id_2c305947_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_resthook_id_d2f95048_fk_api_resthook_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_resthook_id_d2f95048_fk_api_resthook_id FOREIGN KEY (resthook_id) REFERENCES api_resthook(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent api_webhookevent_run_id_1fcb4900_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_run_id_1fcb4900_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookresult api_webhookresult_created_by_id_5f2b29f4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresult_created_by_id_5f2b29f4_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookresult api_webhookresult_event_id_31528f05_fk_api_webhookevent_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresult_event_id_31528f05_fk_api_webhookevent_id FOREIGN KEY (event_id) REFERENCES api_webhookevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookresult api_webhookresult_modified_by_id_b2c2079e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresult_modified_by_id_b2c2079e_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permiss_permission_id_84c5c92e_fk_auth_permission_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permiss_permission_id_84c5c92e_fk_auth_permission_id FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permiss_content_type_id_2f476e4b_fk_django_content_type_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_permiss_content_type_id_2f476e4b_fk_django_content_type_id FOREIGN KEY (content_type_id) REFERENCES django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_per_permission_id_1fbb5f2c_fk_auth_permission_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_per_permission_id_1fbb5f2c_fk_auth_permission_id FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: authtoken_token authtoken_token_user_id_35299eff_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_35299eff_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_c_relative_to_id_f8130023_fk_contacts_contactfield_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_c_relative_to_id_f8130023_fk_contacts_contactfield_id FOREIGN KEY (relative_to_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaig_campaign_id_7752d8e7_fk_campaigns_campaign_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaig_campaign_id_7752d8e7_fk_campaigns_campaign_id FOREIGN KEY (campaign_id) REFERENCES campaigns_campaign(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaig_group_id_c1118360_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaig_group_id_c1118360_fk_contacts_contactgroup_id FOREIGN KEY (group_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaign_created_by_id_11fada74_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_created_by_id_11fada74_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaign_modified_by_id_d578b992_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_modified_by_id_d578b992_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign campaigns_campaign_org_id_ac7ac4ee_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_org_id_ac7ac4ee_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignevent_created_by_id_7755844d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_created_by_id_7755844d_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignevent_flow_id_7a962066_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_flow_id_7a962066_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaignevent campaigns_campaignevent_modified_by_id_9645785d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_modified_by_id_9645785d_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_eventfire campaigns_event_event_id_f5396422_fk_campaigns_campaignevent_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT campaigns_event_event_id_f5396422_fk_campaigns_campaignevent_id FOREIGN KEY (event_id) REFERENCES campaigns_campaignevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_eventfire campaigns_eventfire_contact_id_7d58f0a5_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT campaigns_eventfire_contact_id_7d58f0a5_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_channel_id_1344ae59_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_channel_id_1344ae59_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_created_by_id_1b7c1310_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_created_by_id_1b7c1310_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_modified_by_id_e2555348_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_modified_by_id_e2555348_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert channels_alert_sync_event_id_c866791c_fk_channels_syncevent_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_sync_event_id_c866791c_fk_channels_syncevent_id FOREIGN KEY (sync_event_id) REFERENCES channels_syncevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_chan_contact_urn_id_0d28570b_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelevent
    ADD CONSTRAINT channels_chan_contact_urn_id_0d28570b_fk_contacts_contacturn_id FOREIGN KEY (contact_urn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelsession channels_chan_contact_urn_id_b8ed9558_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession
    ADD CONSTRAINT channels_chan_contact_urn_id_b8ed9558_fk_contacts_contacturn_id FOREIGN KEY (contact_urn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channellog channels_chan_session_id_c80a0f04_fk_channels_channelsession_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT channels_chan_session_id_c80a0f04_fk_channels_channelsession_id FOREIGN KEY (session_id) REFERENCES channels_channelsession(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_created_by_id_8141adf4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_created_by_id_8141adf4_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_modified_by_id_af6bcc5e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_modified_by_id_af6bcc5e_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_org_id_fd34a95a_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_org_id_fd34a95a_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel channels_channel_parent_id_6e9cc8f5_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_parent_id_6e9cc8f5_fk_channels_channel_id FOREIGN KEY (parent_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelcount channels_channelcoun_channel_id_b996d6ab_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelcount
    ADD CONSTRAINT channels_channelcoun_channel_id_b996d6ab_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_channeleven_channel_id_ba42cee7_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelevent
    ADD CONSTRAINT channels_channeleven_channel_id_ba42cee7_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_channeleven_contact_id_054a8a49_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelevent
    ADD CONSTRAINT channels_channeleven_contact_id_054a8a49_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelevent channels_channelevent_org_id_4d7fff63_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelevent
    ADD CONSTRAINT channels_channelevent_org_id_4d7fff63_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channellog channels_channellog_channel_id_567d1602_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT channels_channellog_channel_id_567d1602_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channellog channels_channellog_msg_id_e40e6612_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT channels_channellog_msg_id_e40e6612_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelsession channels_channelsess_channel_id_dbea2097_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession
    ADD CONSTRAINT channels_channelsess_channel_id_dbea2097_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelsession channels_channelsess_contact_id_4fcfc63e_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession
    ADD CONSTRAINT channels_channelsess_contact_id_4fcfc63e_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelsession channels_channelsession_created_by_id_e14d0ce1_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession
    ADD CONSTRAINT channels_channelsession_created_by_id_e14d0ce1_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelsession channels_channelsession_modified_by_id_3fabc050_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession
    ADD CONSTRAINT channels_channelsession_modified_by_id_3fabc050_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channelsession channels_channelsession_org_id_1e76f9d3_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channelsession
    ADD CONSTRAINT channels_channelsession_org_id_1e76f9d3_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syncevent channels_syncevent_channel_id_4b72a0f3_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syncevent_channel_id_4b72a0f3_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syncevent channels_syncevent_created_by_id_1f26df72_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syncevent_created_by_id_1f26df72_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syncevent channels_syncevent_modified_by_id_3d34e239_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syncevent_modified_by_id_3d34e239_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_query_fields contacts_c_contactfield_id_4e8430b1_fk_contacts_contactfield_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_c_contactfield_id_4e8430b1_fk_contacts_contactfield_id FOREIGN KEY (contactfield_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_contacts contacts_c_contactgroup_id_4366e864_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_c_contactgroup_id_4366e864_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_query_fields contacts_c_contactgroup_id_94f3146d_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_c_contactgroup_id_94f3146d_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup contacts_c_import_task_id_5b2cae3f_fk_csv_imports_importtask_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_c_import_task_id_5b2cae3f_fk_csv_imports_importtask_id FOREIGN KEY (import_task_id) REFERENCES csv_imports_importtask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact contacts_contact_created_by_id_57537352_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_created_by_id_57537352_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact contacts_contact_modified_by_id_db5cbe12_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_modified_by_id_db5cbe12_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact contacts_contact_org_id_01d86aa4_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_org_id_01d86aa4_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactfield contacts_contactfield_created_by_id_7bce7fd0_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_created_by_id_7bce7fd0_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactfield contacts_contactfield_modified_by_id_99cfac9b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_modified_by_id_99cfac9b_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactfield contacts_contactfield_org_id_d83cc86a_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_org_id_d83cc86a_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroupcount contacts_contactg_group_id_efcdb311_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroupcount
    ADD CONSTRAINT contacts_contactg_group_id_efcdb311_fk_contacts_contactgroup_id FOREIGN KEY (group_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_contacts contacts_contactgrou_contact_id_572f6e61_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgrou_contact_id_572f6e61_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup contacts_contactgroup_created_by_id_6bbeef89_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_created_by_id_6bbeef89_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup contacts_contactgroup_modified_by_id_a765a76e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_modified_by_id_a765a76e_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup contacts_contactgroup_org_id_be850815_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_org_id_be850815_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contacturn contacts_contacturn_channel_id_c3a417df_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_channel_id_c3a417df_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contacturn contacts_contacturn_contact_id_ae38055c_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_contact_id_ae38055c_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contacturn contacts_contacturn_org_id_3cc60a3a_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_org_id_3cc60a3a_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportco_group_id_f623b2c1_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportco_group_id_f623b2c1_fk_contacts_contactgroup_id FOREIGN KEY (group_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportcontacts_modified_by_id_212a480d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontacts_modified_by_id_212a480d_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportcontactst_created_by_id_c2721c08_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactst_created_by_id_c2721c08_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactstask contacts_exportcontactstask_org_id_07dc65f7_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_org_id_07dc65f7_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: csv_imports_importtask csv_imports_importtask_created_by_id_9657a45f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_created_by_id_9657a45f_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: csv_imports_importtask csv_imports_importtask_modified_by_id_282ce6c3_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_modified_by_id_282ce6c3_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_actionlog flows_actionlog_run_id_f78d1481_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionlog
    ADD CONSTRAINT flows_actionlog_run_id_f78d1481_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_actionset flows_actionset_flow_id_e39e2817_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_flow_id_e39e2817_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask flows_exportflowresults_modified_by_id_f4871075_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresults_modified_by_id_f4871075_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask flows_exportflowresultst_created_by_id_43d8e1bd_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultst_created_by_id_43d8e1bd_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask_flows flows_exportflowresultstask_f_flow_id_b4c9e790_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultstask_f_flow_id_b4c9e790_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultstask flows_exportflowresultstask_org_id_3a816787_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_org_id_3a816787_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_groups flows_flow_contactgroup_id_e2252838_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flow_contactgroup_id_e2252838_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_created_by_id_2e1adcb6_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_created_by_id_2e1adcb6_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_labels flows_flow_labels_flow_id_b5b2fc3c_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flow_id_b5b2fc3c_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_labels flows_flow_labels_flowlabel_id_ce11c90a_fk_flows_flowlabel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flowlabel_id_ce11c90a_fk_flows_flowlabel_id FOREIGN KEY (flowlabel_id) REFERENCES flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_modified_by_id_493fb4b1_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_modified_by_id_493fb4b1_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_org_id_51b9c589_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_org_id_51b9c589_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow flows_flow_saved_by_id_edb563b6_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_saved_by_id_edb563b6_fk_auth_user_id FOREIGN KEY (saved_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabel flows_flowlabel_org_id_4ed2f553_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_org_id_4ed2f553_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabel flows_flowlabel_parent_id_73c0a2dd_fk_flows_flowlabel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_parent_id_73c0a2dd_fk_flows_flowlabel_id FOREIGN KEY (parent_id) REFERENCES flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flownodecount flows_flownodecount_flow_id_ba7a0620_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flownodecount
    ADD CONSTRAINT flows_flownodecount_flow_id_ba7a0620_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowpathcount flows_flowpathcount_flow_id_09a7db20_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowpathcount
    ADD CONSTRAINT flows_flowpathcount_flow_id_09a7db20_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowpathrecentmessage flows_flowpathrecentmessage_run_id_63c0cb82_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowpathrecentmessage
    ADD CONSTRAINT flows_flowpathrecentmessage_run_id_63c0cb82_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrevision flows_flowrevision_created_by_id_fb31d40f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_created_by_id_fb31d40f_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrevision flows_flowrevision_flow_id_4ae332c8_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_flow_id_4ae332c8_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrevision flows_flowrevision_modified_by_id_b5464873_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrevision
    ADD CONSTRAINT flows_flowrevision_modified_by_id_b5464873_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_contact_id_985792a9_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_contact_id_985792a9_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_flow_id_9cbb3a32_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_flow_id_9cbb3a32_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_org_id_07d5f694_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_org_id_07d5f694_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_parent_id_f4daf2da_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_parent_id_f4daf2da_fk_flows_flowrun_id FOREIGN KEY (parent_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_session_id_ef240528_fk_channels_channelsession_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_session_id_ef240528_fk_channels_channelsession_id FOREIGN KEY (session_id) REFERENCES channels_channelsession(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_start_id_6f5f00b9_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_start_id_6f5f00b9_fk_flows_flowstart_id FOREIGN KEY (start_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun flows_flowrun_submitted_by_id_573c1038_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_submitted_by_id_573c1038_fk_auth_user_id FOREIGN KEY (submitted_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowruncount flows_flowruncount_flow_id_6a87383f_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowruncount
    ADD CONSTRAINT flows_flowruncount_flow_id_6a87383f_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_contacts flows_flowstart_con_flowstart_id_d8b4cf8f_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_con_flowstart_id_d8b4cf8f_fk_flows_flowstart_id FOREIGN KEY (flowstart_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_contacts flows_flowstart_cont_contact_id_82879510_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_cont_contact_id_82879510_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart flows_flowstart_created_by_id_4eb88868_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_created_by_id_4eb88868_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart flows_flowstart_flow_id_c74e7d30_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_flow_id_c74e7d30_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_groups flows_flowstart_gro_flowstart_id_b44aad1f_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_gro_flowstart_id_b44aad1f_fk_flows_flowstart_id FOREIGN KEY (flowstart_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart flows_flowstart_modified_by_id_c9a338d3_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_modified_by_id_c9a338d3_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep_broadcasts flows_flowstep_broad_broadcast_id_9166e6a2_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_broadcasts
    ADD CONSTRAINT flows_flowstep_broad_broadcast_id_9166e6a2_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep_broadcasts flows_flowstep_broadc_flowstep_id_36999b7e_fk_flows_flowstep_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_broadcasts
    ADD CONSTRAINT flows_flowstep_broadc_flowstep_id_36999b7e_fk_flows_flowstep_id FOREIGN KEY (flowstep_id) REFERENCES flows_flowstep(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep flows_flowstep_contact_id_8becea23_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT flows_flowstep_contact_id_8becea23_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep_messages flows_flowstep_messag_flowstep_id_a5e15cad_fk_flows_flowstep_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messag_flowstep_id_a5e15cad_fk_flows_flowstep_id FOREIGN KEY (flowstep_id) REFERENCES flows_flowstep(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep_messages flows_flowstep_messages_msg_id_66de5012_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_msg_id_66de5012_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep flows_flowstep_run_id_2735b959_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT flows_flowstep_run_id_2735b959_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_ruleset flows_ruleset_flow_id_adb18930_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_flow_id_adb18930_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: guardian_groupobjectpermission guardian_gro_content_type_id_7ade36b8_fk_django_content_type_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_gro_content_type_id_7ade36b8_fk_django_content_type_id FOREIGN KEY (content_type_id) REFERENCES django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: guardian_groupobjectpermission guardian_groupobje_permission_id_36572738_fk_auth_permission_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobje_permission_id_36572738_fk_auth_permission_id FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: guardian_groupobjectpermission guardian_groupobjectpermissi_group_id_4bbbfb62_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobjectpermissi_group_id_4bbbfb62_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: guardian_userobjectpermission guardian_use_content_type_id_2e892405_fk_django_content_type_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_use_content_type_id_2e892405_fk_django_content_type_id FOREIGN KEY (content_type_id) REFERENCES django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: guardian_userobjectpermission guardian_userobjec_permission_id_71807bfc_fk_auth_permission_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjec_permission_id_71807bfc_fk_auth_permission_id FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: guardian_userobjectpermission guardian_userobjectpermission_user_id_d5c1e964_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjectpermission_user_id_d5c1e964_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_adminboundary locations_admi_parent_id_03a6640e_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locations_admi_parent_id_03a6640e_fk_locations_adminboundary_id FOREIGN KEY (parent_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_bo_boundary_id_7ba2d352_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_bo_boundary_id_7ba2d352_fk_locations_adminboundary_id FOREIGN KEY (boundary_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_boundaryalias_created_by_id_46911c69_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_created_by_id_46911c69_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_boundaryalias_modified_by_id_fabf1a13_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_modified_by_id_fabf1a13_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias locations_boundaryalias_org_id_930a8491_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_org_id_930a8491_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask_groups ms_exportmessagestask_id_3071019e_fk_msgs_exportmessagestask_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT ms_exportmessagestask_id_3071019e_fk_msgs_exportmessagestask_id FOREIGN KEY (exportmessagestask_id) REFERENCES msgs_exportmessagestask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_groups msgs_broad_contactgroup_id_c8187bee_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broad_contactgroup_id_c8187bee_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_channel_id_896f7d11_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_channel_id_896f7d11_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_contacts msgs_broadcast_conta_broadcast_id_c5dc5132_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_conta_broadcast_id_c5dc5132_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_contacts msgs_broadcast_conta_contact_id_9ffd3873_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_conta_contact_id_9ffd3873_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_urns msgs_broadcast_contacturn_id_9fe60d63_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_contacturn_id_9fe60d63_fk_contacts_contacturn_id FOREIGN KEY (contacturn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_created_by_id_bc4d5bb1_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_created_by_id_bc4d5bb1_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_groups msgs_broadcast_group_broadcast_id_1b1d150a_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_group_broadcast_id_1b1d150a_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_modified_by_id_b51c67df_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_modified_by_id_b51c67df_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_org_id_78c94f15_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_org_id_78c94f15_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_parent_id_a2f08782_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_parent_id_a2f08782_fk_msgs_broadcast_id FOREIGN KEY (parent_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_recipients msgs_broadcast_recip_broadcast_id_4fa1f262_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_recipients
    ADD CONSTRAINT msgs_broadcast_recip_broadcast_id_4fa1f262_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_recipients msgs_broadcast_recip_contact_id_c2534d9d_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_recipients
    ADD CONSTRAINT msgs_broadcast_recip_contact_id_c2534d9d_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast msgs_broadcast_schedule_id_3bb038fe_fk_schedules_schedule_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_schedule_id_3bb038fe_fk_schedules_schedule_id FOREIGN KEY (schedule_id) REFERENCES schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_urns msgs_broadcast_urns_broadcast_id_aaf9d7b9_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_broadcast_id_aaf9d7b9_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask_groups msgs_expor_contactgroup_id_3b816325_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_expor_contactgroup_id_3b816325_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_created_by_id_f3b48148_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_created_by_id_f3b48148_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_label_id_80585f7d_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_label_id_80585f7d_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_modified_by_id_d76b3bdf_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_modified_by_id_d76b3bdf_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask msgs_exportmessagestask_org_id_8b5afdca_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_org_id_8b5afdca_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_created_by_id_59cd46ee_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_created_by_id_59cd46ee_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_folder_id_fef43746_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_folder_id_fef43746_fk_msgs_label_id FOREIGN KEY (folder_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_modified_by_id_8a4d5291_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_modified_by_id_8a4d5291_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label msgs_label_org_id_a63db233_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_org_id_a63db233_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_labelcount msgs_labelcount_label_id_3d012b42_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_labelcount
    ADD CONSTRAINT msgs_labelcount_label_id_3d012b42_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_broadcast_id_7514e534_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_broadcast_id_7514e534_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_channel_id_0592b6b0_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_channel_id_0592b6b0_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_contact_id_5a7d63da_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_contact_id_5a7d63da_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_contact_urn_id_fc1da718_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_contact_urn_id_fc1da718_fk_contacts_contacturn_id FOREIGN KEY (contact_urn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_labels msgs_msg_labels_label_id_525dfbc1_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_label_id_525dfbc1_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_labels msgs_msg_labels_msg_id_a1f8fefa_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_msg_id_a1f8fefa_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_org_id_d3488a20_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_org_id_d3488a20_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_response_to_id_9ea625a0_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_response_to_id_9ea625a0_fk_msgs_msg_id FOREIGN KEY (response_to_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_session_id_b96f88e9_fk_channels_channelsession_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_session_id_b96f88e9_fk_channels_channelsession_id FOREIGN KEY (session_id) REFERENCES channels_channelsession(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg msgs_msg_topup_id_0d2ccb2d_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_topup_id_0d2ccb2d_fk_orgs_topup_id FOREIGN KEY (topup_id) REFERENCES orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_systemlabelcount msgs_systemlabel_org_id_c6e5a0d7_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_systemlabelcount
    ADD CONSTRAINT msgs_systemlabel_org_id_c6e5a0d7_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert orgs_creditalert_created_by_id_902a99c9_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_created_by_id_902a99c9_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert orgs_creditalert_modified_by_id_a7b1b154_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_modified_by_id_a7b1b154_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert orgs_creditalert_org_id_f6caae69_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_org_id_f6caae69_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_debit orgs_debit_beneficiary_id_b95fb2b4_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_debit
    ADD CONSTRAINT orgs_debit_beneficiary_id_b95fb2b4_fk_orgs_topup_id FOREIGN KEY (beneficiary_id) REFERENCES orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_debit orgs_debit_created_by_id_6e727579_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_debit
    ADD CONSTRAINT orgs_debit_created_by_id_6e727579_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_debit orgs_debit_topup_id_be941fdc_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_debit
    ADD CONSTRAINT orgs_debit_topup_id_be941fdc_fk_orgs_topup_id FOREIGN KEY (topup_id) REFERENCES orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation orgs_invitation_created_by_id_147e359a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_created_by_id_147e359a_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation orgs_invitation_modified_by_id_dd8cae65_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_modified_by_id_dd8cae65_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation orgs_invitation_org_id_d9d2be95_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_org_id_d9d2be95_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_language orgs_language_created_by_id_51a81437_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_created_by_id_51a81437_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_language orgs_language_modified_by_id_44fa8893_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_modified_by_id_44fa8893_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_language orgs_language_org_id_48328636_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_org_id_48328636_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_administrators orgs_org_administrators_org_id_df1333f0_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_org_id_df1333f0_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_administrators orgs_org_administrators_user_id_74fbbbcb_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_user_id_74fbbbcb_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_country_id_c6e479af_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_country_id_c6e479af_fk_locations_adminboundary_id FOREIGN KEY (country_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_created_by_id_f738c068_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_created_by_id_f738c068_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_editors orgs_org_editors_org_id_2ac53adb_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_org_id_2ac53adb_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_editors orgs_org_editors_user_id_21fb7e08_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_user_id_21fb7e08_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_modified_by_id_61e424e7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_modified_by_id_61e424e7_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_parent_id_79ba1bbf_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_parent_id_79ba1bbf_fk_orgs_org_id FOREIGN KEY (parent_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org orgs_org_primary_language_id_595173db_fk_orgs_language_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_primary_language_id_595173db_fk_orgs_language_id FOREIGN KEY (primary_language_id) REFERENCES orgs_language(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_surveyors orgs_org_surveyors_org_id_80c50287_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_org_id_80c50287_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_surveyors orgs_org_surveyors_user_id_78800efa_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_surveyors
    ADD CONSTRAINT orgs_org_surveyors_user_id_78800efa_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_viewers orgs_org_viewers_org_id_d7604492_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_org_id_d7604492_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_viewers orgs_org_viewers_user_id_0650bd4d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_user_id_0650bd4d_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup orgs_topup_created_by_id_026008e4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_created_by_id_026008e4_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup orgs_topup_modified_by_id_c6b91b30_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_modified_by_id_c6b91b30_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup orgs_topup_org_id_cde450ed_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_org_id_cde450ed_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topupcredits orgs_topupcredits_topup_id_9b2e5f7d_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topupcredits
    ADD CONSTRAINT orgs_topupcredits_topup_id_9b2e5f7d_fk_orgs_topup_id FOREIGN KEY (topup_id) REFERENCES orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_usersettings orgs_usersettings_user_id_ef7b03af_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_user_id_ef7b03af_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_lead public_lead_created_by_id_2da6cfc7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT public_lead_created_by_id_2da6cfc7_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_lead public_lead_modified_by_id_934f2f0c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT public_lead_modified_by_id_934f2f0c_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_video public_video_created_by_id_11455096_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT public_video_created_by_id_11455096_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_video public_video_modified_by_id_7009d0a7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT public_video_modified_by_id_7009d0a7_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: reports_report reports_report_created_by_id_e9adac24_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_created_by_id_e9adac24_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: reports_report reports_report_modified_by_id_2c4405a7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_modified_by_id_2c4405a7_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: reports_report reports_report_org_id_3b235c3d_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_org_id_3b235c3d_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedules_schedule schedules_schedule_created_by_id_7a808dd9_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT schedules_schedule_created_by_id_7a808dd9_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedules_schedule schedules_schedule_modified_by_id_75f3d89a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT schedules_schedule_modified_by_id_75f3d89a_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_groups triggers_t_contactgroup_id_648b9858_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_t_contactgroup_id_648b9858_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_channel_id_1e8206f8_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_channel_id_1e8206f8_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_contacts triggers_trigger_con_contact_id_58bca9a4_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_con_contact_id_58bca9a4_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_contacts triggers_trigger_con_trigger_id_2d7952cd_fk_triggers_trigger_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_con_trigger_id_2d7952cd_fk_triggers_trigger_id FOREIGN KEY (trigger_id) REFERENCES triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_created_by_id_265631d7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_created_by_id_265631d7_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_flow_id_89d39d82_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_flow_id_89d39d82_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_groups triggers_trigger_gro_trigger_id_e3f9e0a9_fk_triggers_trigger_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_gro_trigger_id_e3f9e0a9_fk_triggers_trigger_id FOREIGN KEY (trigger_id) REFERENCES triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_modified_by_id_6a5f982f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_modified_by_id_6a5f982f_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_org_id_4a23f4c2_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_org_id_4a23f4c2_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger triggers_trigger_schedule_id_22e85233_fk_schedules_schedule_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_schedule_id_22e85233_fk_schedules_schedule_id FOREIGN KEY (schedule_id) REFERENCES schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_failedlogin users_failedlogin_user_id_d881e023_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_failedlogin
    ADD CONSTRAINT users_failedlogin_user_id_d881e023_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_passwordhistory users_passwordhistory_user_id_1396dbb7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_passwordhistory
    ADD CONSTRAINT users_passwordhistory_user_id_1396dbb7_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_recoverytoken users_recoverytoken_user_id_0d7bef8c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_user_id_0d7bef8c_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value values_location_value_id_f669603a_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_location_value_id_f669603a_fk_locations_adminboundary_id FOREIGN KEY (location_value_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value values_va_contact_field_id_d48e5ab7_fk_contacts_contactfield_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_va_contact_field_id_d48e5ab7_fk_contacts_contactfield_id FOREIGN KEY (contact_field_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value values_value_contact_id_c160928a_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_contact_id_c160928a_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value values_value_org_id_ac514e4c_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_org_id_ac514e4c_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value values_value_ruleset_id_ad05ba21_fk_flows_ruleset_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_ruleset_id_ad05ba21_fk_flows_ruleset_id FOREIGN KEY (ruleset_id) REFERENCES flows_ruleset(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value values_value_run_id_fe1d25b9_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_run_id_fe1d25b9_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: geography_columns; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE geography_columns TO textit;


--
-- Name: geometry_columns; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE geometry_columns TO textit;


--
-- Name: raster_columns; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE raster_columns TO textit;


--
-- Name: raster_overviews; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE raster_overviews TO textit;


--
-- Name: spatial_ref_sys; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE spatial_ref_sys TO textit;


--
-- PostgreSQL database dump complete
--

