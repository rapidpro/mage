package io.rapidpro.mage.util;

import javax.ws.rs.core.MultivaluedMap;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * General utility methods
 */
public class MageUtils {

    /**
     * Jersey uses MultivaluedMaps to represent request data but other places (e.g. Twilio client ) need 1:1 maps
     * This method just takes the last item for each parameter value.
     * @param incoming the map of values lists
     * @return the simplified map
     */
    public static <K, V> Map<K, V> simplifyMultivaluedMap(MultivaluedMap<K, V> incoming) {
        Map<K, V> params = new HashMap<>();
        for (Map.Entry<K, List<V>> entry : incoming.entrySet()) {
            List<V> values = entry.getValue();

            if (values.size() > 0) {
                params.put(entry.getKey(), values.get(values.size() - 1));
            }
        }

        return params;
    }

    /**
     * Encodes a map as a string
     * @param map the map to encode
     * @param assignOp the text to join keys and values
     * @param joinOp the text to join entries
     * @return the encoded string
     */
    public static <K, V> String encodeMap(Map<K, V> map, String assignOp, String joinOp) {
        return map.entrySet().stream().map(e -> e.getKey() + assignOp + e.getValue()).collect(Collectors.joining(joinOp));
    }

    /**
     * Gets the value of field on the given instance
     * @param field the field
     * @param instance the object instance
     * @return the value
     */
    public static Object getFieldValue(Field field, Object instance) {
        try {
            field.setAccessible(true);
            return field.get(instance);
        } catch (IllegalAccessException e) {
            throw new RuntimeException(e);
        }
    }
}