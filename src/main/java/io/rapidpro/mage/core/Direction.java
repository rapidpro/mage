package io.rapidpro.mage.core;

/**
 * Message direction
 */
public enum Direction {
    INCOMING("I"),
    OUTGOING("O");

    private final String m_code;

    Direction(String code) {
        m_code = code;
    }

    public static Direction fromString(String str) {
        for (Direction s : values()) {
            if (s.m_code.equals(str)) {
                return s;
            }
        }
        throw new IllegalArgumentException("'" + str + "' is not a valid message direction");
    }

    @Override
    public String toString() {
        return m_code;
    }
}