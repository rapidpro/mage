package io.rapidpro.mage.core;

import com.fasterxml.jackson.annotation.JsonValue;
import com.google.i18n.phonenumbers.NumberParseException;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.google.i18n.phonenumbers.Phonenumber;

/**
 * A contact URN
 */
public class ContactUrn {

    public static enum Scheme {
        TEL(50),
        TWITTER(90);

        private int defaultPriority;

        Scheme(int defaultPriority) {
            this.defaultPriority = defaultPriority;
        }

        public int getDefaultPriority() {
            return defaultPriority;
        }

        @Override
        public String toString() {
            return name().toLowerCase();
        }
    }

    private Scheme m_scheme;

    private String m_path;

    public ContactUrn(Scheme scheme, String path) {
        this.m_scheme = scheme;
        this.m_path = path;
    }

    public Scheme getScheme() {
        return m_scheme;
    }

    public String getPath() {
        return m_path;
    }

    public void normalize(String country) {
        if (m_scheme == Scheme.TEL) {
            m_path = normalizeNumber(m_path, country);
        }
    }

    @JsonValue
    @Override
    public String toString() {
        return m_scheme + ":" + m_path;
    }

    /**
     * Normalizes the passed in number, they should be only digits, some backends prepend + and maybe crazy users put in
     * dashes or parentheses in the console
     * @param number the number
     * @param countryCode the 2-letter country code, e.g. US, RW
     * @return the normalized number
     */
    protected static String normalizeNumber(String number, String countryCode) {
        number = number.toLowerCase();

        // if the number ends with e11, then that is Excel corrupting it, remove it
        if (number.endsWith("e+11") || number.endsWith("e+12")) {
            number = number.substring(0, number.length() - 4).replace(".", "");
        }

        // remove other characters
        number = number.replaceAll("[^0-9a-z\\+]", "");

        // add on a plus if it looks like it could be a fully qualified number
        if (number.length() > 11 && number.charAt(0) != '+') {
            number = '+' + number;
        }

        PhoneNumberUtil phoneUtil = PhoneNumberUtil.getInstance();
        Phonenumber.PhoneNumber normalized = null;
        try {
            normalized = phoneUtil.parse(number, countryCode);
        } catch (NumberParseException e) {
        }

        // now does it look plausible ?
        try {
            if (phoneUtil.isValidNumber(normalized)) {
                return phoneUtil.format(normalized, PhoneNumberUtil.PhoneNumberFormat.E164);
            }
        } catch (NullPointerException ex) {
        }

        // this must be a local number of some kind, just lowercase and save
        return number.replaceAll("[^0-9a-z]", "");
    }
}