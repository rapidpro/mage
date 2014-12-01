package io.rapidpro.mage.temba;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.rapidpro.mage.util.JsonUtils;
import io.rapidpro.mage.util.MageUtils;
import com.sun.jersey.api.client.ClientResponse;
import com.sun.jersey.api.client.WebResource;
import com.sun.jersey.api.representation.Form;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.lang.reflect.Field;

/**
 * Client for calls to the Temba API
 */
public class TembaClients {

    protected static final Logger log = LoggerFactory.getLogger(TembaClients.class);

    public static interface Client {
        ClientResponse call(TembaRequest request);
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
        public ClientResponse call(TembaRequest request) {
            com.sun.jersey.api.client.Client client = com.sun.jersey.api.client.Client.create();
            WebResource.Builder resource = client
                    .resource(m_apiUrl)
                    .path("mage")
                    .path(request.getAction())
                    .header("Authorization", "Token " + m_authKey);

            Form form = buildForm(request);
            ClientResponse response = resource.type(MediaType.APPLICATION_FORM_URLENCODED).post(ClientResponse.class, form);

            if (response.getStatusInfo().getFamily() != Response.Status.Family.SUCCESSFUL) {
                log.error("Temba API returned status " + response.getStatusInfo().getStatusCode() + " for " + JsonUtils.encode(request, true));
            }

            if (log.isDebugEnabled()) {
                String body = response.getEntity(String.class);
                log.debug(resource.toString() + " -> " + body);
            }

            return response;
        }
    }

    /**
     * Stub client - does nothing and returns 200 for all calls
     */
    protected static class StubClient implements Client {
        public ClientResponse call(TembaRequest request) {
            return new ClientResponse(200, null, null, null);
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
                form.putSingle(jsonProperty.value(), value);
            }
        }
        return form;
    }
}