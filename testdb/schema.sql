--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA topology;


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
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


SET search_path = public, pg_catalog;

--
-- Name: contact_check_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION contact_check_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.is_test != NEW.is_test THEN
    RAISE EXCEPTION 'is_test cannot be changed';
  END IF;

  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: contacts_contact; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contact (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    is_blocked boolean NOT NULL,
    name character varying(128),
    is_test boolean NOT NULL,
    language character varying(3),
    uuid character varying(36) NOT NULL,
    is_stopped boolean NOT NULL
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
-- Name: exec(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION exec(text) RETURNS text
    LANGUAGE plpgsql
    AS $_$ BEGIN EXECUTE $1; RETURN $1; END; $_$;


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
    ELSE
      PERFORM contact_toggle_system_group(NEW, 'A', true);
      IF NEW.is_stopped THEN
          PERFORM contact_toggle_system_group(NEW, 'F', true);
      END IF;
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
      PERFORM contact_toggle_system_group(NEW, 'A', false);
      PERFORM contact_toggle_system_group(NEW, 'B', true);
      PERFORM contact_toggle_system_group(NEW, 'F', false);
    END IF;

    -- is being unblocked
    IF OLD.is_blocked AND NOT NEW.is_blocked THEN
      PERFORM contact_toggle_system_group(NEW, 'A', true);
      PERFORM contact_toggle_system_group(NEW, 'B', false);
      IF NEW.is_stopped THEN
        PERFORM contact_toggle_system_group(NEW, 'F', true);
      END IF;
    END IF;

    -- is being failed
    IF NOT OLD.is_stopped AND NEW.is_stopped THEN
      PERFORM contact_toggle_system_group(NEW, 'F', true);
    END IF;

    -- is being unfailed
    IF OLD.is_stopped AND NOT NEW.is_stopped THEN
      PERFORM contact_toggle_system_group(NEW, 'F', false);
    END IF;

    -- is being released
    IF OLD.is_active AND NOT NEW.is_active THEN
      PERFORM contact_toggle_system_group(NEW, 'A', false);
      PERFORM contact_toggle_system_group(NEW, 'B', false);
      PERFORM contact_toggle_system_group(NEW, 'F', false);
    END IF;

    -- is being unreleased
    IF NOT OLD.is_active AND NEW.is_active THEN
      IF NOT NEW.is_blocked THEN
        PERFORM contact_toggle_system_group(NEW, 'A', false);
      ELSE
        PERFORM contact_toggle_system_group(NEW, 'B', false);
      END IF;
      IF NEW.is_stopped THEN
        PERFORM contact_toggle_system_group(NEW, 'F', false);
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
      -- increment our group count
      UPDATE contacts_contactgroup SET count = count + 1 WHERE id = NEW.contactgroup_id;
    END IF;

  -- contact being removed from a group
  ELSIF TG_OP = 'DELETE' THEN
    -- is this a test contact
    SELECT contacts_contact.is_test INTO STRICT is_test FROM contacts_contact WHERE id = OLD.contact_id;

    IF NOT is_test THEN
      -- decrement our group count
      UPDATE contacts_contactgroup SET count = count - 1 WHERE id = OLD.contactgroup_id;
    END IF;

  -- table being cleared, reset all counts
  ELSIF TG_OP = 'TRUNCATE' THEN
    UPDATE contacts_contactgroup SET count = 0;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: update_label_count(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_label_count() RETURNS trigger
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
      UPDATE msgs_label SET visible_count = visible_count + 1 WHERE id = NEW.label_id;
    END IF;

  -- label removed from message
  ELSIF TG_OP = 'DELETE' THEN
    -- is this message visible
    SELECT msgs_msg.visibility = 'V' INTO STRICT is_visible FROM msgs_msg WHERE msgs_msg.id = OLD.msg_id;

    IF is_visible THEN
      UPDATE msgs_label SET visible_count = visible_count - 1 WHERE id = OLD.label_id;
    END IF;

  -- no more labels for any messages
  ELSIF TG_OP = 'TRUNCATE' THEN
    UPDATE msgs_label SET visible_count = 0;

  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: update_msg_user_label_counts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_msg_user_label_counts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- is being archived (i.e. no longer included)
  IF OLD.visibility = 'V' AND NEW.visibility = 'A' THEN
    UPDATE msgs_label SET visible_count = visible_count - 1
    FROM msgs_msg_labels
    WHERE msgs_label.label_type = 'L' AND msgs_msg_labels.label_id = msgs_label.id AND msgs_msg_labels.msg_id = NEW.id;
  END IF;

  -- is being restored (i.e. now included)
  IF OLD.visibility = 'A' AND NEW.visibility = 'V' THEN
    UPDATE msgs_label SET visible_count = visible_count + 1
    FROM msgs_msg_labels
    WHERE msgs_label.label_type = 'L' AND msgs_msg_labels.label_id = msgs_label.id AND msgs_msg_labels.msg_id = NEW.id;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: update_topup_used(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_topup_used() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
            BEGIN
              -- Msg is being created
              IF TG_OP = 'INSERT' THEN
                -- If we have a topup, increment our # of used credits
                IF NEW.topup_id IS NOT NULL THEN
                  UPDATE orgs_topup SET used=used+1 where id=NEW.topup_id;
                END IF;

              -- Msg is being updated
              ELSIF TG_OP = 'UPDATE' THEN
                -- If the topup has changed
                IF NEW.topup_id IS DISTINCT FROM OLD.topup_id THEN
                  -- If our old topup wasn't null then decrement our used credits on it
                  IF OLD.topup_id IS NOT NULL THEN
                    UPDATE orgs_topup SET used=used-1 where id=OLD.topup_id;
                  END IF;

                  -- if our new topup isn't null, then increment our used credits on it
                  IF NEW.topup_id IS NOT NULL THEN
                    UPDATE orgs_topup SET used=used+1 where id=NEW.topup_id;
                  END IF;
                END IF;

              -- Msg is being deleted
              ELSIF TG_OP = 'DELETE' THEN
                -- Remove a used credit if this Msg had one assigned
                IF OLD.topup_id IS NOT NULL THEN
                  UPDATE orgs_topup SET used=used-1 WHERE id=OLD.topup_id;
                END IF;

              -- Msgs table is being truncated
              ELSIF TG_OP = 'TRUNCATE' THEN
                -- Clear all used credits
                UPDATE orgs_topup SET used=0;

              END IF;

              RETURN NEW;
            END;
            $$;


--
-- Name: api_apitoken; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE api_apitoken (
    key character varying(40) NOT NULL,
    user_id integer NOT NULL,
    org_id integer NOT NULL,
    created timestamp with time zone NOT NULL
);


--
-- Name: api_webhookevent; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE api_webhookevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    status character varying(1) NOT NULL,
    channel_id integer,
    event character varying(16) NOT NULL,
    data text NOT NULL,
    try_count integer NOT NULL,
    org_id integer NOT NULL,
    next_attempt timestamp with time zone,
    action character varying(8) NOT NULL
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
-- Name: api_webhookresult; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE api_webhookresult (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    event_id integer NOT NULL,
    status_code integer NOT NULL,
    message character varying(255) NOT NULL,
    body text,
    url text,
    data text
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
-- Name: auth_group; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_permission (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
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
-- Name: auth_user; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone NOT NULL,
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
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: authtoken_token; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE authtoken_token (
    key character varying(40) NOT NULL,
    user_id integer NOT NULL,
    created timestamp with time zone NOT NULL
);


--
-- Name: campaigns_campaign; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE campaigns_campaign (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(255) NOT NULL,
    group_id integer NOT NULL,
    is_archived boolean NOT NULL,
    org_id integer NOT NULL,
    uuid character varying(36) NOT NULL
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
-- Name: campaigns_campaignevent; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE campaigns_campaignevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    campaign_id integer NOT NULL,
    "offset" integer NOT NULL,
    relative_to_id integer NOT NULL,
    flow_id integer NOT NULL,
    event_type character varying(1) NOT NULL,
    message text,
    unit character varying(1) NOT NULL,
    delivery_hour integer NOT NULL,
    uuid character varying(36) NOT NULL
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
-- Name: campaigns_eventfire; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE campaigns_eventfire (
    id integer NOT NULL,
    event_id integer NOT NULL,
    contact_id integer NOT NULL,
    scheduled timestamp with time zone NOT NULL,
    fired timestamp with time zone
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
-- Name: celery_taskmeta; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE celery_taskmeta (
    id integer NOT NULL,
    task_id character varying(255) NOT NULL,
    status character varying(50) NOT NULL,
    result text,
    date_done timestamp with time zone NOT NULL,
    traceback text,
    hidden boolean NOT NULL,
    meta text
);


--
-- Name: celery_taskmeta_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE celery_taskmeta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: celery_taskmeta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE celery_taskmeta_id_seq OWNED BY celery_taskmeta.id;


--
-- Name: celery_tasksetmeta; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE celery_tasksetmeta (
    id integer NOT NULL,
    taskset_id character varying(255) NOT NULL,
    result text NOT NULL,
    date_done timestamp with time zone NOT NULL,
    hidden boolean NOT NULL
);


--
-- Name: celery_tasksetmeta_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE celery_tasksetmeta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: celery_tasksetmeta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE celery_tasksetmeta_id_seq OWNED BY celery_tasksetmeta.id;


--
-- Name: channels_alert; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_alert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    sync_event_id integer,
    alert_type character varying(1) NOT NULL,
    ended_on timestamp with time zone,
    channel_id integer NOT NULL,
    host character varying(32) NOT NULL
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
-- Name: channels_channel; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_channel (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(64),
    address character varying(255),
    org_id integer,
    gcm_id character varying(255),
    secret character varying(64),
    last_seen timestamp with time zone NOT NULL,
    claim_code character varying(16),
    country character varying(2),
    alert_email character varying(75),
    uuid character varying(36),
    device character varying(255),
    os character varying(255),
    channel_type character varying(3) NOT NULL,
    config text,
    role character varying(4) NOT NULL,
    parent_id integer,
    bod text
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
-- Name: channels_channellog; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_channellog (
    id integer NOT NULL,
    msg_id integer NOT NULL,
    description character varying(255) NOT NULL,
    url text,
    method character varying(16),
    request text,
    response text,
    response_status integer,
    created_on timestamp with time zone NOT NULL,
    is_error boolean NOT NULL
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
-- Name: channels_syncevent; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_syncevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    channel_id integer NOT NULL,
    power_source character varying(64) NOT NULL,
    power_level integer NOT NULL,
    network_type character varying(128) NOT NULL,
    power_status character varying(64) NOT NULL,
    lifetime integer,
    pending_message_count integer NOT NULL,
    retry_message_count integer NOT NULL,
    incoming_command_count integer NOT NULL,
    outgoing_command_count integer NOT NULL
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
-- Name: contacts_contactfield; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contactfield (
    id integer NOT NULL,
    org_id integer NOT NULL,
    label character varying(36) NOT NULL,
    key character varying(36) NOT NULL,
    is_active boolean NOT NULL,
    show_in_table boolean NOT NULL,
    value_type character varying(1) NOT NULL
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
-- Name: contacts_contactgroup; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contactgroup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(64) NOT NULL,
    org_id integer NOT NULL,
    import_task_id integer,
    query text,
    uuid character varying(36) NOT NULL,
    count integer NOT NULL,
    group_type character varying(1) NOT NULL
);


--
-- Name: contacts_contactgroup_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: contacts_contactgroup_query_fields; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: contacts_contacturn; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contacturn (
    id integer NOT NULL,
    contact_id integer,
    urn character varying(255) NOT NULL,
    scheme character varying(128) NOT NULL,
    org_id integer NOT NULL,
    priority integer NOT NULL,
    path character varying(255) NOT NULL,
    channel_id integer
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
-- Name: contacts_exportcontactstask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_exportcontactstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    group_id integer,
    host character varying(32) NOT NULL,
    task_id character varying(64)
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
-- Name: csv_imports_importtask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE csv_imports_importtask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    csv_file character varying(100) NOT NULL,
    model_class character varying(255) NOT NULL,
    import_log text NOT NULL,
    task_id character varying(64),
    import_params text,
    import_results text
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
-- Name: dashboard_pagerank; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dashboard_pagerank (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    website_id integer NOT NULL,
    rank integer NOT NULL
);


--
-- Name: dashboard_pagerank_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dashboard_pagerank_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_pagerank_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dashboard_pagerank_id_seq OWNED BY dashboard_pagerank.id;


--
-- Name: dashboard_search; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dashboard_search (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    query character varying(256) NOT NULL
);


--
-- Name: dashboard_search_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dashboard_search_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_search_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dashboard_search_id_seq OWNED BY dashboard_search.id;


--
-- Name: dashboard_searchposition; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dashboard_searchposition (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    website_id integer NOT NULL,
    search_id integer NOT NULL,
    "position" integer NOT NULL
);


--
-- Name: dashboard_searchposition_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dashboard_searchposition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_searchposition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dashboard_searchposition_id_seq OWNED BY dashboard_searchposition.id;


--
-- Name: dashboard_website; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dashboard_website (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    domain character varying(256) NOT NULL
);


--
-- Name: dashboard_website_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dashboard_website_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_website_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dashboard_website_id_seq OWNED BY dashboard_website.id;


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE django_content_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
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
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: django_select2_keymap; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE django_select2_keymap (
    id integer NOT NULL,
    key character varying(40) NOT NULL,
    value character varying(100) NOT NULL,
    accessed_on timestamp with time zone NOT NULL
);


--
-- Name: django_select2_keymap_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE django_select2_keymap_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_select2_keymap_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE django_select2_keymap_id_seq OWNED BY django_select2_keymap.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


--
-- Name: django_site; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: djcelery_crontabschedule; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_crontabschedule (
    id integer NOT NULL,
    minute character varying(64) NOT NULL,
    hour character varying(64) NOT NULL,
    day_of_week character varying(64) NOT NULL,
    day_of_month character varying(64) NOT NULL,
    month_of_year character varying(64) NOT NULL
);


--
-- Name: djcelery_crontabschedule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_crontabschedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_crontabschedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_crontabschedule_id_seq OWNED BY djcelery_crontabschedule.id;


--
-- Name: djcelery_intervalschedule; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_intervalschedule (
    id integer NOT NULL,
    every integer NOT NULL,
    period character varying(24) NOT NULL
);


--
-- Name: djcelery_intervalschedule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_intervalschedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_intervalschedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_intervalschedule_id_seq OWNED BY djcelery_intervalschedule.id;


--
-- Name: djcelery_periodictask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_periodictask (
    id integer NOT NULL,
    name character varying(200) NOT NULL,
    task character varying(200) NOT NULL,
    interval_id integer,
    crontab_id integer,
    args text NOT NULL,
    kwargs text NOT NULL,
    queue character varying(200),
    exchange character varying(200),
    routing_key character varying(200),
    expires timestamp with time zone,
    enabled boolean NOT NULL,
    last_run_at timestamp with time zone,
    total_run_count integer NOT NULL,
    date_changed timestamp with time zone NOT NULL,
    description text NOT NULL,
    CONSTRAINT djcelery_periodictask_total_run_count_check CHECK ((total_run_count >= 0))
);


--
-- Name: djcelery_periodictask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_periodictask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_periodictask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_periodictask_id_seq OWNED BY djcelery_periodictask.id;


--
-- Name: djcelery_periodictasks; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_periodictasks (
    ident smallint NOT NULL,
    last_update timestamp with time zone NOT NULL
);


--
-- Name: djcelery_taskstate; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_taskstate (
    id integer NOT NULL,
    state character varying(64) NOT NULL,
    task_id character varying(36) NOT NULL,
    name character varying(200),
    tstamp timestamp with time zone NOT NULL,
    args text,
    kwargs text,
    eta timestamp with time zone,
    expires timestamp with time zone,
    result text,
    traceback text,
    runtime double precision,
    retries integer NOT NULL,
    worker_id integer,
    hidden boolean NOT NULL
);


--
-- Name: djcelery_taskstate_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_taskstate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_taskstate_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_taskstate_id_seq OWNED BY djcelery_taskstate.id;


--
-- Name: djcelery_workerstate; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_workerstate (
    id integer NOT NULL,
    hostname character varying(255) NOT NULL,
    last_heartbeat timestamp with time zone
);


--
-- Name: djcelery_workerstate_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_workerstate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_workerstate_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_workerstate_id_seq OWNED BY djcelery_workerstate.id;


--
-- Name: flows_actionlog; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_actionlog (
    id integer NOT NULL,
    run_id integer NOT NULL,
    text text NOT NULL,
    created_on timestamp with time zone NOT NULL
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
-- Name: flows_actionset; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_actionset (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    flow_id integer NOT NULL,
    actions text NOT NULL,
    x integer NOT NULL,
    y integer NOT NULL,
    created_on timestamp with time zone DEFAULT '2013-06-28 00:00:00'::timestamp without time zone NOT NULL,
    modified_on timestamp with time zone DEFAULT '2013-06-28 00:00:00'::timestamp without time zone NOT NULL,
    destination character varying(36),
    destination_type character varying(1)
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
-- Name: flows_exportflowresultstask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_exportflowresultstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    task_id character varying(64),
    host character varying(32) NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: flows_exportflowresultstask_flows; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: flows_flow; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flow (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(64) NOT NULL,
    org_id integer NOT NULL,
    is_archived boolean NOT NULL,
    flow_type character varying(1) NOT NULL,
    metadata text,
    entry_uuid character varying(36),
    entry_type character varying(1),
    expires_after_minutes integer NOT NULL,
    ignore_triggers boolean NOT NULL,
    saved_on timestamp with time zone NOT NULL,
    saved_by_id integer NOT NULL,
    base_language character varying(3),
    uuid character varying(36) NOT NULL
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
-- Name: flows_flow_labels; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: flows_flowlabel; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowlabel (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    parent_id integer,
    org_id integer NOT NULL
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
-- Name: flows_flowrun; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowrun (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    contact_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    is_active boolean NOT NULL,
    fields text,
    expires_on timestamp with time zone,
    expired_on timestamp with time zone,
    call_id integer,
    start_id integer
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
-- Name: flows_flowstart; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowstart (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    flow_id integer NOT NULL,
    restart_participants boolean NOT NULL,
    status character varying(1) NOT NULL,
    contact_count integer NOT NULL
);


--
-- Name: flows_flowstart_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: flows_flowstart_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: flows_flowstep; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowstep (
    id integer NOT NULL,
    step_type character varying(1) NOT NULL,
    step_uuid character varying(36) NOT NULL,
    arrived_on timestamp with time zone NOT NULL,
    left_on timestamp with time zone,
    rule_uuid character varying(36),
    next_uuid character varying(36),
    rule_category character varying(36),
    rule_decimal_value numeric(36,8),
    run_id integer DEFAULT 1 NOT NULL,
    rule_value character varying(640),
    contact_id integer NOT NULL
);


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
-- Name: flows_flowstep_messages; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: flows_flowversion; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowversion (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    flow_id integer NOT NULL,
    definition text NOT NULL
);


--
-- Name: flows_flowversion_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowversion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowversion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowversion_id_seq OWNED BY flows_flowversion.id;


--
-- Name: flows_ruleset; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_ruleset (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    flow_id integer NOT NULL,
    label character varying(64),
    rules text NOT NULL,
    x integer NOT NULL,
    y integer NOT NULL,
    created_on timestamp with time zone DEFAULT '2013-06-28 00:00:00'::timestamp without time zone NOT NULL,
    modified_on timestamp with time zone DEFAULT '2013-06-28 00:00:00'::timestamp without time zone NOT NULL,
    operand character varying(128),
    webhook_url character varying(255),
    webhook_action character varying(8),
    finished_key character varying(1),
    value_type character varying(1) NOT NULL,
    response_type character varying(1) NOT NULL
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
-- Name: guardian_groupobjectpermission; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE guardian_groupobjectpermission (
    id integer NOT NULL,
    permission_id integer NOT NULL,
    content_type_id integer NOT NULL,
    group_id integer NOT NULL,
    object_pk character varying(255) NOT NULL
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
-- Name: guardian_userobjectpermission; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE guardian_userobjectpermission (
    id integer NOT NULL,
    permission_id integer NOT NULL,
    content_type_id integer NOT NULL,
    user_id integer NOT NULL,
    object_pk character varying(255) NOT NULL
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
-- Name: ivr_ivrcall; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE ivr_ivrcall (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    external_id character varying(255) NOT NULL,
    status character varying(1) NOT NULL,
    channel_id integer NOT NULL,
    contact_id integer NOT NULL,
    direction character varying(1) NOT NULL,
    flow_id integer,
    started_on timestamp with time zone,
    ended_on timestamp with time zone,
    org_id integer NOT NULL,
    call_type character varying(1) NOT NULL,
    duration integer,
    contact_urn_id integer NOT NULL
);


--
-- Name: ivr_ivrcall_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE ivr_ivrcall_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ivr_ivrcall_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE ivr_ivrcall_id_seq OWNED BY ivr_ivrcall.id;


--
-- Name: locations_adminboundary; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE locations_adminboundary (
    id integer NOT NULL,
    osm_id character varying(15) NOT NULL,
    name character varying(128) NOT NULL,
    level integer NOT NULL,
    geometry geometry(MultiPolygon,4326),
    simplified_geometry geometry(MultiPolygon,4326),
    parent_id integer
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
-- Name: locations_boundaryalias; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE locations_boundaryalias (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    boundary_id integer NOT NULL,
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
-- Name: msgs_broadcast; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_broadcast (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    text text NOT NULL,
    status character varying(1) NOT NULL,
    org_id integer NOT NULL,
    schedule_id integer,
    parent_id integer,
    language_dict text,
    recipient_count integer,
    channel_id integer
);


--
-- Name: msgs_broadcast_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: msgs_broadcast_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: msgs_broadcast_urns; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: msgs_call; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_call (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    channel_id integer,
    contact_id integer NOT NULL,
    "time" timestamp with time zone NOT NULL,
    duration integer NOT NULL,
    call_type character varying(16) NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: msgs_call_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_call_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_call_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_call_id_seq OWNED BY msgs_call.id;


--
-- Name: msgs_exportmessagestask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_exportmessagestask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    start_date date,
    end_date date,
    host character varying(32) NOT NULL,
    task_id character varying(64),
    label_id integer
);


--
-- Name: msgs_exportmessagestask_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: msgs_label; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_label (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    org_id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    is_active boolean NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    folder_id integer,
    label_type character varying(1) NOT NULL,
    visible_count integer NOT NULL,
    CONSTRAINT msgs_label_visible_count_check CHECK ((visible_count >= 0))
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
-- Name: msgs_msg; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_msg (
    id integer NOT NULL,
    channel_id integer,
    contact_id integer NOT NULL,
    broadcast_id integer,
    text text NOT NULL,
    direction character varying(1) NOT NULL,
    status character varying(1) NOT NULL,
    response_to_id integer,
    org_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    sent_on timestamp with time zone,
    delivered_on timestamp with time zone,
    has_template_error boolean NOT NULL,
    msg_type character varying(1),
    msg_count integer NOT NULL,
    external_id character varying(255),
    error_count integer NOT NULL,
    next_attempt timestamp with time zone NOT NULL,
    visibility character varying(1) NOT NULL,
    topup_id integer,
    queued_on timestamp with time zone,
    priority integer NOT NULL,
    contact_urn_id integer NOT NULL,
    recording_url character varying(255)
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
-- Name: msgs_msg_labels; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: orgs_creditalert; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_creditalert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    threshold integer NOT NULL
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
-- Name: orgs_invitation; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_invitation (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    email character varying(75) NOT NULL,
    secret character varying(64) NOT NULL,
    user_group character varying(1) NOT NULL,
    host character varying(32) NOT NULL
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
-- Name: orgs_language; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_language (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    iso_code character varying(4) NOT NULL,
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
-- Name: orgs_org; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_org (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    msg_last_viewed timestamp with time zone NOT NULL,
    webhook character varying(255),
    webhook_events integer NOT NULL,
    plan character varying(16) NOT NULL,
    plan_start timestamp with time zone NOT NULL,
    stripe_customer character varying(32),
    timezone character varying(64) DEFAULT 'Africa/Kigali'::character varying NOT NULL,
    flows_last_viewed timestamp with time zone NOT NULL,
    language character varying(64),
    date_format character varying(1) NOT NULL,
    config text,
    slug character varying(255),
    is_anon boolean NOT NULL,
    country_id integer,
    primary_language_id integer
);


--
-- Name: orgs_org_administrators; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: orgs_org_editors; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: orgs_org_viewers; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: orgs_topup; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_topup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    price integer NOT NULL,
    credits integer NOT NULL,
    expires_on timestamp with time zone NOT NULL,
    stripe_charge character varying(32),
    comment character varying(255),
    used integer NOT NULL
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
-- Name: orgs_usersettings; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_usersettings (
    id integer NOT NULL,
    user_id integer NOT NULL,
    language character varying(8) NOT NULL,
    tel character varying(16)
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
-- Name: public_lead; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE public_lead (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    email character varying(75) NOT NULL
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
-- Name: public_video; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE public_video (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(255) NOT NULL,
    summary text NOT NULL,
    description text NOT NULL,
    vimeo_id character varying(255) NOT NULL,
    "order" integer NOT NULL
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
-- Name: reports_report; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE reports_report (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    title character varying(64) NOT NULL,
    description text NOT NULL,
    org_id integer NOT NULL,
    config text,
    is_published boolean NOT NULL
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
-- Name: schedules_schedule; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE schedules_schedule (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    repeat_period character varying(1),
    repeat_days integer,
    last_fire timestamp with time zone,
    next_fire timestamp with time zone,
    repeat_day_of_month integer,
    repeat_hour_of_day integer,
    status character varying(1) NOT NULL
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
-- Name: south_migrationhistory; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE south_migrationhistory (
    id integer NOT NULL,
    app_name character varying(255) NOT NULL,
    migration character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


--
-- Name: south_migrationhistory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE south_migrationhistory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: south_migrationhistory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE south_migrationhistory_id_seq OWNED BY south_migrationhistory.id;


--
-- Name: triggers_trigger; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE triggers_trigger (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    keyword character varying(16),
    flow_id integer,
    last_triggered timestamp with time zone,
    trigger_count integer NOT NULL,
    is_archived boolean NOT NULL,
    schedule_id integer,
    trigger_type character varying(1) NOT NULL,
    channel_id integer
);


--
-- Name: triggers_trigger_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: triggers_trigger_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
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
-- Name: users_failedlogin; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users_failedlogin (
    id integer NOT NULL,
    user_id integer NOT NULL,
    failed_on timestamp with time zone NOT NULL
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
-- Name: users_passwordhistory; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users_passwordhistory (
    id integer NOT NULL,
    user_id integer NOT NULL,
    password character varying(255) NOT NULL,
    set_on timestamp with time zone NOT NULL
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
-- Name: users_recoverytoken; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users_recoverytoken (
    id integer NOT NULL,
    user_id integer NOT NULL,
    token character varying(32) NOT NULL,
    created_on timestamp with time zone NOT NULL
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
-- Name: values_value; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE values_value (
    id integer NOT NULL,
    contact_id integer NOT NULL,
    contact_field_id integer,
    string_value text NOT NULL,
    decimal_value numeric(36,8),
    datetime_value timestamp with time zone,
    org_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    ruleset_id integer,
    run_id integer,
    rule_uuid character varying(255),
    category character varying(128),
    location_value_id integer,
    recording_value text
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
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent ALTER COLUMN id SET DEFAULT nextval('api_webhookevent_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult ALTER COLUMN id SET DEFAULT nextval('api_webhookresult_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group ALTER COLUMN id SET DEFAULT nextval('auth_group_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('auth_group_permissions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission ALTER COLUMN id SET DEFAULT nextval('auth_permission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user ALTER COLUMN id SET DEFAULT nextval('auth_user_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups ALTER COLUMN id SET DEFAULT nextval('auth_user_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('auth_user_user_permissions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign ALTER COLUMN id SET DEFAULT nextval('campaigns_campaign_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent ALTER COLUMN id SET DEFAULT nextval('campaigns_campaignevent_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire ALTER COLUMN id SET DEFAULT nextval('campaigns_eventfire_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY celery_taskmeta ALTER COLUMN id SET DEFAULT nextval('celery_taskmeta_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY celery_tasksetmeta ALTER COLUMN id SET DEFAULT nextval('celery_tasksetmeta_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert ALTER COLUMN id SET DEFAULT nextval('channels_alert_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel ALTER COLUMN id SET DEFAULT nextval('channels_channel_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog ALTER COLUMN id SET DEFAULT nextval('channels_channellog_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent ALTER COLUMN id SET DEFAULT nextval('channels_syncevent_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact ALTER COLUMN id SET DEFAULT nextval('contacts_contact_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield ALTER COLUMN id SET DEFAULT nextval('contacts_contactfield_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_query_fields_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn ALTER COLUMN id SET DEFAULT nextval('contacts_contacturn_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask ALTER COLUMN id SET DEFAULT nextval('contacts_exportcontactstask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask ALTER COLUMN id SET DEFAULT nextval('csv_imports_importtask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_pagerank ALTER COLUMN id SET DEFAULT nextval('dashboard_pagerank_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_search ALTER COLUMN id SET DEFAULT nextval('dashboard_search_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_searchposition ALTER COLUMN id SET DEFAULT nextval('dashboard_searchposition_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_website ALTER COLUMN id SET DEFAULT nextval('dashboard_website_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_content_type ALTER COLUMN id SET DEFAULT nextval('django_content_type_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_migrations ALTER COLUMN id SET DEFAULT nextval('django_migrations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_select2_keymap ALTER COLUMN id SET DEFAULT nextval('django_select2_keymap_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_site ALTER COLUMN id SET DEFAULT nextval('django_site_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_crontabschedule ALTER COLUMN id SET DEFAULT nextval('djcelery_crontabschedule_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_intervalschedule ALTER COLUMN id SET DEFAULT nextval('djcelery_intervalschedule_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_periodictask ALTER COLUMN id SET DEFAULT nextval('djcelery_periodictask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_taskstate ALTER COLUMN id SET DEFAULT nextval('djcelery_taskstate_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_workerstate ALTER COLUMN id SET DEFAULT nextval('djcelery_workerstate_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionlog ALTER COLUMN id SET DEFAULT nextval('flows_actionlog_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset ALTER COLUMN id SET DEFAULT nextval('flows_actionset_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask ALTER COLUMN id SET DEFAULT nextval('flows_exportflowresultstask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows ALTER COLUMN id SET DEFAULT nextval('flows_exportflowresultstask_flows_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow ALTER COLUMN id SET DEFAULT nextval('flows_flow_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels ALTER COLUMN id SET DEFAULT nextval('flows_flow_labels_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel ALTER COLUMN id SET DEFAULT nextval('flows_flowlabel_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun ALTER COLUMN id SET DEFAULT nextval('flows_flowrun_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep ALTER COLUMN id SET DEFAULT nextval('flows_flowstep_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages ALTER COLUMN id SET DEFAULT nextval('flows_flowstep_messages_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion ALTER COLUMN id SET DEFAULT nextval('flows_flowversion_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset ALTER COLUMN id SET DEFAULT nextval('flows_ruleset_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission ALTER COLUMN id SET DEFAULT nextval('guardian_groupobjectpermission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission ALTER COLUMN id SET DEFAULT nextval('guardian_userobjectpermission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall ALTER COLUMN id SET DEFAULT nextval('ivr_ivrcall_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary ALTER COLUMN id SET DEFAULT nextval('locations_adminboundary_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias ALTER COLUMN id SET DEFAULT nextval('locations_boundaryalias_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_urns_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call ALTER COLUMN id SET DEFAULT nextval('msgs_call_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask ALTER COLUMN id SET DEFAULT nextval('msgs_exportmessagestask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups ALTER COLUMN id SET DEFAULT nextval('msgs_exportmessagestask_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label ALTER COLUMN id SET DEFAULT nextval('msgs_label_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg ALTER COLUMN id SET DEFAULT nextval('msgs_msg_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels ALTER COLUMN id SET DEFAULT nextval('msgs_msg_labels_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert ALTER COLUMN id SET DEFAULT nextval('orgs_creditalert_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation ALTER COLUMN id SET DEFAULT nextval('orgs_invitation_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language ALTER COLUMN id SET DEFAULT nextval('orgs_language_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org ALTER COLUMN id SET DEFAULT nextval('orgs_org_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators ALTER COLUMN id SET DEFAULT nextval('orgs_org_administrators_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors ALTER COLUMN id SET DEFAULT nextval('orgs_org_editors_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers ALTER COLUMN id SET DEFAULT nextval('orgs_org_viewers_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup ALTER COLUMN id SET DEFAULT nextval('orgs_topup_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_usersettings ALTER COLUMN id SET DEFAULT nextval('orgs_usersettings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead ALTER COLUMN id SET DEFAULT nextval('public_lead_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video ALTER COLUMN id SET DEFAULT nextval('public_video_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report ALTER COLUMN id SET DEFAULT nextval('reports_report_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule ALTER COLUMN id SET DEFAULT nextval('schedules_schedule_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY south_migrationhistory ALTER COLUMN id SET DEFAULT nextval('south_migrationhistory_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_failedlogin ALTER COLUMN id SET DEFAULT nextval('users_failedlogin_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_passwordhistory ALTER COLUMN id SET DEFAULT nextval('users_passwordhistory_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_recoverytoken ALTER COLUMN id SET DEFAULT nextval('users_recoverytoken_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value ALTER COLUMN id SET DEFAULT nextval('values_value_id_seq'::regclass);


--
-- Name: api_apitoken_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_pkey PRIMARY KEY (key);


--
-- Name: api_apitoken_user_id_5752cf28bea31ac4_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_user_id_5752cf28bea31ac4_uniq UNIQUE (user_id, org_id);


--
-- Name: api_webhookevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_pkey PRIMARY KEY (id);


--
-- Name: api_webhookresult_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresult_pkey PRIMARY KEY (id);


--
-- Name: auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions_group_id_permission_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_key UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission_content_type_id_codename_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_key UNIQUE (content_type_id, codename);


--
-- Name: auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups_user_id_group_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_key UNIQUE (user_id, group_id);


--
-- Name: auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions_user_id_permission_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_key UNIQUE (user_id, permission_id);


--
-- Name: auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: authtoken_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_pkey PRIMARY KEY (key);


--
-- Name: authtoken_token_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_key UNIQUE (user_id);


--
-- Name: campaigns_campaign_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaign_uuid_70da94f192ee2f54_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_uuid_70da94f192ee2f54_uniq UNIQUE (uuid);


--
-- Name: campaigns_campaignevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaignevent_uuid_652cd08c5c5af6b7_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_uuid_652cd08c5c5af6b7_uniq UNIQUE (uuid);


--
-- Name: campaigns_eventfire_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT campaigns_eventfire_pkey PRIMARY KEY (id);


--
-- Name: celery_taskmeta_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_taskmeta
    ADD CONSTRAINT celery_taskmeta_pkey PRIMARY KEY (id);


--
-- Name: celery_taskmeta_task_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_taskmeta
    ADD CONSTRAINT celery_taskmeta_task_id_key UNIQUE (task_id);


--
-- Name: celery_tasksetmeta_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_tasksetmeta
    ADD CONSTRAINT celery_tasksetmeta_pkey PRIMARY KEY (id);


--
-- Name: celery_tasksetmeta_taskset_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_tasksetmeta
    ADD CONSTRAINT celery_tasksetmeta_taskset_id_key UNIQUE (taskset_id);


--
-- Name: channels_alert_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_pkey PRIMARY KEY (id);


--
-- Name: channels_channel_claim_code_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_claim_code_key UNIQUE (claim_code);


--
-- Name: channels_channel_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_pkey PRIMARY KEY (id);


--
-- Name: channels_channel_secret_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_secret_key UNIQUE (secret);


--
-- Name: channels_channellog_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT channels_channellog_pkey PRIMARY KEY (id);


--
-- Name: channels_syncevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syncevent_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact_uuid_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_uuid_uniq UNIQUE (uuid);


--
-- Name: contacts_contactfield_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_cont_contactgroup_id_1b08ad0e5aceab9_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_cont_contactgroup_id_1b08ad0e5aceab9_uniq UNIQUE (contactgroup_id, contact_id);


--
-- Name: contacts_contactgroup_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_contacts_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_que_contactgroup_id_1f961d508de63691_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_que_contactgroup_id_1f961d508de63691_uniq UNIQUE (contactgroup_id, contactfield_id);


--
-- Name: contacts_contactgroup_query_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_query_fields_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contacturn_org_id_53c1dd6b37975d80_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_org_id_53c1dd6b37975d80_uniq UNIQUE (org_id, urn);


--
-- Name: contacts_contacturn_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_pkey PRIMARY KEY (id);


--
-- Name: contacts_exportcontactstask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_pkey PRIMARY KEY (id);


--
-- Name: csv_imports_importtask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_pkey PRIMARY KEY (id);


--
-- Name: dashboard_pagerank_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dashboard_pagerank
    ADD CONSTRAINT dashboard_pagerank_pkey PRIMARY KEY (id);


--
-- Name: dashboard_search_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dashboard_search
    ADD CONSTRAINT dashboard_search_pkey PRIMARY KEY (id);


--
-- Name: dashboard_searchposition_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dashboard_searchposition
    ADD CONSTRAINT dashboard_searchposition_pkey PRIMARY KEY (id);


--
-- Name: dashboard_website_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dashboard_website
    ADD CONSTRAINT dashboard_website_pkey PRIMARY KEY (id);


--
-- Name: django_content_type_app_label_model_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_key UNIQUE (app_label, model);


--
-- Name: django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_select2_keymap_key_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_select2_keymap
    ADD CONSTRAINT django_select2_keymap_key_key UNIQUE (key);


--
-- Name: django_select2_keymap_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_select2_keymap
    ADD CONSTRAINT django_select2_keymap_pkey PRIMARY KEY (id);


--
-- Name: django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: django_site_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_site
    ADD CONSTRAINT django_site_pkey PRIMARY KEY (id);


--
-- Name: djcelery_crontabschedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_crontabschedule
    ADD CONSTRAINT djcelery_crontabschedule_pkey PRIMARY KEY (id);


--
-- Name: djcelery_intervalschedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_intervalschedule
    ADD CONSTRAINT djcelery_intervalschedule_pkey PRIMARY KEY (id);


--
-- Name: djcelery_periodictask_name_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT djcelery_periodictask_name_key UNIQUE (name);


--
-- Name: djcelery_periodictask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT djcelery_periodictask_pkey PRIMARY KEY (id);


--
-- Name: djcelery_periodictasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_periodictasks
    ADD CONSTRAINT djcelery_periodictasks_pkey PRIMARY KEY (ident);


--
-- Name: djcelery_taskstate_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_taskstate
    ADD CONSTRAINT djcelery_taskstate_pkey PRIMARY KEY (id);


--
-- Name: djcelery_taskstate_task_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_taskstate
    ADD CONSTRAINT djcelery_taskstate_task_id_key UNIQUE (task_id);


--
-- Name: djcelery_workerstate_hostname_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_workerstate
    ADD CONSTRAINT djcelery_workerstate_hostname_key UNIQUE (hostname);


--
-- Name: djcelery_workerstate_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_workerstate
    ADD CONSTRAINT djcelery_workerstate_pkey PRIMARY KEY (id);


--
-- Name: flows_actionlog_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_actionlog
    ADD CONSTRAINT flows_actionlog_pkey PRIMARY KEY (id);


--
-- Name: flows_actionset_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_pkey PRIMARY KEY (id);


--
-- Name: flows_actionset_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_uuid_key UNIQUE (uuid);


--
-- Name: flows_exportflow_exportflowresultstask_id_394f117d3bdbc9d8_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflow_exportflowresultstask_id_394f117d3bdbc9d8_uniq UNIQUE (exportflowresultstask_id, flow_id);


--
-- Name: flows_exportflowresultstask_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultstask_flows_pkey PRIMARY KEY (id);


--
-- Name: flows_exportflowresultstask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_entry_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_entry_uuid_key UNIQUE (entry_uuid);


--
-- Name: flows_flow_labels_flow_id_72a0bc0c2420ba82_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flow_id_72a0bc0c2420ba82_uniq UNIQUE (flow_id, flowlabel_id);


--
-- Name: flows_flow_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_uuid_1449b94137c010a4_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_uuid_1449b94137c010a4_uniq UNIQUE (uuid);


--
-- Name: flows_flowlabel_name_4348fc61d5223f4e_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_name_4348fc61d5223f4e_uniq UNIQUE (name, parent_id, org_id);


--
-- Name: flows_flowlabel_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrun_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_contacts_flowstart_id_3a4634bf8d96e52_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_flowstart_id_3a4634bf8d96e52_uniq UNIQUE (flowstart_id, contact_id);


--
-- Name: flows_flowstart_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_groups_flowstart_id_73ad868c245b99b7_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_flowstart_id_73ad868c245b99b7_uniq UNIQUE (flowstart_id, contactgroup_id);


--
-- Name: flows_flowstart_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstep_messages_flowstep_id_1c16da1df33fadce_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_flowstep_id_1c16da1df33fadce_uniq UNIQUE (flowstep_id, msg_id);


--
-- Name: flows_flowstep_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstep_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT flows_flowstep_pkey PRIMARY KEY (id);


--
-- Name: flows_flowversion_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT flows_flowversion_pkey PRIMARY KEY (id);


--
-- Name: flows_ruleset_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_pkey PRIMARY KEY (id);


--
-- Name: flows_ruleset_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_uuid_key UNIQUE (uuid);


--
-- Name: guardian_groupobjectpermission_object_pk_1496f467edd78b17_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobjectpermission_object_pk_1496f467edd78b17_uniq UNIQUE (object_pk, group_id, content_type_id, permission_id);


--
-- Name: guardian_groupobjectpermission_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobjectpermission_pkey PRIMARY KEY (id);


--
-- Name: guardian_userobjectpermission_object_pk_4a3e38372084f8ff_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjectpermission_object_pk_4a3e38372084f8ff_uniq UNIQUE (object_pk, user_id, content_type_id, permission_id);


--
-- Name: guardian_userobjectpermission_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjectpermission_pkey PRIMARY KEY (id);


--
-- Name: ivr_ivrcall_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_pkey PRIMARY KEY (id);


--
-- Name: locations_adminboundary_osm_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_osm_id_key UNIQUE (osm_id);


--
-- Name: locations_adminboundary_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_pkey PRIMARY KEY (id);


--
-- Name: locations_boundaryalias_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_contacts_broadcast_id_51c4c2769b6492d2_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_broadcast_id_51c4c2769b6492d2_uniq UNIQUE (broadcast_id, contact_id);


--
-- Name: msgs_broadcast_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_groups_broadcast_id_1983d7ef7345208b_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_broadcast_id_1983d7ef7345208b_uniq UNIQUE (broadcast_id, contactgroup_id);


--
-- Name: msgs_broadcast_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_schedule_id_key UNIQUE (schedule_id);


--
-- Name: msgs_broadcast_urns_broadcast_id_2e61583b1ade1fc9_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_broadcast_id_2e61583b1ade1fc9_uniq UNIQUE (broadcast_id, contacturn_id);


--
-- Name: msgs_broadcast_urns_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_pkey PRIMARY KEY (id);


--
-- Name: msgs_call_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT msgs_call_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportsmstask_groups_exportsmstask_id_44aae5323f00ae25_uni; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportsmstask_groups_exportsmstask_id_44aae5323f00ae25_uni UNIQUE (exportmessagestask_id, contactgroup_id);


--
-- Name: msgs_exportsmstask_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportsmstask_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportsmstask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportsmstask_pkey PRIMARY KEY (id);


--
-- Name: msgs_label_org_id_7ab7f9bb751e78b4_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_org_id_7ab7f9bb751e78b4_uniq UNIQUE (org_id, name);


--
-- Name: msgs_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_pkey PRIMARY KEY (id);


--
-- Name: msgs_label_uuid_7d50eba9220d6f69_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_uuid_7d50eba9220d6f69_uniq UNIQUE (uuid);


--
-- Name: msgs_msg_labels_msgs_id_33bef276d391b5f6_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_msgs_id_33bef276d391b5f6_uniq UNIQUE (msg_id, label_id);


--
-- Name: msgs_msg_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_pkey PRIMARY KEY (id);


--
-- Name: msgs_msg_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_pkey PRIMARY KEY (id);


--
-- Name: orgs_creditalert_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation_secret_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_secret_key UNIQUE (secret);


--
-- Name: orgs_language_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_administrators_org_id_6e45eb894eda5b26_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_org_id_6e45eb894eda5b26_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_administrators_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_editors_org_id_6d6a49e762ecf991_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_org_id_6d6a49e762ecf991_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_editors_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_slug_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_slug_key UNIQUE (slug);


--
-- Name: orgs_org_viewers_org_id_64e1939c6c378b34_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_org_id_64e1939c6c378b34_uniq UNIQUE (org_id, user_id);


--
-- Name: orgs_org_viewers_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_pkey PRIMARY KEY (id);


--
-- Name: orgs_topup_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_pkey PRIMARY KEY (id);


--
-- Name: orgs_usersettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_pkey PRIMARY KEY (id);


--
-- Name: public_lead_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT public_lead_pkey PRIMARY KEY (id);


--
-- Name: public_video_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT public_video_pkey PRIMARY KEY (id);


--
-- Name: reports_report_org_id_6c82d69e44350d9d_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_org_id_6c82d69e44350d9d_uniq UNIQUE (org_id, title);


--
-- Name: reports_report_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_pkey PRIMARY KEY (id);


--
-- Name: schedules_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT schedules_schedule_pkey PRIMARY KEY (id);


--
-- Name: south_migrationhistory_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY south_migrationhistory
    ADD CONSTRAINT south_migrationhistory_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_contacts_trigger_id_758e8a27d88cec7f_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_trigger_id_758e8a27d88cec7f_uniq UNIQUE (trigger_id, contact_id);


--
-- Name: triggers_trigger_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_groups_trigger_id_6737ca64e1c00276_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_trigger_id_6737ca64e1c00276_uniq UNIQUE (trigger_id, contactgroup_id);


--
-- Name: triggers_trigger_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_relayer_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_relayer_id_key UNIQUE (channel_id);


--
-- Name: triggers_trigger_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_schedule_id_key UNIQUE (schedule_id);


--
-- Name: users_failedlogin_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_failedlogin
    ADD CONSTRAINT users_failedlogin_pkey PRIMARY KEY (id);


--
-- Name: users_passwordhistory_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_passwordhistory
    ADD CONSTRAINT users_passwordhistory_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken_token_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_token_key UNIQUE (token);


--
-- Name: values_value_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_pkey PRIMARY KEY (id);


--
-- Name: api_apitoken_key_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_apitoken_key_like ON api_apitoken USING btree (key varchar_pattern_ops);


--
-- Name: api_apitoken_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_apitoken_org_id ON api_apitoken USING btree (org_id);


--
-- Name: api_apitoken_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_apitoken_user_id ON api_apitoken USING btree (user_id);


--
-- Name: api_webhookevent_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_created_by_id ON api_webhookevent USING btree (created_by_id);


--
-- Name: api_webhookevent_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_modified_by_id ON api_webhookevent USING btree (modified_by_id);


--
-- Name: api_webhookevent_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_org_id ON api_webhookevent USING btree (org_id);


--
-- Name: api_webhookevent_relayer_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_relayer_id ON api_webhookevent USING btree (channel_id);


--
-- Name: api_webhookresult_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookresult_created_by_id ON api_webhookresult USING btree (created_by_id);


--
-- Name: api_webhookresult_event_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookresult_event_id ON api_webhookresult USING btree (event_id);


--
-- Name: api_webhookresult_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookresult_modified_by_id ON api_webhookresult USING btree (modified_by_id);


--
-- Name: authtoken_token_key_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX authtoken_token_key_like ON authtoken_token USING btree (key varchar_pattern_ops);


--
-- Name: campaigns_campaign_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_created_by_id ON campaigns_campaign USING btree (created_by_id);


--
-- Name: campaigns_campaign_group_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_group_id ON campaigns_campaign USING btree (group_id);


--
-- Name: campaigns_campaign_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_modified_by_id ON campaigns_campaign USING btree (modified_by_id);


--
-- Name: campaigns_campaign_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_org_id ON campaigns_campaign USING btree (org_id);


--
-- Name: campaigns_campaignevent_campaign_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_campaign_id ON campaigns_campaignevent USING btree (campaign_id);


--
-- Name: campaigns_campaignevent_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_created_by_id ON campaigns_campaignevent USING btree (created_by_id);


--
-- Name: campaigns_campaignevent_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_flow_id ON campaigns_campaignevent USING btree (flow_id);


--
-- Name: campaigns_campaignevent_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_modified_by_id ON campaigns_campaignevent USING btree (modified_by_id);


--
-- Name: campaigns_campaignevent_related_to_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_related_to_id ON campaigns_campaignevent USING btree (relative_to_id);


--
-- Name: campaigns_eventfire_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_eventfire_contact_id ON campaigns_eventfire USING btree (contact_id);


--
-- Name: campaigns_eventfire_event_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_eventfire_event_id ON campaigns_eventfire USING btree (event_id);


--
-- Name: celery_taskmeta_hidden; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_taskmeta_hidden ON celery_taskmeta USING btree (hidden);


--
-- Name: celery_taskmeta_task_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_taskmeta_task_id_like ON celery_taskmeta USING btree (task_id varchar_pattern_ops);


--
-- Name: celery_tasksetmeta_hidden; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_tasksetmeta_hidden ON celery_tasksetmeta USING btree (hidden);


--
-- Name: celery_tasksetmeta_taskset_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_tasksetmeta_taskset_id_like ON celery_tasksetmeta USING btree (taskset_id varchar_pattern_ops);


--
-- Name: channels_alert_channel_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_channel_id ON channels_alert USING btree (channel_id);


--
-- Name: channels_alert_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_created_by_id ON channels_alert USING btree (created_by_id);


--
-- Name: channels_alert_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_modified_by_id ON channels_alert USING btree (modified_by_id);


--
-- Name: channels_alert_sync_event_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_sync_event_id ON channels_alert USING btree (sync_event_id);


--
-- Name: channels_channel_claim_code_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_claim_code_like ON channels_channel USING btree (claim_code varchar_pattern_ops);


--
-- Name: channels_channel_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_created_by_id ON channels_channel USING btree (created_by_id);


--
-- Name: channels_channel_gcm_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_gcm_id_like ON channels_channel USING btree (gcm_id varchar_pattern_ops);


--
-- Name: channels_channel_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_modified_by_id ON channels_channel USING btree (modified_by_id);


--
-- Name: channels_channel_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_org_id ON channels_channel USING btree (org_id);


--
-- Name: channels_channel_parent_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_parent_id ON channels_channel USING btree (parent_id);


--
-- Name: channels_channel_secret_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_secret_like ON channels_channel USING btree (secret varchar_pattern_ops);


--
-- Name: channels_channel_uuid; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_uuid ON channels_channel USING btree (uuid);


--
-- Name: channels_channellog_msgs_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channellog_msgs_id ON channels_channellog USING btree (msg_id);


--
-- Name: channels_syncevent_channel_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_syncevent_channel_id ON channels_syncevent USING btree (channel_id);


--
-- Name: channels_syncevent_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_syncevent_created_by_id ON channels_syncevent USING btree (created_by_id);


--
-- Name: channels_syncevent_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_syncevent_modified_by_id ON channels_syncevent USING btree (modified_by_id);


--
-- Name: contacts_contact_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contact_created_by_id ON contacts_contact USING btree (created_by_id);


--
-- Name: contacts_contact_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contact_modified_by_id ON contacts_contact USING btree (modified_by_id);


--
-- Name: contacts_contact_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contact_org_id ON contacts_contact USING btree (org_id);


--
-- Name: contacts_contactfield_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactfield_org_id ON contacts_contactfield USING btree (org_id);


--
-- Name: contacts_contactgroup_contacts_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_contacts_contact_id ON contacts_contactgroup_contacts USING btree (contact_id);


--
-- Name: contacts_contactgroup_contacts_contactgroup_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_contacts_contactgroup_id ON contacts_contactgroup_contacts USING btree (contactgroup_id);


--
-- Name: contacts_contactgroup_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_created_by_id ON contacts_contactgroup USING btree (created_by_id);


--
-- Name: contacts_contactgroup_import_task_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_import_task_id ON contacts_contactgroup USING btree (import_task_id);


--
-- Name: contacts_contactgroup_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_modified_by_id ON contacts_contactgroup USING btree (modified_by_id);


--
-- Name: contacts_contactgroup_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_org_id ON contacts_contactgroup USING btree (org_id);


--
-- Name: contacts_contactgroup_query_fields_contactfield_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_query_fields_contactfield_id ON contacts_contactgroup_query_fields USING btree (contactfield_id);


--
-- Name: contacts_contactgroup_query_fields_contactgroup_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_query_fields_contactgroup_id ON contacts_contactgroup_query_fields USING btree (contactgroup_id);


--
-- Name: contacts_contacturn_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contacturn_contact_id ON contacts_contacturn USING btree (contact_id);


--
-- Name: contacts_contacturn_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contacturn_org_id ON contacts_contacturn USING btree (org_id);


--
-- Name: contacts_contacturn_relayer_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contacturn_relayer_id ON contacts_contacturn USING btree (channel_id);


--
-- Name: contacts_exportcontactstask_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_created_by_id ON contacts_exportcontactstask USING btree (created_by_id);


--
-- Name: contacts_exportcontactstask_group_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_group_id ON contacts_exportcontactstask USING btree (group_id);


--
-- Name: contacts_exportcontactstask_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_modified_by_id ON contacts_exportcontactstask USING btree (modified_by_id);


--
-- Name: contacts_exportcontactstask_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_org_id ON contacts_exportcontactstask USING btree (org_id);


--
-- Name: csv_imports_importtask_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX csv_imports_importtask_created_by_id ON csv_imports_importtask USING btree (created_by_id);


--
-- Name: csv_imports_importtask_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX csv_imports_importtask_modified_by_id ON csv_imports_importtask USING btree (modified_by_id);


--
-- Name: dashboard_pagerank_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_pagerank_created_by_id ON dashboard_pagerank USING btree (created_by_id);


--
-- Name: dashboard_pagerank_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_pagerank_modified_by_id ON dashboard_pagerank USING btree (modified_by_id);


--
-- Name: dashboard_pagerank_website_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_pagerank_website_id ON dashboard_pagerank USING btree (website_id);


--
-- Name: dashboard_search_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_search_created_by_id ON dashboard_search USING btree (created_by_id);


--
-- Name: dashboard_search_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_search_modified_by_id ON dashboard_search USING btree (modified_by_id);


--
-- Name: dashboard_searchposition_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_searchposition_created_by_id ON dashboard_searchposition USING btree (created_by_id);


--
-- Name: dashboard_searchposition_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_searchposition_modified_by_id ON dashboard_searchposition USING btree (modified_by_id);


--
-- Name: dashboard_searchposition_search_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_searchposition_search_id ON dashboard_searchposition USING btree (search_id);


--
-- Name: dashboard_searchposition_website_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_searchposition_website_id ON dashboard_searchposition USING btree (website_id);


--
-- Name: dashboard_website_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_website_created_by_id ON dashboard_website USING btree (created_by_id);


--
-- Name: dashboard_website_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX dashboard_website_modified_by_id ON dashboard_website USING btree (modified_by_id);


--
-- Name: djcelery_periodictask_crontab_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_periodictask_crontab_id ON djcelery_periodictask USING btree (crontab_id);


--
-- Name: djcelery_periodictask_interval_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_periodictask_interval_id ON djcelery_periodictask USING btree (interval_id);


--
-- Name: djcelery_periodictask_name_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_periodictask_name_like ON djcelery_periodictask USING btree (name varchar_pattern_ops);


--
-- Name: djcelery_taskstate_hidden; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_hidden ON djcelery_taskstate USING btree (hidden);


--
-- Name: djcelery_taskstate_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_name ON djcelery_taskstate USING btree (name);


--
-- Name: djcelery_taskstate_name_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_name_like ON djcelery_taskstate USING btree (name varchar_pattern_ops);


--
-- Name: djcelery_taskstate_state; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_state ON djcelery_taskstate USING btree (state);


--
-- Name: djcelery_taskstate_state_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_state_like ON djcelery_taskstate USING btree (state varchar_pattern_ops);


--
-- Name: djcelery_taskstate_task_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_task_id_like ON djcelery_taskstate USING btree (task_id varchar_pattern_ops);


--
-- Name: djcelery_taskstate_tstamp; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_tstamp ON djcelery_taskstate USING btree (tstamp);


--
-- Name: djcelery_taskstate_worker_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_worker_id ON djcelery_taskstate USING btree (worker_id);


--
-- Name: djcelery_workerstate_hostname_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_workerstate_hostname_like ON djcelery_workerstate USING btree (hostname varchar_pattern_ops);


--
-- Name: djcelery_workerstate_last_heartbeat; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_workerstate_last_heartbeat ON djcelery_workerstate USING btree (last_heartbeat);


--
-- Name: flows_actionlog_run_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_actionlog_run_id ON flows_actionlog USING btree (run_id);


--
-- Name: flows_actionset_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_actionset_flow_id ON flows_actionset USING btree (flow_id);


--
-- Name: flows_actionset_uuid_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_actionset_uuid_like ON flows_actionset USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_exportflowresultstask_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_9cf869aa ON flows_exportflowresultstask USING btree (org_id);


--
-- Name: flows_exportflowresultstask_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_created_by_id ON flows_exportflowresultstask USING btree (created_by_id);


--
-- Name: flows_exportflowresultstask_flows_exportflowresultstask_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_flows_exportflowresultstask_id ON flows_exportflowresultstask_flows USING btree (exportflowresultstask_id);


--
-- Name: flows_exportflowresultstask_flows_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_flows_flow_id ON flows_exportflowresultstask_flows USING btree (flow_id);


--
-- Name: flows_exportflowresultstask_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_modified_by_id ON flows_exportflowresultstask USING btree (modified_by_id);


--
-- Name: flows_flow_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_created_by_id ON flows_flow USING btree (created_by_id);


--
-- Name: flows_flow_entry_uuid_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_entry_uuid_like ON flows_flow USING btree (entry_uuid varchar_pattern_ops);


--
-- Name: flows_flow_labels_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_labels_flow_id ON flows_flow_labels USING btree (flow_id);


--
-- Name: flows_flow_labels_flowlabel_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_labels_flowlabel_id ON flows_flow_labels USING btree (flowlabel_id);


--
-- Name: flows_flow_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_modified_by_id ON flows_flow USING btree (modified_by_id);


--
-- Name: flows_flow_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_org_id ON flows_flow USING btree (org_id);


--
-- Name: flows_flow_saved_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_saved_by_id ON flows_flow USING btree (saved_by_id);


--
-- Name: flows_flowlabel_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowlabel_org_id ON flows_flowlabel USING btree (org_id);


--
-- Name: flows_flowlabel_parent_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowlabel_parent_id ON flows_flowlabel USING btree (parent_id);


--
-- Name: flows_flowrun_call_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_call_id ON flows_flowrun USING btree (call_id);


--
-- Name: flows_flowrun_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_contact_id ON flows_flowrun USING btree (contact_id);


--
-- Name: flows_flowrun_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_flow_id ON flows_flowrun USING btree (flow_id);


--
-- Name: flows_flowrun_start_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_start_id ON flows_flowrun USING btree (start_id);


--
-- Name: flows_flowstart_contacts_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_contacts_contact_id ON flows_flowstart_contacts USING btree (contact_id);


--
-- Name: flows_flowstart_contacts_flowstart_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_contacts_flowstart_id ON flows_flowstart_contacts USING btree (flowstart_id);


--
-- Name: flows_flowstart_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_created_by_id ON flows_flowstart USING btree (created_by_id);


--
-- Name: flows_flowstart_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_flow_id ON flows_flowstart USING btree (flow_id);


--
-- Name: flows_flowstart_groups_contactgroup_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_groups_contactgroup_id ON flows_flowstart_groups USING btree (contactgroup_id);


--
-- Name: flows_flowstart_groups_flowstart_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_groups_flowstart_id ON flows_flowstart_groups USING btree (flowstart_id);


--
-- Name: flows_flowstart_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_modified_by_id ON flows_flowstart USING btree (modified_by_id);


--
-- Name: flows_flowstep_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_contact_id ON flows_flowstep USING btree (contact_id);


--
-- Name: flows_flowstep_left_on; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_left_on ON flows_flowstep USING btree (left_on);


--
-- Name: flows_flowstep_messages_flowstep_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_messages_flowstep_id ON flows_flowstep_messages USING btree (flowstep_id);


--
-- Name: flows_flowstep_messages_msgs_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_messages_msgs_id ON flows_flowstep_messages USING btree (msg_id);


--
-- Name: flows_flowstep_run_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_run_id ON flows_flowstep USING btree (run_id);


--
-- Name: flows_flowstep_step_next_left_null_rule; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_step_next_left_null_rule ON flows_flowstep USING btree (step_uuid, next_uuid, left_on) WHERE (rule_uuid IS NULL);


--
-- Name: flows_flowstep_step_next_rule_left; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_step_next_rule_left ON flows_flowstep USING btree (step_uuid, next_uuid, rule_uuid, left_on);


--
-- Name: flows_flowstep_step_uuid; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_step_uuid ON flows_flowstep USING btree (step_uuid);


--
-- Name: flows_flowversion_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowversion_created_by_id ON flows_flowversion USING btree (created_by_id);


--
-- Name: flows_flowversion_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowversion_flow_id ON flows_flowversion USING btree (flow_id);


--
-- Name: flows_flowversion_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowversion_modified_by_id ON flows_flowversion USING btree (modified_by_id);


--
-- Name: flows_ruleset_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_ruleset_flow_id ON flows_ruleset USING btree (flow_id);


--
-- Name: flows_ruleset_uuid_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_ruleset_uuid_like ON flows_ruleset USING btree (uuid varchar_pattern_ops);


--
-- Name: guardian_groupobjectpermission_content_type_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_groupobjectpermission_content_type_id ON guardian_groupobjectpermission USING btree (content_type_id);


--
-- Name: guardian_groupobjectpermission_group_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_groupobjectpermission_group_id ON guardian_groupobjectpermission USING btree (group_id);


--
-- Name: guardian_groupobjectpermission_permission_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_groupobjectpermission_permission_id ON guardian_groupobjectpermission USING btree (permission_id);


--
-- Name: guardian_userobjectpermission_content_type_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_userobjectpermission_content_type_id ON guardian_userobjectpermission USING btree (content_type_id);


--
-- Name: guardian_userobjectpermission_permission_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_userobjectpermission_permission_id ON guardian_userobjectpermission USING btree (permission_id);


--
-- Name: guardian_userobjectpermission_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_userobjectpermission_user_id ON guardian_userobjectpermission USING btree (user_id);


--
-- Name: ivr_ivrcall_842dde28; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_842dde28 ON ivr_ivrcall USING btree (contact_urn_id);


--
-- Name: ivr_ivrcall_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_contact_id ON ivr_ivrcall USING btree (contact_id);


--
-- Name: ivr_ivrcall_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_created_by_id ON ivr_ivrcall USING btree (created_by_id);


--
-- Name: ivr_ivrcall_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_flow_id ON ivr_ivrcall USING btree (flow_id);


--
-- Name: ivr_ivrcall_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_modified_by_id ON ivr_ivrcall USING btree (modified_by_id);


--
-- Name: ivr_ivrcall_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_org_id ON ivr_ivrcall USING btree (org_id);


--
-- Name: ivr_ivrcall_relayer_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_relayer_id ON ivr_ivrcall USING btree (channel_id);


--
-- Name: locations_adminboundary_geometry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_geometry_id ON locations_adminboundary USING gist (geometry);


--
-- Name: locations_adminboundary_osm_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_osm_id_like ON locations_adminboundary USING btree (osm_id varchar_pattern_ops);


--
-- Name: locations_adminboundary_parent_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_parent_id ON locations_adminboundary USING btree (parent_id);


--
-- Name: locations_adminboundary_simplified_geometry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_simplified_geometry_id ON locations_adminboundary USING gist (simplified_geometry);


--
-- Name: locations_boundaryalias_boundary_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_boundary_id ON locations_boundaryalias USING btree (boundary_id);


--
-- Name: locations_boundaryalias_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_created_by_id ON locations_boundaryalias USING btree (created_by_id);


--
-- Name: locations_boundaryalias_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_modified_by_id ON locations_boundaryalias USING btree (modified_by_id);


--
-- Name: locations_boundaryalias_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_org_id ON locations_boundaryalias USING btree (org_id);


--
-- Name: msg_visibility_direction_type_created_inbound; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msg_visibility_direction_type_created_inbound ON msgs_msg USING btree (org_id, visibility, direction, msg_type, created_on DESC) WHERE ((direction)::text = 'I'::text);


--
-- Name: msgs_broadcast_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_72eb6c85 ON msgs_broadcast USING btree (channel_id);


--
-- Name: msgs_broadcast_contacts_broadcast_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_contacts_broadcast_id ON msgs_broadcast_contacts USING btree (broadcast_id);


--
-- Name: msgs_broadcast_contacts_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_contacts_contact_id ON msgs_broadcast_contacts USING btree (contact_id);


--
-- Name: msgs_broadcast_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_created_by_id ON msgs_broadcast USING btree (created_by_id);


--
-- Name: msgs_broadcast_created_on; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_created_on ON msgs_broadcast USING btree (created_on);


--
-- Name: msgs_broadcast_groups_broadcast_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_groups_broadcast_id ON msgs_broadcast_groups USING btree (broadcast_id);


--
-- Name: msgs_broadcast_groups_contactgroup_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_groups_contactgroup_id ON msgs_broadcast_groups USING btree (contactgroup_id);


--
-- Name: msgs_broadcast_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_modified_by_id ON msgs_broadcast USING btree (modified_by_id);


--
-- Name: msgs_broadcast_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_org_id ON msgs_broadcast USING btree (org_id);


--
-- Name: msgs_broadcast_parent_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_parent_id ON msgs_broadcast USING btree (parent_id);


--
-- Name: msgs_broadcast_urns_broadcast_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_urns_broadcast_id ON msgs_broadcast_urns USING btree (broadcast_id);


--
-- Name: msgs_broadcast_urns_contacturn_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_urns_contacturn_id ON msgs_broadcast_urns USING btree (contacturn_id);


--
-- Name: msgs_call_channel_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_channel_id ON msgs_call USING btree (channel_id);


--
-- Name: msgs_call_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_contact_id ON msgs_call USING btree (contact_id);


--
-- Name: msgs_call_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_created_by_id ON msgs_call USING btree (created_by_id);


--
-- Name: msgs_call_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_modified_by_id ON msgs_call USING btree (modified_by_id);


--
-- Name: msgs_call_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_org_id ON msgs_call USING btree (org_id);


--
-- Name: msgs_exportsmstask_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportsmstask_created_by_id ON msgs_exportmessagestask USING btree (created_by_id);


--
-- Name: msgs_exportsmstask_groups_contactgroup_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportsmstask_groups_contactgroup_id ON msgs_exportmessagestask_groups USING btree (contactgroup_id);


--
-- Name: msgs_exportsmstask_groups_exportsmstask_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportsmstask_groups_exportsmstask_id ON msgs_exportmessagestask_groups USING btree (exportmessagestask_id);


--
-- Name: msgs_exportsmstask_label_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportsmstask_label_id ON msgs_exportmessagestask USING btree (label_id);


--
-- Name: msgs_exportsmstask_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportsmstask_modified_by_id ON msgs_exportmessagestask USING btree (modified_by_id);


--
-- Name: msgs_exportsmstask_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportsmstask_org_id ON msgs_exportmessagestask USING btree (org_id);


--
-- Name: msgs_label_a8a44dbb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_a8a44dbb ON msgs_label USING btree (folder_id);


--
-- Name: msgs_label_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_b3da0983 ON msgs_label USING btree (modified_by_id);


--
-- Name: msgs_label_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_e93cb7eb ON msgs_label USING btree (created_by_id);


--
-- Name: msgs_label_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_org_id ON msgs_label USING btree (org_id);


--
-- Name: msgs_msg_broadcast_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_broadcast_id ON msgs_msg USING btree (broadcast_id);


--
-- Name: msgs_msg_channel_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_channel_id ON msgs_msg USING btree (channel_id);


--
-- Name: msgs_msg_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_contact_id ON msgs_msg USING btree (contact_id);


--
-- Name: msgs_msg_contact_urn_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_contact_urn_id ON msgs_msg USING btree (contact_urn_id);


--
-- Name: msgs_msg_created_on; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_created_on ON msgs_msg USING btree (created_on);


--
-- Name: msgs_msg_external_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_external_id ON msgs_msg USING btree (external_id);


--
-- Name: msgs_msg_labels_label_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_labels_label_id ON msgs_msg_labels USING btree (label_id);


--
-- Name: msgs_msg_labels_msgs_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_labels_msgs_id ON msgs_msg_labels USING btree (msg_id);


--
-- Name: msgs_msg_org_failed_created_on; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_org_failed_created_on ON msgs_msg USING btree (org_id, direction, visibility, created_on DESC) WHERE ((status)::text = 'F'::text);


--
-- Name: msgs_msg_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_org_id ON msgs_msg USING btree (org_id);


--
-- Name: msgs_msg_response_to_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_response_to_id ON msgs_msg USING btree (response_to_id);


--
-- Name: msgs_msg_status; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_status ON msgs_msg USING btree (status);


--
-- Name: msgs_msg_topup_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_topup_id ON msgs_msg USING btree (topup_id);


--
-- Name: msgs_msg_visibility; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_visibility ON msgs_msg USING btree (visibility);


--
-- Name: orgs_creditalert_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_creditalert_created_by_id ON orgs_creditalert USING btree (created_by_id);


--
-- Name: orgs_creditalert_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_creditalert_modified_by_id ON orgs_creditalert USING btree (modified_by_id);


--
-- Name: orgs_creditalert_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_creditalert_org_id ON orgs_creditalert USING btree (org_id);


--
-- Name: orgs_invitation_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_created_by_id ON orgs_invitation USING btree (created_by_id);


--
-- Name: orgs_invitation_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_modified_by_id ON orgs_invitation USING btree (modified_by_id);


--
-- Name: orgs_invitation_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_org_id ON orgs_invitation USING btree (org_id);


--
-- Name: orgs_invitation_secret_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_secret_like ON orgs_invitation USING btree (secret varchar_pattern_ops);


--
-- Name: orgs_language_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_language_created_by_id ON orgs_language USING btree (created_by_id);


--
-- Name: orgs_language_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_language_modified_by_id ON orgs_language USING btree (modified_by_id);


--
-- Name: orgs_language_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_language_org_id ON orgs_language USING btree (org_id);


--
-- Name: orgs_org_administrators_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_administrators_org_id ON orgs_org_administrators USING btree (org_id);


--
-- Name: orgs_org_administrators_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_administrators_user_id ON orgs_org_administrators USING btree (user_id);


--
-- Name: orgs_org_country_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_country_id ON orgs_org USING btree (country_id);


--
-- Name: orgs_org_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_created_by_id ON orgs_org USING btree (created_by_id);


--
-- Name: orgs_org_editors_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_editors_org_id ON orgs_org_editors USING btree (org_id);


--
-- Name: orgs_org_editors_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_editors_user_id ON orgs_org_editors USING btree (user_id);


--
-- Name: orgs_org_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_modified_by_id ON orgs_org USING btree (modified_by_id);


--
-- Name: orgs_org_name_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_name_like ON orgs_org USING btree (name varchar_pattern_ops);


--
-- Name: orgs_org_primary_language_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_primary_language_id ON orgs_org USING btree (primary_language_id);


--
-- Name: orgs_org_slug_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_slug_like ON orgs_org USING btree (slug varchar_pattern_ops);


--
-- Name: orgs_org_viewers_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_viewers_org_id ON orgs_org_viewers USING btree (org_id);


--
-- Name: orgs_org_viewers_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_viewers_user_id ON orgs_org_viewers USING btree (user_id);


--
-- Name: orgs_topup_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_topup_created_by_id ON orgs_topup USING btree (created_by_id);


--
-- Name: orgs_topup_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_topup_modified_by_id ON orgs_topup USING btree (modified_by_id);


--
-- Name: orgs_topup_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_topup_org_id ON orgs_topup USING btree (org_id);


--
-- Name: orgs_usersettings_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_usersettings_user_id ON orgs_usersettings USING btree (user_id);


--
-- Name: public_lead_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_lead_created_by_id ON public_lead USING btree (created_by_id);


--
-- Name: public_lead_email_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_lead_email_like ON public_lead USING btree (email varchar_pattern_ops);


--
-- Name: public_lead_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_lead_modified_by_id ON public_lead USING btree (modified_by_id);


--
-- Name: public_video_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_video_created_by_id ON public_video USING btree (created_by_id);


--
-- Name: public_video_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_video_modified_by_id ON public_video USING btree (modified_by_id);


--
-- Name: reports_report_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX reports_report_created_by_id ON reports_report USING btree (created_by_id);


--
-- Name: reports_report_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX reports_report_modified_by_id ON reports_report USING btree (modified_by_id);


--
-- Name: reports_report_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX reports_report_org_id ON reports_report USING btree (org_id);


--
-- Name: schedules_schedule_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX schedules_schedule_created_by_id ON schedules_schedule USING btree (created_by_id);


--
-- Name: schedules_schedule_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX schedules_schedule_modified_by_id ON schedules_schedule USING btree (modified_by_id);


--
-- Name: triggers_trigger_contacts_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_contacts_contact_id ON triggers_trigger_contacts USING btree (contact_id);


--
-- Name: triggers_trigger_contacts_trigger_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_contacts_trigger_id ON triggers_trigger_contacts USING btree (trigger_id);


--
-- Name: triggers_trigger_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_created_by_id ON triggers_trigger USING btree (created_by_id);


--
-- Name: triggers_trigger_flow_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_flow_id ON triggers_trigger USING btree (flow_id);


--
-- Name: triggers_trigger_groups_contactgroup_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_groups_contactgroup_id ON triggers_trigger_groups USING btree (contactgroup_id);


--
-- Name: triggers_trigger_groups_trigger_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_groups_trigger_id ON triggers_trigger_groups USING btree (trigger_id);


--
-- Name: triggers_trigger_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_modified_by_id ON triggers_trigger USING btree (modified_by_id);


--
-- Name: triggers_trigger_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_org_id ON triggers_trigger USING btree (org_id);


--
-- Name: values_value_contact_field_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_contact_field_id ON values_value USING btree (contact_field_id);


--
-- Name: values_value_contact_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_contact_id ON values_value USING btree (contact_id);


--
-- Name: values_value_location_value_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_location_value_id ON values_value USING btree (location_value_id);


--
-- Name: values_value_org_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_org_id ON values_value USING btree (org_id);


--
-- Name: values_value_rule_uuid_76ab85922190b184_uniq; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_rule_uuid_76ab85922190b184_uniq ON values_value USING btree (rule_uuid);


--
-- Name: values_value_ruleset_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_ruleset_id ON values_value USING btree (ruleset_id);


--
-- Name: values_value_run_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_run_id ON values_value USING btree (run_id);


--
-- Name: contact_check_update_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contact_check_update_trg BEFORE UPDATE ON contacts_contact FOR EACH ROW EXECUTE PROCEDURE contact_check_update();


--
-- Name: when_contact_groups_changed_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contact_groups_changed_then_update_count_trg AFTER INSERT OR DELETE ON contacts_contactgroup_contacts FOR EACH ROW EXECUTE PROCEDURE update_group_count();


--
-- Name: when_contact_groups_truncate_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contact_groups_truncate_then_update_count_trg AFTER TRUNCATE ON contacts_contactgroup_contacts FOR EACH STATEMENT EXECUTE PROCEDURE update_group_count();


--
-- Name: when_contacts_changed_then_update_groups_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contacts_changed_then_update_groups_trg AFTER INSERT OR UPDATE ON contacts_contact FOR EACH ROW EXECUTE PROCEDURE update_contact_system_groups();


--
-- Name: when_label_inserted_or_deleted_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_label_inserted_or_deleted_then_update_count_trg AFTER INSERT OR DELETE ON msgs_msg_labels FOR EACH ROW EXECUTE PROCEDURE update_label_count();


--
-- Name: when_labels_truncated_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_labels_truncated_then_update_count_trg AFTER TRUNCATE ON msgs_msg_labels FOR EACH STATEMENT EXECUTE PROCEDURE update_label_count();


--
-- Name: when_msg_updated_then_update_label_counts_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_msg_updated_then_update_label_counts_trg AFTER UPDATE OF visibility ON msgs_msg FOR EACH ROW EXECUTE PROCEDURE update_msg_user_label_counts();


--
-- Name: when_msgs_truncate_then_update_topup_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_msgs_truncate_then_update_topup_trg AFTER TRUNCATE ON msgs_msg FOR EACH STATEMENT EXECUTE PROCEDURE update_topup_used();


--
-- Name: when_msgs_update_then_update_topup_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_msgs_update_then_update_topup_trg AFTER INSERT OR DELETE OR UPDATE OF topup_id ON msgs_msg FOR EACH ROW EXECUTE PROCEDURE update_topup_used();


--
-- Name: auth_group_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: boundary_id_refs_id_062fa703; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT boundary_id_refs_id_062fa703 FOREIGN KEY (boundary_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: broadcast_id_refs_id_13be1a0f4ee207d5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT broadcast_id_refs_id_13be1a0f4ee207d5 FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: broadcast_id_refs_id_1bbfd8e1ec515cd5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT broadcast_id_refs_id_1bbfd8e1ec515cd5 FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: broadcast_id_refs_id_7462bf3acc906426; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT broadcast_id_refs_id_7462bf3acc906426 FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: broadcast_id_refs_id_c7953a11; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT broadcast_id_refs_id_c7953a11 FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: call_id_refs_id_104929674b9f5123; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT call_id_refs_id_104929674b9f5123 FOREIGN KEY (call_id) REFERENCES ivr_ivrcall(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaign_id_refs_id_5ef97c1b243bb46a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaign_id_refs_id_5ef97c1b243bb46a FOREIGN KEY (campaign_id) REFERENCES campaigns_campaign(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: co_contactgroup_id_278c502545b43b84_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT co_contactgroup_id_278c502545b43b84_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_field_id_refs_id_df7dbdfb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT contact_field_id_refs_id_df7dbdfb FOREIGN KEY (contact_field_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_1ee8f54bcc3f0a7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT contact_id_refs_id_1ee8f54bcc3f0a7a FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_24d6c21dc4c10347; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT contact_id_refs_id_24d6c21dc4c10347 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_284700c8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT contact_id_refs_id_284700c8 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_3504f414fb9060a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT contact_id_refs_id_3504f414fb9060a6 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_399b7589345b1f53; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT contact_id_refs_id_399b7589345b1f53 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_609f248a3c6913eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT contact_id_refs_id_609f248a3c6913eb FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_6e9c2b0dcfa57ce6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT contact_id_refs_id_6e9c2b0dcfa57ce6 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_784bbb50e698dd81; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT contact_id_refs_id_784bbb50e698dd81 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_7c45d84b3c4134e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contact_id_refs_id_7c45d84b3c4134e1 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_7d643581aa860347; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT contact_id_refs_id_7d643581aa860347 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_id_refs_id_93ca1165; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT contact_id_refs_id_93ca1165 FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_urn_id_refs_id_3f13a05a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT contact_urn_id_refs_id_3f13a05a FOREIGN KEY (contact_urn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contactfield_id_refs_id_eacf313f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contactfield_id_refs_id_eacf313f FOREIGN KEY (contactfield_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contactgroup_id_refs_id_14343436daae0938; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT contactgroup_id_refs_id_14343436daae0938 FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contactgroup_id_refs_id_2e6637e835080d9d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT contactgroup_id_refs_id_2e6637e835080d9d FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contactgroup_id_refs_id_5255cfea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT contactgroup_id_refs_id_5255cfea FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contactgroup_id_refs_id_b63844cf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contactgroup_id_refs_id_b63844cf FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contactgroup_id_refs_id_ca66cb90b113da1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT contactgroup_id_refs_id_ca66cb90b113da1 FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_cont_contact_id_1dee76983891f9e_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_cont_contact_id_1dee76983891f9e_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_org_id_4c569ecced215497_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_org_id_4c569ecced215497_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacturn_id_refs_id_024d0fed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT contacturn_id_refs_id_024d0fed FOREIGN KEY (contacturn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: content_type_id_refs_id_41c07efb11cb62e8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT content_type_id_refs_id_41c07efb11cb62e8 FOREIGN KEY (content_type_id) REFERENCES django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: content_type_id_refs_id_478017b6b7357933; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT content_type_id_refs_id_478017b6b7357933 FOREIGN KEY (content_type_id) REFERENCES django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: content_type_id_refs_id_d043b34a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT content_type_id_refs_id_d043b34a FOREIGN KEY (content_type_id) REFERENCES django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: country_id_refs_id_803e28ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT country_id_refs_id_803e28ef FOREIGN KEY (country_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_10c0e57cc7a79728; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask
    ADD CONSTRAINT created_by_id_refs_id_10c0e57cc7a79728 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_2000d84de6e18a85; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_website
    ADD CONSTRAINT created_by_id_refs_id_2000d84de6e18a85 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_3168bd8e280b4816; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_pagerank
    ADD CONSTRAINT created_by_id_refs_id_3168bd8e280b4816 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_31b453568c583e3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT created_by_id_refs_id_31b453568c583e3b FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_3357779d12137f23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT created_by_id_refs_id_3357779d12137f23 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_344c4dc08d4e79c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT created_by_id_refs_id_344c4dc08d4e79c0 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_3487a6041ca2c1c9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_search
    ADD CONSTRAINT created_by_id_refs_id_3487a6041ca2c1c9 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_34a43cfe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT created_by_id_refs_id_34a43cfe FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_3fda08273ed4ff50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT created_by_id_refs_id_3fda08273ed4ff50 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_423bcb531ab5992b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT created_by_id_refs_id_423bcb531ab5992b FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_4276a924acd5cf9e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT created_by_id_refs_id_4276a924acd5cf9e FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_43bd750ae51a4aaa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT created_by_id_refs_id_43bd750ae51a4aaa FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_46995b61b9b84e2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT created_by_id_refs_id_46995b61b9b84e2e FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_470c2ab12f360eb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT created_by_id_refs_id_470c2ab12f360eb3 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_488a9013a6b2ac3a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_searchposition
    ADD CONSTRAINT created_by_id_refs_id_488a9013a6b2ac3a FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_496f1d51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT created_by_id_refs_id_496f1d51 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_4994a5332759a8e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT created_by_id_refs_id_4994a5332759a8e1 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_4a4c89d8e8271552; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT created_by_id_refs_id_4a4c89d8e8271552 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_524adb83be426aba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT created_by_id_refs_id_524adb83be426aba FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_5cedf4f88dca8b6c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT created_by_id_refs_id_5cedf4f88dca8b6c FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_6017a21a4524280; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT created_by_id_refs_id_6017a21a4524280 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_64aa357a9e00be32; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT created_by_id_refs_id_64aa357a9e00be32 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_6a09878553db6cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT created_by_id_refs_id_6a09878553db6cc FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_7011f13b2145170a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT created_by_id_refs_id_7011f13b2145170a FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_7123d39572809d86; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT created_by_id_refs_id_7123d39572809d86 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_774b6611a97a423a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT created_by_id_refs_id_774b6611a97a423a FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_7d242c12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT created_by_id_refs_id_7d242c12 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_8de76f8914b53e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT created_by_id_refs_id_8de76f8914b53e2 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_a6ca7cd4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT created_by_id_refs_id_a6ca7cd4 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_b07adadc347b29f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT created_by_id_refs_id_b07adadc347b29f FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_b761c265231ecce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT created_by_id_refs_id_b761c265231ecce FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_d504ff00; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT created_by_id_refs_id_d504ff00 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_e1394ac5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT created_by_id_refs_id_e1394ac5 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: created_by_id_refs_id_fe4ab50969265b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT created_by_id_refs_id_fe4ab50969265b0 FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: crontab_id_refs_id_2c92a393ebff5e74; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT crontab_id_refs_id_2c92a393ebff5e74 FOREIGN KEY (crontab_id) REFERENCES djcelery_crontabschedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: event_id_refs_id_13bd3f5c45a36a6b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT event_id_refs_id_13bd3f5c45a36a6b FOREIGN KEY (event_id) REFERENCES campaigns_campaignevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: event_id_refs_id_645b9ebb8ed7cc8b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT event_id_refs_id_645b9ebb8ed7cc8b FOREIGN KEY (event_id) REFERENCES api_webhookevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: exportflowresultstask_id_refs_id_3759edfabd6946d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT exportflowresultstask_id_refs_id_3759edfabd6946d7 FOREIGN KEY (exportflowresultstask_id) REFERENCES flows_exportflowresultstask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: exportsmstask_id_refs_id_6dde0a03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT exportsmstask_id_refs_id_6dde0a03 FOREIGN KEY (exportmessagestask_id) REFERENCES msgs_exportmessagestask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_13679e3038c0556d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT flow_id_refs_id_13679e3038c0556d FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_16a5e8b5cd5f9a7d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flow_id_refs_id_16a5e8b5cd5f9a7d FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_1a7c48188e66de2a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flow_id_refs_id_1a7c48188e66de2a FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_2b7e88c902122680; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT flow_id_refs_id_2b7e88c902122680 FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_34e5dc5bca2b90f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flow_id_refs_id_34e5dc5bca2b90f0 FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_6ebba82a1862669; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT flow_id_refs_id_6ebba82a1862669 FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_7fc1316c73377e59; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flow_id_refs_id_7fc1316c73377e59 FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_af5e3e61595ec2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flow_id_refs_id_af5e3e61595ec2e FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_d89d09e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flow_id_refs_id_d89d09e1 FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flow_id_refs_id_eec911e8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT flow_id_refs_id_eec911e8 FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flowlabel_id_refs_id_76fdbb7d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flowlabel_id_refs_id_76fdbb7d FOREIGN KEY (flowlabel_id) REFERENCES flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultst_org_id_687d004b88c4a95d_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultst_org_id_687d004b88c4a95d_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flowstart_id_refs_id_149c72fcc464f547; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flowstart_id_refs_id_149c72fcc464f547 FOREIGN KEY (flowstart_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flowstart_id_refs_id_52e7786b42d0f432; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flowstart_id_refs_id_52e7786b42d0f432 FOREIGN KEY (flowstart_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flowstep_id_refs_id_62dfbfb72af3f8a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flowstep_id_refs_id_62dfbfb72af3f8a7 FOREIGN KEY (flowstep_id) REFERENCES flows_flowstep(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: group_id_refs_id_1d1dde31576d4670; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT group_id_refs_id_1d1dde31576d4670 FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: group_id_refs_id_6dbdd41c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT group_id_refs_id_6dbdd41c FOREIGN KEY (group_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: group_id_refs_id_7c00c136f3a7aa27; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT group_id_refs_id_7c00c136f3a7aa27 FOREIGN KEY (group_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: group_id_refs_id_f4b32aac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT group_id_refs_id_f4b32aac FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: import_task_id_refs_id_129e1c5e8f7834f3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT import_task_id_refs_id_129e1c5e8f7834f3 FOREIGN KEY (import_task_id) REFERENCES csv_imports_importtask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: interval_id_refs_id_672c7616f2054349; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT interval_id_refs_id_672c7616f2054349 FOREIGN KEY (interval_id) REFERENCES djcelery_intervalschedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_i_contact_urn_id_2084cbe146270b65_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_i_contact_urn_id_2084cbe146270b65_fk_contacts_contacturn_id FOREIGN KEY (contact_urn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: label_id_refs_id_6916c8fb8329be69; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT label_id_refs_id_6916c8fb8329be69 FOREIGN KEY (label_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: label_id_refs_id_73b41ef0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT label_id_refs_id_73b41ef0 FOREIGN KEY (label_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: location_value_id_refs_id_09e0d5e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT location_value_id_refs_id_09e0d5e1 FOREIGN KEY (location_value_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_10c0e57cc7a79728; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask
    ADD CONSTRAINT modified_by_id_refs_id_10c0e57cc7a79728 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_2000d84de6e18a85; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_website
    ADD CONSTRAINT modified_by_id_refs_id_2000d84de6e18a85 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_3168bd8e280b4816; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_pagerank
    ADD CONSTRAINT modified_by_id_refs_id_3168bd8e280b4816 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_31b453568c583e3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT modified_by_id_refs_id_31b453568c583e3b FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_3357779d12137f23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT modified_by_id_refs_id_3357779d12137f23 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_344c4dc08d4e79c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT modified_by_id_refs_id_344c4dc08d4e79c0 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_3487a6041ca2c1c9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_search
    ADD CONSTRAINT modified_by_id_refs_id_3487a6041ca2c1c9 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_34a43cfe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT modified_by_id_refs_id_34a43cfe FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_3fda08273ed4ff50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT modified_by_id_refs_id_3fda08273ed4ff50 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_423bcb531ab5992b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT modified_by_id_refs_id_423bcb531ab5992b FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_4276a924acd5cf9e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT modified_by_id_refs_id_4276a924acd5cf9e FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_43bd750ae51a4aaa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT modified_by_id_refs_id_43bd750ae51a4aaa FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_46995b61b9b84e2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT modified_by_id_refs_id_46995b61b9b84e2e FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_470c2ab12f360eb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT modified_by_id_refs_id_470c2ab12f360eb3 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_488a9013a6b2ac3a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_searchposition
    ADD CONSTRAINT modified_by_id_refs_id_488a9013a6b2ac3a FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_496f1d51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT modified_by_id_refs_id_496f1d51 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_4994a5332759a8e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT modified_by_id_refs_id_4994a5332759a8e1 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_4a4c89d8e8271552; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT modified_by_id_refs_id_4a4c89d8e8271552 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_524adb83be426aba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT modified_by_id_refs_id_524adb83be426aba FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_5cedf4f88dca8b6c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT modified_by_id_refs_id_5cedf4f88dca8b6c FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_6017a21a4524280; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT modified_by_id_refs_id_6017a21a4524280 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_64aa357a9e00be32; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT modified_by_id_refs_id_64aa357a9e00be32 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_6a09878553db6cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT modified_by_id_refs_id_6a09878553db6cc FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_7011f13b2145170a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT modified_by_id_refs_id_7011f13b2145170a FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_7123d39572809d86; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT modified_by_id_refs_id_7123d39572809d86 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_774b6611a97a423a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT modified_by_id_refs_id_774b6611a97a423a FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_7d242c12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT modified_by_id_refs_id_7d242c12 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_8de76f8914b53e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT modified_by_id_refs_id_8de76f8914b53e2 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_a6ca7cd4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT modified_by_id_refs_id_a6ca7cd4 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_b07adadc347b29f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT modified_by_id_refs_id_b07adadc347b29f FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_b761c265231ecce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT modified_by_id_refs_id_b761c265231ecce FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_d504ff00; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT modified_by_id_refs_id_d504ff00 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_e1394ac5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT modified_by_id_refs_id_e1394ac5 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: modified_by_id_refs_id_fe4ab50969265b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT modified_by_id_refs_id_fe4ab50969265b0 FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadca_channel_id_20eff13de920a190_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadca_channel_id_20eff13de920a190_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label_created_by_id_fcd217a496d61b5_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_created_by_id_fcd217a496d61b5_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label_folder_id_1fe88e1f66fca0b9_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_folder_id_1fe88e1f66fca0b9_fk_msgs_label_id FOREIGN KEY (folder_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label_modified_by_id_17b1c8500c7961a1_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_modified_by_id_17b1c8500c7961a1_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_08cd3dce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT org_id_refs_id_08cd3dce FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_1724be74; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT org_id_refs_id_1724be74 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_17a2c18cdf4cf271; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT org_id_refs_id_17a2c18cdf4cf271 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_24f46abdb08c603e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT org_id_refs_id_24f46abdb08c603e FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_2d6992068197fc39; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT org_id_refs_id_2d6992068197fc39 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_307a5e04fe37123b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT org_id_refs_id_307a5e04fe37123b FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_332e45d81ba9271d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT org_id_refs_id_332e45d81ba9271d FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_38123a03059f94b9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT org_id_refs_id_38123a03059f94b9 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_3cdf661e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT org_id_refs_id_3cdf661e FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_41686d2989a6f1ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT org_id_refs_id_41686d2989a6f1ac FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_42a499a3fbc82f3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT org_id_refs_id_42a499a3fbc82f3d FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_4889ed1e172d5a6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT org_id_refs_id_4889ed1e172d5a6d FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_4e0ad1b143284e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT org_id_refs_id_4e0ad1b143284e1 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_4ff3b50d5e3642ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT org_id_refs_id_4ff3b50d5e3642ed FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_5100f9430bb89aa1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT org_id_refs_id_5100f9430bb89aa1 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_5462677619ea3ebc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT org_id_refs_id_5462677619ea3ebc FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_54d54d2b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT org_id_refs_id_54d54d2b FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_6357287ec09f1fe7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT org_id_refs_id_6357287ec09f1fe7 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_65d150fc1504ec2b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT org_id_refs_id_65d150fc1504ec2b FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_678f9b66ee4fc79; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT org_id_refs_id_678f9b66ee4fc79 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_6b782c6f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT org_id_refs_id_6b782c6f FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_6edf00c01955e73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT org_id_refs_id_6edf00c01955e73 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_74ecf77b27d76207; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT org_id_refs_id_74ecf77b27d76207 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_87792018f4b9f69; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT org_id_refs_id_87792018f4b9f69 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_af6eb9c2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT org_id_refs_id_af6eb9c2 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_cf8f98eced9c76a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT org_id_refs_id_cf8f98eced9c76a FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: org_id_refs_id_f101c665; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT org_id_refs_id_f101c665 FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: parent_id_refs_id_076599a3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT parent_id_refs_id_076599a3 FOREIGN KEY (parent_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: parent_id_refs_id_4e8db3b1d86baa49; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT parent_id_refs_id_4e8db3b1d86baa49 FOREIGN KEY (parent_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: parent_id_refs_id_9b4c175d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT parent_id_refs_id_9b4c175d FOREIGN KEY (parent_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: parent_id_refs_id_d16c3aa6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT parent_id_refs_id_d16c3aa6 FOREIGN KEY (parent_id) REFERENCES flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: permission_id_refs_id_4d2ad9935b560df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT permission_id_refs_id_4d2ad9935b560df FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: permission_id_refs_id_6b69e5b38352772a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT permission_id_refs_id_6b69e5b38352772a FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: primary_language_id_refs_id_a770813d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT primary_language_id_refs_id_a770813d FOREIGN KEY (primary_language_id) REFERENCES orgs_language(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: related_to_id_refs_id_46269ba16cec53c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT related_to_id_refs_id_46269ba16cec53c5 FOREIGN KEY (relative_to_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_15db4e071fdd509b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT relayer_id_refs_id_15db4e071fdd509b FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_2ccb4cd38ac61f37; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT relayer_id_refs_id_2ccb4cd38ac61f37 FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_4fa37a4a71ff7aa5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT relayer_id_refs_id_4fa37a4a71ff7aa5 FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_56177ce05fb3e43; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT relayer_id_refs_id_56177ce05fb3e43 FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_63e41d5a7b0d0025; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT relayer_id_refs_id_63e41d5a7b0d0025 FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_7f061d282afdffbc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT relayer_id_refs_id_7f061d282afdffbc FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_c53f0e75; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT relayer_id_refs_id_c53f0e75 FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: relayer_id_refs_id_e8f4d6e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT relayer_id_refs_id_e8f4d6e4 FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: response_to_id_refs_id_3a3b14e5a428ab89; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT response_to_id_refs_id_3a3b14e5a428ab89 FOREIGN KEY (response_to_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ruleset_id_refs_id_fb349cdd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT ruleset_id_refs_id_fb349cdd FOREIGN KEY (ruleset_id) REFERENCES flows_ruleset(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: run_id_refs_id_3c5208e6a8d5399a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionlog
    ADD CONSTRAINT run_id_refs_id_3c5208e6a8d5399a FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: run_id_refs_id_7a74adea7882cf3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT run_id_refs_id_7a74adea7882cf3d FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: run_id_refs_id_a0acbaa9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT run_id_refs_id_a0acbaa9 FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: saved_by_id_refs_id_a8ea6f14; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT saved_by_id_refs_id_a8ea6f14 FOREIGN KEY (saved_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedule_id_refs_id_5319e4b7780eb68f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT schedule_id_refs_id_5319e4b7780eb68f FOREIGN KEY (schedule_id) REFERENCES schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedule_id_refs_id_770d8203a7c87a5d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT schedule_id_refs_id_770d8203a7c87a5d FOREIGN KEY (schedule_id) REFERENCES schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: search_id_refs_id_37bd94af289e5d34; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_searchposition
    ADD CONSTRAINT search_id_refs_id_37bd94af289e5d34 FOREIGN KEY (search_id) REFERENCES dashboard_search(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: sms_id_refs_id_6afda843f07d0887; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT sms_id_refs_id_6afda843f07d0887 FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: sms_id_refs_id_6ce29883cc671bee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT sms_id_refs_id_6ce29883cc671bee FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: sms_id_refs_id_cbffe71ce9c944e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT sms_id_refs_id_cbffe71ce9c944e FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: start_id_refs_id_07e3fbae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT start_id_refs_id_07e3fbae FOREIGN KEY (start_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: sync_event_id_refs_id_1fa4ecc9f2d11a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT sync_event_id_refs_id_1fa4ecc9f2d11a4 FOREIGN KEY (sync_event_id) REFERENCES channels_syncevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: topup_id_refs_id_37a3abe8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT topup_id_refs_id_37a3abe8 FOREIGN KEY (topup_id) REFERENCES orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: trigger_id_refs_id_1ef74137b8d38993; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT trigger_id_refs_id_1ef74137b8d38993 FOREIGN KEY (trigger_id) REFERENCES triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: trigger_id_refs_id_f42ab82ea7d3bbe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT trigger_id_refs_id_f42ab82ea7d3bbe FOREIGN KEY (trigger_id) REFERENCES triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_1851bb7c05c4f994; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT user_id_refs_id_1851bb7c05c4f994 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_40c41112; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT user_id_refs_id_40c41112 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_44820666ba86f712; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT user_id_refs_id_44820666ba86f712 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_4aadac60a67c4fc8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT user_id_refs_id_4aadac60a67c4fc8 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_4dc23c39; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT user_id_refs_id_4dc23c39 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_614e2019c95e8429; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT user_id_refs_id_614e2019c95e8429 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_7fd06f635656ace4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT user_id_refs_id_7fd06f635656ace4 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_db93ce6a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_usersettings
    ADD CONSTRAINT user_id_refs_id_db93ce6a FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: user_id_refs_id_e4b08bac101bc94; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT user_id_refs_id_e4b08bac101bc94 FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_failedlogin_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_failedlogin
    ADD CONSTRAINT users_failedlogin_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_passwordhistory_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_passwordhistory
    ADD CONSTRAINT users_passwordhistory_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: users_recoverytoken_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: website_id_refs_id_14e5edf5d5f100e0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_pagerank
    ADD CONSTRAINT website_id_refs_id_14e5edf5d5f100e0 FOREIGN KEY (website_id) REFERENCES dashboard_website(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: website_id_refs_id_1a3d74c2c915af30; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_searchposition
    ADD CONSTRAINT website_id_refs_id_1a3d74c2c915af30 FOREIGN KEY (website_id) REFERENCES dashboard_website(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: worker_id_refs_id_13af6e2204e3453a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_taskstate
    ADD CONSTRAINT worker_id_refs_id_13af6e2204e3453a FOREIGN KEY (worker_id) REFERENCES djcelery_workerstate(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public; Type: ACL; Schema: -; Owner: -
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM rowan;
GRANT ALL ON SCHEMA public TO rowan;
GRANT ALL ON SCHEMA public TO root;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

