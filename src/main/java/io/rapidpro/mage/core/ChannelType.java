package io.rapidpro.mage.core;

/**
 * Channel types
 */
public enum ChannelType {
    ANDROID("A"),
    AFRICAS_TALKING("AT"),
    ZENVIA("ZV"),
    EXTERNAL("EX"),
    NEXMO("NX"),
    INFOBIP("IB"),
    HUB9("H9"),
    TWILIO("T"),
    TWITTER("TT"),
    VUMI("VM");

    private final String m_code;

    ChannelType(String code) {
        m_code = code;
    }

    public static ChannelType fromString(String code) {
        for (ChannelType v : values()) {
            if (v.m_code.equals(code)) {
                return v;
            }
        }
        throw new IllegalArgumentException("'" + code + "' is not a valid channel type");
    }

    @Override
    public String toString() {
        return m_code;
    }
}