package io.rapidpro.mage.temba;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.rapidpro.mage.util.JsonUtils;
import io.rapidpro.mage.util.MageUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.ws.rs.client.ClientBuilder;
import javax.ws.rs.client.Entity;
import javax.ws.rs.client.WebTarget;
import javax.ws.rs.core.Form;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.lang.reflect.Field;

/**
 * Client for calls to the Temba API
 */
public class TembaClients {

    protected static final Logger log = LoggerFactory.getLogger(TembaClients.class);

    public static interface Client {
        Response call(TembaRequest request);
    }

    /**
     * Default REST client - makes real web service requests
     */
    protected static class DefaultClient implements Client {
        private final String m_apiUrl;
        private final String m_authKey;

        public DefaultClient(String apiUrl, String authKey) {
            m_apiUrl = apiUrl;
            m_authKey = authKey;

            log.info("Created Temba client (url=" + m_apiUrl + ")");
        }

        /**
         * Calls the API with the given request
         * @param request the request
         * @return the client response
         */
        public Response call(TembaRequest request) {
            javax.ws.rs.client.Client client = ClientBuilder.newClient();
            WebTarget target = client.target(m_apiUrl)
                    .path("mage")
                    .path(request.getAction());

            Form form = buildForm(request);

            Response response = target.request(MediaType.APPLICATION_FORM_URLENCODED)
                    .header("Authorization", "Token " + m_authKey)
                    .post(Entity.form(form));

            log.info(target.getUri().toString() + " responded with status " + response.getStatus());

            if (log.isDebugEnabled()) {
                String body = response.readEntity(String.class);
                log.debug(target.toString() + " -> " + body);
            }

            return response;
        }
    }

    /**
     * Stub client - does nothing and returns 200 for all calls
     */
    protected static class StubClient implements Client {
        public Response call(TembaRequest request) {
            return Response.ok().build();
        }
    }

    /**
     * Gets a Temba client instance
     * @param apiUrl the complete API URL
     * @param authKey the authorization key
     */
    public static Client getClient(String apiUrl, String authKey, boolean production) {
        return production ? new DefaultClient(apiUrl, authKey) : new StubClient();
    }

    /**
     * Builds a submittable form from a request object
     * @param request the request
     * @return the form
     */
    protected static Form buildForm(TembaRequest request) {
        Form form = new Form();
        for (Field field : request.getClass().getDeclaredFields()) {
            JsonProperty jsonProperty = field.getAnnotation(JsonProperty.class);
            if (jsonProperty == null) {
                continue;
            }

            Object value = MageUtils.getFieldValue(field, request);
            if (value != null) {
                form.param(jsonProperty.value(), String.valueOf(value));
            }
        }
        return form;
    }
}