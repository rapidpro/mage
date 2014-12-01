package io.rapidpro.mage.test;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Ignore;

/**
 * POJO for testing JSON serialization
 */
@Ignore
public class TestPojo {

    public enum Choice {
        YES, NO, MAYBE
    }

    @JsonProperty("test_int")
    private int m_int;

    @JsonProperty("test_string")
    private String m_string;

    @JsonProperty("test_enum")
    private Choice m_choice;

    @JsonProperty("test_node")
    private JsonNode m_node;

    public TestPojo() {
    }

    public TestPojo(int anInt, String string, JsonNode node, Choice choice) {
        m_int = anInt;
        m_string = string;
        m_node = node;
        m_choice = choice;
    }

    public int getInt() {
        return m_int;
    }

    public String getString() {
        return m_string;
    }

    public Choice getEnum() {
        return m_choice;
    }

    public JsonNode getNode() {
        return m_node;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;

        TestPojo testPojo = (TestPojo) o;

        if (m_int != testPojo.m_int) return false;
        if (m_choice != testPojo.m_choice) return false;
        if (m_node != null ? !m_node.equals(testPojo.m_node) : testPojo.m_node != null) return false;
        if (m_string != null ? !m_string.equals(testPojo.m_string) : testPojo.m_string != null) return false;

        return true;
    }

    @Override
    public int hashCode() {
        int result = m_int;
        result = 31 * result + (m_string != null ? m_string.hashCode() : 0);
        result = 31 * result + (m_choice != null ? m_choice.hashCode() : 0);
        result = 31 * result + (m_node != null ? m_node.hashCode() : 0);
        return result;
    }
}
