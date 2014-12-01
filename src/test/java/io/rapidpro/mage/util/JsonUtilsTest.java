package io.rapidpro.mage.util;

import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.rapidpro.mage.test.BaseMageTest;
import io.rapidpro.mage.test.TestPojo;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.util.JsonUtils}
 */
public class JsonUtilsTest extends BaseMageTest {

    @Test
    public void integration() {
        new JsonUtils();
    }

    /**
     * @see JsonUtils#parse(String)
     */
    @Test
    public void parse_shouldParseValidJson() {
        // check an object
        ObjectNode obj = (ObjectNode) JsonUtils.parse("{\"id\": 123, \"name\": \"Bob\"}");
        assertThat(obj.isObject(), is(true));
        assertThat(obj.get("id").intValue(), is(123));
        assertThat(obj.get("name").textValue(), is("Bob"));

        // check an array
        ArrayNode arr = (ArrayNode) JsonUtils.parse("[123, \"Bob\"]");
        assertThat(arr.isArray(), is(true));
        assertThat(arr.get(0).intValue(), is(123));
        assertThat(arr.get(1).textValue(), is("Bob"));

        // check that null or empty strings safely return null object
        assertThat(JsonUtils.parse(null), nullValue());
        assertThat(JsonUtils.parse(""), nullValue());
    }

    /**
     * @see JsonUtils#parse(String, Class)
     */
    @Test
    public void parse_withClass_shouldParseValidJsonAndUnmarshalObject() {
        TestPojo pojo = JsonUtils.parse("{\"test_int\":1,\"test_string\":\"RW\",\"test_enum\":\"YES\",\"test_node\":{\"foo\":\"bar\"}}", TestPojo.class);
        assertThat(pojo.getInt(), is(1));
        assertThat(pojo.getString(), is("RW"));
        assertThat(pojo.getNode().get("foo").textValue(), is("bar"));
        assertThat(pojo.getEnum(), is(TestPojo.Choice.YES));

        // check that null or empty strings safely return null object
        assertThat(JsonUtils.parse(null, TestPojo.class), nullValue());
        assertThat(JsonUtils.parse("", TestPojo.class), nullValue());
    }

    /**
     * @see JsonUtils#parse(String)
     */
    @Test(expected = IllegalArgumentException.class)
    public void parse_shouldThrowExceptionForInvalidJson() {
        JsonUtils.parse("{{}");
    }

    /**
     * @see JsonUtils#parseObject(String)
     */
    @Test
    public void parseObject_shouldParseValidJson() {
        // Check an object
        ObjectNode obj = JsonUtils.parseObject("{\"id\": 123, \"name\": \"Bob\"}");
        assertThat(obj.isObject(), is(true));
        assertThat(obj.get("id").intValue(), is(123));
        assertThat(obj.get("name").textValue(), is("Bob"));

        // Check that null or empty strings safely return null object
        assertThat(JsonUtils.parseObject(null), nullValue());
        assertThat(JsonUtils.parseObject(""), nullValue());
    }

    /**
     * @see JsonUtils#parse(String)
     */
    @Test(expected = IllegalArgumentException.class)
    public void parseObject_shouldThrowExceptionForInvalidJsonObject() {
        JsonUtils.parseObject("[]");
    }

    /**
     * @see JsonUtils#encode(com.fasterxml.jackson.databind.JsonNode)
     */
    @Test
    public void encode_node() {
        ObjectNode node = JsonUtils.object()
                .put("test_int", 1)
                .put("test_string", "RW")
                .put("test_enum", "YES");
        node.put("test_node", JsonUtils.object().put("foo", "bar"));

        assertThat(JsonUtils.encode(node), is("{\"test_int\":1,\"test_string\":\"RW\",\"test_enum\":\"YES\",\"test_node\":{\"foo\":\"bar\"}}"));
    }

    /**
     * @see JsonUtils#encode(Object, boolean)
     */
    @Test
    public void encode_object() {
        TestPojo pojo = new TestPojo(1, "RW", JsonUtils.object().put("foo", "bar"), TestPojo.Choice.MAYBE);

        assertThat(JsonUtils.encode(pojo, true), is("{\"test_int\":1,\"test_string\":\"RW\",\"test_enum\":\"MAYBE\",\"test_node\":{\"foo\":\"bar\"}}"));
    }

    /**
     * @see JsonUtils#encode(com.fasterxml.jackson.databind.JsonNode)
     */
    @Test(expected = RuntimeException.class)
    public void encode_shouldThrowExceptionIfObjectCantBeEncoded() {
        ObjectNode node = JsonUtils.object().putPOJO("test", new JsonUtils());
        JsonUtils.encode(node);
    }

    /**
     * @see JsonUtils#marshal(Object, boolean)
     */
    @Test
    public void marshal_shouldConvertPojoToNode() {
        TestPojo pojo = new TestPojo(1, "RW", JsonUtils.object().put("foo", "bar"), TestPojo.Choice.YES);

        ObjectNode node = JsonUtils.marshal(pojo, true);
        assertThat(node.get("test_int").intValue(), is(1));
        assertThat(node.get("test_string").textValue(), is("RW"));
        assertThat(node.get("test_enum").textValue(), is("YES"));
        assertThat(node.get("test_node").get("foo").textValue(), is("bar"));
    }

    /**
     * @see JsonUtils#unmarshal(com.fasterxml.jackson.databind.node.ObjectNode, Class, boolean)
     */
    @Test
    public void unmarshal_shouldConvertNodeToPojo() {
        ObjectNode node = JsonUtils.object()
                .put("test_int", 1)
                .put("test_string", "RW")
                .put("test_enum", "NO");
        node.put("test_node", JsonUtils.object().put("foo", "bar"));

        TestPojo pojo = JsonUtils.unmarshal(node, TestPojo.class, true);
        assertThat(pojo.getInt(), is(1));
        assertThat(pojo.getString(), is("RW"));
        assertThat(pojo.getNode().get("foo").textValue(), is("bar"));
        assertThat(pojo.getEnum(), is(TestPojo.Choice.NO));
    }
}