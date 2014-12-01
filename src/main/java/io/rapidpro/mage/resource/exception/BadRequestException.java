package io.rapidpro.mage.resource.exception;

import io.rapidpro.mage.api.MessageEvent;

import javax.ws.rs.WebApplicationException;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;

/**
 * 400
 */
public class BadRequestException extends WebApplicationException {

    private Integer m_messageId;

    private String m_description;

    public BadRequestException(int messageId, String description) {
        m_messageId = messageId;
        m_description = description;
    }

    public BadRequestException(String description) {
        m_description = description;
    }

    @Override
    public Response getResponse() {
        MessageEvent event = new MessageEvent(m_messageId, MessageEvent.Result.ERROR, m_description);

        return Response.status(Response.Status.BAD_REQUEST)
                .type(MediaType.APPLICATION_JSON)
                .entity(event).build();
    }
}
