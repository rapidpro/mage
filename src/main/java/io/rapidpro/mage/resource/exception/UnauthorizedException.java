package io.rapidpro.mage.resource.exception;

import javax.ws.rs.WebApplicationException;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;

/**
 * HTTP 401
 */
public class UnauthorizedException extends WebApplicationException {

    @Override
    public Response getResponse() {
        return Response.status(Response.Status.UNAUTHORIZED)
                .type(MediaType.TEXT_PLAIN)
                .entity("Authorization failed").build();
    }
}