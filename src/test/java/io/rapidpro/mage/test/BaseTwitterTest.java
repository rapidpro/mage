package io.rapidpro.mage.test;

import io.rapidpro.mage.twitter.TwitterManager;
import org.junit.AfterClass;
import org.junit.BeforeClass;
import org.junit.Ignore;
import org.mockito.Mockito;
import twitter4j.DirectMessage;
import twitter4j.JSONArray;
import twitter4j.JSONObject;
import twitter4j.ResponseList;
import twitter4j.TwitterObjectFactory;
import twitter4j.User;

import java.util.ArrayList;
import java.util.List;

/**
 * Base class for tests that require a Twitter manager node
 */
@Ignore
public class BaseTwitterTest extends BaseServicesTest {

    private static TwitterManager s_twitter;

    @BeforeClass
    public static void setupTwitter() throws Exception {
        s_twitter = new TwitterManager(getServices(), getCache(), getTemba(), "abcd", "1234");
        s_twitter.start();

        // wait for this node to become master...
        while (!s_twitter.isMaster()) {
            Thread.sleep(10);
        }
    }

    @AfterClass
    public static void teardownTwitter() throws Exception {
        s_twitter.stop();
    }

    public static TwitterManager getTwitter() {
        return s_twitter;
    }

    protected DirectMessage createDirectMessage(String jsonFile) throws Exception {
        String json = loadResource(jsonFile);
        return TwitterObjectFactory.createDirectMessage(json);
    }

    protected User createTwitterUser(String jsonFile) throws Exception {
        String json = loadResource(jsonFile);
        return TwitterObjectFactory.createUser(json);
    }

    protected ResponseList<DirectMessage> createDirectMessageResponseList(String json) throws Exception {
        JSONArray array = new JSONArray(json);
        List<DirectMessage> list = new ArrayList<>();

        if (array.length() > 0) {
            for (int x = 0; x < array.length(); x++) {
                JSONObject obj = (JSONObject) array.get(x);
                DirectMessage msg = TwitterObjectFactory.createDirectMessage(obj.toString());
                list.add(msg);
            }
        }
        // Create a mock {@link ResponseList} that returns the statuses constructed
        // Only mock the toArray method, only one being used
        ResponseList<DirectMessage> responseList = Mockito.mock(ResponseList.class);
        Mockito.when(responseList.toArray(Mockito.any())).thenReturn(list.toArray());
        return responseList;
    }
}