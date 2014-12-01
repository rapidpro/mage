package io.rapidpro.mage.util;

import com.fasterxml.jackson.annotation.JsonAutoDetect;
import com.fasterxml.jackson.annotation.PropertyAccessor;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.apache.commons.lang3.StringUtils;

import java.io.IOException;

/**
 * JSON utility methods
 */
public class JsonUtils {

    private static final ObjectMapper s_mapper = new ObjectMapper();

    static {
        disableMapperAutoDetection(s_mapper);
    }

    /**
     * Disables all auto-detection of fields and properties
     * @param mapper the object mapper
     */
    public static void disableMapperAutoDetection(ObjectMapper mapper) {
        mapper.setVisibility(PropertyAccessor.FIELD, JsonAutoDetect.Visibility.NONE);
        mapper.setVisibility(PropertyAccessor.GETTER, JsonAutoDetect.Visibility.NONE);
        mapper.setVisibility(PropertyAccessor.IS_GETTER, JsonAutoDetect.Visibility.NONE);
        mapper.setVisibility(PropertyAccessor.SETTER, JsonAutoDetect.Visibility.NONE);
    }

    /**
     * Creates a new empty object node
     * @return the empty node
     */
    public static ObjectNode object() {
        return s_mapper.createObjectNode();
    }

    /**
     * Parses the given JSON string into a node. Returns null for null or empty strings
     * @param json the string
     * @return the node
     */
    public static JsonNode parse(String json) {
        if (StringUtils.isEmpty(json)) {
            return null;
        }

        try {
            return s_mapper.readTree(json);
        } catch (IOException e) {
            throw new IllegalArgumentException(e);
        }
    }

    /**
     * Parses the given JSON string into. Returns null for null or empty strings
     * @param json the string
     * @return the node
     */
    public static <T> T parse(String json, Class<T> clazz) {
        ObjectNode node = parseObject(json);
        return node != null ? unmarshal(node, clazz, true) : null;
    }

    /**
     * Parses the given JSON string into an object. Returns null for null or empty strings
     * @param json the string
     * @return the object node
     */
    public static ObjectNode parseObject(String json) {
        JsonNode node = parse(json);
        if (node instanceof ObjectNode) {
            return (ObjectNode) node;
        }
        else if (node == null) {
            return null;
        }

        throw new IllegalArgumentException("JSON does not contain an object");
    }

    /**
     * Encodes a node as a string
     * @param node the node
     * @return the string
     */
    public static String encode(JsonNode node) {
        try {
            return s_mapper.writeValueAsString(node);
        } catch (JsonProcessingException e) {
            throw new RuntimeException(e);
        }
    }

    /**
     * Encodes an object as a string
     * @param object the object
     * @param byAnnotation whether serialization should be by annotation only
     * @return the string
     */
    public static <T> String encode(T object, boolean byAnnotation) {
        ObjectNode node = marshal(object, byAnnotation);
        return encode(node);
    }

    /**
     * Marshals a POJO into a node (assumes POJO's fields are annotated with @JsonProperty)
     * @param obj the POJO
     * @param byAnnotation whether serialization should be by annotation only
     * @return the node
     */
    public static ObjectNode marshal(Object obj, boolean byAnnotation) {
        return byAnnotation ? s_mapper.valueToTree(obj) : new ObjectMapper().valueToTree(obj);
    }

    /**
     * Unmarshals a node into a POJO (assumes POJO's fields are annotated with @JsonProperty)
     * @param node the node
     * @param clazz the POJO class
     * @param byAnnotation whether serialization should be by annotation only
     * @return the node
     */
    public static <T> T unmarshal(ObjectNode node, Class<T> clazz, boolean byAnnotation) {
        return byAnnotation ? s_mapper.convertValue(node, clazz) : new ObjectMapper().convertValue(node, clazz);
    }
}