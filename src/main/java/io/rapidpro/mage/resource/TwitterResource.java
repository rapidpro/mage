package io.rapidpro.mage.resource;

import com.codahale.metrics.annotation.Timed;
import io.rapidpro.mage.api.StreamEvent;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.resource.exception.UnauthorizedException;
import io.rapidpro.mage.service.ServiceManager;
import io.rapidpro.mage.twitter.StreamOperation;
import io.rapidpro.mage.twitter.TwitterManager;
import com.sun.jersey.api.NotFoundException;

import javax.ws.rs.DELETE;
import javax.ws.rs.FormParam;
import javax.ws.rs.HeaderParam;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;

/**
 * Twitter stream management
 */
@Path("/twitter")
public class TwitterResource extends BaseResource {

    private static final String HEADER_AUTHORIZATION = "Authorization";

    private final TwitterManager m_twitter;
    private final String m_authToken;

    public TwitterResource(TwitterManager twitter, ServiceManager services, String authToken) {
        super(services);

        this.m_twitter = twitter;
        this.m_authToken = authToken;
    }

    @Timed
    @POST
    public Response addStream(@HeaderParam(HEADER_AUTHORIZATION) String auth,
                              @FormParam("uuid") String channelUuid) throws Exception {
        checkAuthorization(auth);

        ChannelContext channel = fetchChannel(channelUuid);

        m_twitter.requestStreamOperation(channel, StreamOperation.Action.ADD);

        StreamEvent event = new StreamEvent(channel.getChannelUuid(), StreamEvent.Result.ADDED, "");
        return Response.status(200).type(MediaType.APPLICATION_JSON).entity(event).build();
    }

    @Timed
    @POST
    @Path("/{uuid}")
    public Response updateStream(@HeaderParam(HEADER_AUTHORIZATION) String auth,
                                 @PathParam("uuid") String channelUuid) throws Exception {
        checkAuthorization(auth);

        ChannelContext channel = fetchChannel(channelUuid);

        m_twitter.requestStreamOperation(channel, StreamOperation.Action.UPDATE);

        StreamEvent event = new StreamEvent(channel.getChannelUuid(), StreamEvent.Result.UPDATED, "");
        return Response.status(200).type(MediaType.APPLICATION_JSON).entity(event).build();
    }

    @Timed
    @DELETE
    @Path("/{uuid}")
    public Response removeStream(@HeaderParam(HEADER_AUTHORIZATION) String auth,
                                 @PathParam("uuid") String channelUuid) throws Exception {
        checkAuthorization(auth);

        ChannelContext channel = fetchChannel(channelUuid);

        m_twitter.requestStreamOperation(channel, StreamOperation.Action.REMOVE);

        StreamEvent event = new StreamEvent(channel.getChannelUuid(), StreamEvent.Result.REMOVED, "");
        return Response.status(200).type(MediaType.APPLICATION_JSON).entity(event).build();
    }

    /**
     * TODO when Dropwizard 0.8 comes out with Jersey 2.x support, we can this with a filter
     */
    protected void checkAuthorization(String headerValue) {
        String[] parts = headerValue != null ? headerValue.split(" ") : new String[]{};
        if (parts.length != 2 || !parts[0].equals("Token") || !parts[1].equals(m_authToken)) {
            throw new UnauthorizedException();
        }
    }

    /**
     * Convenience method to fetch a channel and throw an exception if it doesn't exist
     * @param channelUuid the channel UUID
     * @return the channel context
     */
    protected ChannelContext fetchChannel(String channelUuid) {
        ChannelContext channel = getServices().getChannelService().getChannelByUuid(channelUuid);
        if (channel == null) {
            throw new NotFoundException("No such channel");
        }
        return channel;
    }
}