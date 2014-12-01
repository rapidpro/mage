package io.rapidpro.mage.core;

/**
 * Message status
 */
public enum Status {
    PENDING("P"),
    QUEUED("Q"),
    WIRED("W"),
    SENT("S"),
    DELIVERED("D"),
    HANDLED("H"),
    ERRORED("E"),
    FAILED("F"),
    RESENT("R");

    private final String m_code;

    Status(String code) {
        m_code = code;
    }

    public static Status fromString(String str) {
        for (Status s : values()) {
            if (s.m_code.equals(str)) {
                return s;
            }
        }
        throw new IllegalArgumentException("'" + str + "' is not a valid message status");
    }

    @Override
    public String toString() {
        return m_code;
    }
}